extends Node2D
## 《百炼》M1 自动操作回放（demo reel）
##
## 目的：把 M1 的验收清单做成一段「可观看的自动操作录像」——
##       脚本自己注入按键、自己打字幕、自己录帧。不需要人在场，不需要装插件。
##
## 运行方式：
##   录成 PNG 序列（再交给 ffmpeg 合成 mp4）：
##     godot --path . --write-movie build/reel/frame.png --fixed-fps 60 res://tests/demo_reel.tscn
##   只在屏幕上看，不录：
##     godot --path . res://tests/demo_reel.tscn
##
## 画面上的遥测不是装饰：on_floor / coyote / buffer / velocity 都是引擎里实时读出来的。
## 土狼时间和跳跃缓冲这类「玩家感觉不到」的机制，只能靠把计时器打出来证明它真的在工作。
##
## 时序约定（与 tests/test_m1.gd 相同的坑）：
##   Input.parse_input_event 是排队处理的，注入之后要过 2 个物理帧玩家才真正响应。
##   所以每段动作开头留 2 帧「预备期」，字幕延后到预备期结束才出，
##   否则字幕会先于画面出现，看起来像在说谎。

const LEAD_FRAMES := 2
const TRAIL_MAX := 90

## 参与回放的动作。_apply_hold 每一步都会把这批动作整体同步成步骤声明值，
## 所以每个步骤的 hold 字典就是「这一步期间按住哪些键」的完整声明，不会漏松键。
const ACTIONS := ["move_left", "move_right", "jump", "attack", "dodge"]

const COL_BG   := Color(0.13, 0.12, 0.11, 0.92)
const COL_FG   := Color(0.94, 0.92, 0.88)
const COL_DIM  := Color(0.63, 0.60, 0.56)
const COL_HI   := Color(0.95, 0.87, 0.46)
const COL_TRAIL := Color(0.98, 0.85, 0.35)

var _player: CharacterBody2D
var _dummy: Node2D
var _dummy_health: Health
var _cap_label: Label
var _tele_label: Label
var _title_label: Label

var _trail: Line2D
var _apex_line: Line2D

var _steps: Array = []
var _i := -1
var _phase := 0            # 0 = 预备期，1 = 正式期
var _t := 0
var _tick := 0
var _held: Dictionary = {}
var _pts: Array[Vector2] = []
var _running := true

# ── 观测记录：用来核对字幕说的和引擎做的是不是一回事 ──────────────
var _air_frames := 0
var _press_frame := -1
var _press_airborne := false
var _floor_since_press := false
var _prev_vy := 0.0
var _jumps: Array = []
var _marks: Array = []
var _flights: Array = []
var _was_air := false
var _flight_start := 0.0
var _flight_min := 0.0
var _flight_cause := "fall"
var _prev_y := 0.0

# ── 战斗观测 ──
var _hp_events: Array = []       # 靶子血量每一次变化
var _last_hp := -1
var _last_hits := 0
var _dodge_log: Array = []       # 每一次闪避的起止 x
var _dodge_from := 0.0
var _dodge_running := false
var _last_dodges := 0
var _prev_px := 0.0              # 上一帧的 x（闪避起点要减掉观察延迟）
var _drift: Dictionary = {}      # 每个动作连续「掉了」多少帧
var _input_drifts := 0           # 补针次数
var _kills: Array = []           # 靶子被打死的帧号
var _was_dead := false
var _atk_press_frames: Array = []


func _ready() -> void:
	_player = get_node_or_null("TestRoom/Player") as CharacterBody2D
	if _player == null:
		printerr("[reel] 找不到 TestRoom/Player")
		get_tree().quit()
		return

	_dummy = get_node_or_null("TestRoom/TargetDummy") as Node2D
	if _dummy == null:
		printerr("[reel] 找不到 TestRoom/TargetDummy")
		get_tree().quit()
		return
	_dummy_health = _dummy.get_node("Health")

	# 把攻击判定框画出来。平时是关的（调手感时才开），回放里必须开 ——
	# 「前摇 / 判定 / 后摇」这三段时间光看角色是看不出来的，红框亮起才是判定的开始。
	var hb := _player.get_node_or_null("Hitbox")
	if hb != null:
		hb.set("debug_draw", true)

	var hint := get_node_or_null("TestRoom/Hint")
	if hint != null:
		(hint as CanvasItem).visible = false

	# 初始位置先喂给 _prev_y：角色出生在空中会先落一段，不预置的话
	# 那一段会被记成一次「从 y=0 起跳」的假事件。
	_prev_y = _player.global_position.y
	_flight_start = _player.global_position.y
	_flight_min = _player.global_position.y

	_make_overlays()
	_build_steps()
	_enter(0)


# ═══════════════════════════════════════════════════════════════════
# 回放剧本
# ═══════════════════════════════════════════════════════════════════

func _build_steps() -> void:
	_add({}, 30, "① 静止 — 色块默认朝右")
	_add({"move_right": true}, 40, "② 按住 → / D：约 5 帧到全速 180 px/s，不是缓慢加速")
	_add({}, 26, "③ 松手：约 4 帧停住，滑行不到 8 px — 几乎没有惯性拖拽")
	_add({"move_left": true}, 26, "④ 按住 ← / A：白色「脸」翻到左侧")
	_add({"move_left": true, "move_right": true}, 30, "⑤ 同时按住 ← 和 →：方向归零，立刻停下")
	_add({}, 24, "⑥ 松手之后：朝向保持不动，不弹回右侧")

	# ── 跳跃：看画面上的 v 与 pos，配合地面网格判断高度 ──
	_add({}, 12, "")
	_add({"jump": true}, 6, "⑦ 起跳 — 初速 -420 px/s，离地最高约 77 px")
	_add({}, 52, "⑧ 完整跳跃：上升 21 帧 / 下落 17 帧 → 下落更快，手感偏「脆」")
	_add({}, 14, "")

	# ── 助跑跳上高台（PlatformB：台面比地面高 61 px，横向 452..548）──
	_add({"move_right": true}, 55, "⑨ 助跑 …… 目标是把右上那块高台当台阶踩上去")
	_add({"move_right": true, "jump": true}, 6, "⑨ 起跳")
	_add_wait({"move_right": true}, _pred_on_platform, 90,
		"⑨ 落上高台 — 台高 61 px，跳跃高度 77 px，余量 16 px")
	_add({}, 26, "⑨ 站定在台面上（松手即停）")

	# ── 土狼时间：走出台边之后仍然能跳 ──
	# 往左走出台缘：右侧那块空地站着靶子，往右走会直接落到它头顶上，
	# 那是另一种玩法（站桩上），不该混进土狼时间的演示里。
	_add_wait({"move_left": true}, _pred_left_ground, 120,
		"⑩ 往左走，一直走到走出台边（注意 coyote 从 0.100 开始倒数）")
	_add({"move_left": true}, 2,
		"⑩ 已经踏空了 —— 脚下没有台面，正在往下掉，coyote 在倒数")
	_add({"move_left": true, "jump": true}, 6,
		"⑩ 踏空之后才按的跳 —— 土狼时间内依然起跳成功")
	_add({}, 70, "⑩ 落地。这一跳是「凭空」发生的，因为脚下已经没有台面了")

	# ── 跳跃缓冲：落地前提前按跳，落地瞬间自动接跳 ──
	_add({}, 20, "")
	_add({"jump": true}, 6, "⑪ 先跳一次，制造一次自由落体")
	_add_wait({}, _pred_near_ground, 200,
		"⑪ 下落中 …… 在离落地还有几帧时按下跳（buffer 会亮起来）")
	_add({"jump": true}, 4, "⑪ 落地前按下跳 —— 落地瞬间自动接上跳跃（跳跃缓冲）")
	_add({}, 70, "⑪ 缓冲跳跃成功：这一次起跳发生在落地的那一帧，而不是按键的那一帧")

	# ═══════════════════════════════════════════════════════════════
	# 战斗：J 攻击 / K 闪避。右边那个深红色块是训练靶子，头顶有血条
	# ═══════════════════════════════════════════════════════════════
	_add({}, 24, "■ 移动 / 跳跃演示到此结束。下面是战斗 —— J 攻击，K 闪避")

	# 走向靶子。注意这一步必须【向右】走：角色只有在真的移动时才会翻面，
	# 从左边一路向左走过来会面朝左，之后所有攻击全部打空（踩过一次）。
	_add_wait({"move_right": true}, _pred_touch_dummy, 240,
		"⑫ 向右走向靶子 —— 靶子有车身碰撞，会把你挡在它身前")
	_add({}, 30, "⑫ 站定。角色面朝右，靶子头顶的血条是满的（120 / 120）")

	# ⑬ 单次攻击：前摇 → 判定 → 后摇
	_add({"attack": true}, 4,
		"⑬ 按一下 J：出第 1 段。身前那个红框是攻击判定框 —— 现在还没亮（前摇 6 帧）")
	_add({}, 12, "⑬ 判定框亮起 → 命中：靶子闪白、掉血、飘出伤害数字，同时双方一起顿帧")
	_add({}, 34, "⑬ 一次挥砍的判定持续 4 帧，但只结算一次伤害 —— 不是打 4 下")

	# ⑭ 三段连招
	_add({"attack": true}, 4, "⑭ 连按 J —— 第 1 段")
	_add({}, 8, "⑭ 这一下按在收招里：按键被「记住」了，不是丢掉（连招缓冲）")
	_add({"attack": true}, 4, "⑭ 衔接窗口一开，自动接上第 2 段")
	_add({}, 8, "⑭ …")
	_add({"attack": true}, 4, "⑭ 第 3 段 —— 重击：伤害 22、顿帧更长、靶子后仰更狠")
	_add({}, 6, "⑭ 第 3 段带收招硬直。现在就猛按 J，看它接不接第 4 段")
	_add({"attack": true}, 4, "⑭ 再按 J ……")
	_add({}, 4, "⑭ …… 没反应。这一段配的就是 chainable = false")
	_add({}, 44, "⑭ 三段就是三段。出招次数和靶子挨打次数打在下面的遥测里")

	# ⑮ 闪避：位移 + 无敌帧
	_add({"move_left": true, "dodge": true}, 4, "⑮ 按住 ← 再按 K：朝左闪避，方向可控")
	_add({}, 26, "⑮ 闪出去了 —— 22 帧挪了约 119 px；同样帧数全程跑满也只有 66 px")
	_add({}, 30, "⑮ 闪避第 2~18 帧是无敌的（遥测里的 invul 会亮）。M1 靶子不还手，只能看遥测")

	# ⑯ 闪避打断攻击（紧接着按，赶在判定生效之前打断）
	_add_wait({"move_right": true}, _pred_touch_dummy, 240, "⑯ 走回靶子面前")
	_add({}, 20, "⑯ 站定")
	_add({"attack": true}, 4, "⑯ 按 J 出招 ……")
	_add({"move_left": true, "dodge": true}, 4,
		"⑯ 挥砍还没打到人，就按 K —— 出招硬直可以被打断（被贴身时的退路）")
	_add({}, 34, "⑯ 已经闪到左边：出招让位给闪避，不是把按键吃掉")

	# ⑰ 打死 → 满血重生
	_add_wait({"move_right": true}, _pred_touch_dummy, 240, "⑰ 再走回靶子面前，这回把它打死")
	_add({}, 20, "⑰ 站定")
	for k in 9:
		_add({"attack": true}, 4, "⑰ 连打 J ……" if k == 0 else "")
		_add({}, 8, "")
	_add({}, 40, "⑰ 血条清空 —— 靶子淡出、关掉受击，打不着了")
	_add({}, 120, "⑰ 1.3 秒后满血重生，可以接着打 —— 这就是「反复打这个靶子」的循环")

	_add({}, 60, "■ 回放结束 — 移动 / 跳跃 / 三段连招 / 闪避 / 靶子重生，全程脚本自动操作")


## 已经被靶子的车身挡住（贴在它身前）。用它当「走到位了」的判据，
## 比写死一个 x 更稳：靶子挪位置，剧本不用跟着改。
func _pred_touch_dummy() -> bool:
	if _player == null or _dummy == null:
		return false
	return _player.global_position.x >= _dummy.global_position.x - 30.0


## 走出台边：脚下没有支撑
func _pred_left_ground() -> bool:
	return _player != null and not _player.is_on_floor()


## 已经站到高台上（y=243，明显高于地面站立高度 304）
func _pred_on_platform() -> bool:
	if _player == null:
		return false
	return _player.is_on_floor() and _player.global_position.y < 280.0


## 下落中、且预计离落地只剩几帧。
##
## 这里不能用「距离地面多少像素」判断——自由落体越接近地面速度越快，
## 离地 12 px 时速度已经到 8.5 px/帧，按距离触发只会提前 1 帧按下去，
## 根本压不到跳跃缓冲的窗口上。必须按「预计剩余帧数」触发。
##
## 要求剩余 ≤ 6 帧而不是 8 帧：注入按键本身要 2 帧才被玩家脚本读到，
## 6 帧缓冲窗口减去这 2 帧，真正能用的只有 4 帧左右。
func _pred_near_ground() -> bool:
	if _player == null or _player.velocity.y <= 0.0:
		return false
	const GROUND_STAND_Y := 304.0   # 本测试房间的地面站立高度
	const G := 1200.0 * 1.6         # 下落重力 = default_gravity × fall_gravity_scale
	var remain := GROUND_STAND_Y - _player.global_position.y
	if remain <= 0.0:
		return true
	var v := _player.velocity.y
	var t := (-v + sqrt(v * v + 2.0 * G * remain)) / G
	return t * 60.0 <= 6.0


func _add(hold: Dictionary, frames: int, cap: String) -> void:
	_steps.append({"hold": hold, "frames": frames, "cap": cap})


func _add_wait(hold: Dictionary, pred: Callable, limit: int, cap: String) -> void:
	_steps.append({"hold": hold, "wait": pred, "max": limit, "cap": cap})


# ═══════════════════════════════════════════════════════════════════
# 帧循环
# ═══════════════════════════════════════════════════════════════════

func _physics_process(_delta: float) -> void:
	if not _running:
		return
	_tick += 1
	_observe()

	if _i >= _steps.size():
		_finish()
		return

	var s: Dictionary = _steps[_i]

	# 每帧复查一次「该按住的键是不是还按着」——见 _resync_holds 的说明
	_resync_holds()

	if _phase == 0:
		_t += 1
		if _t >= LEAD_FRAMES:
			_phase = 1
			_t = 0
			var cap := str(s.get("cap", ""))
			if cap != "":
				_cap_label.text = cap
		return

	_t += 1
	var go := false
	if s.has("wait"):
		go = bool((s["wait"] as Callable).call()) and _t >= 3
	else:
		go = _t >= int(s.get("frames", 1))
	if _t >= int(s.get("max", 100000)):
		# 等待步骤超时说明「条件一直没满足」——多半是输入掉了或者剧本写错了。
		# 不能静默跳过：从这里开始后面每一帧的画面都和字幕对不上。
		if s.has("wait"):
			print("[reel][WARN] f=%d 等待步骤超时（跑了 %d 帧条件仍未满足）: %s" % [
				_tick, _t, str(s.get("cap", ""))])
		go = true

	if go:
		_enter(_i + 1)

	_update_tele()
	_push_trail()


func _enter(idx: int) -> void:
	# 记录离开上一步时的状态 —— 用来核对剧本有没有演成我以为的样子
	if idx >= 1 and idx <= _steps.size() and _player != null:
		var prev: Dictionary = _steps[idx - 1]
		_marks.append({
			"step": idx - 1,
			"cap": str(prev.get("cap", "")) ,
			"x": _player.global_position.x,
			"y": _player.global_position.y,
			"floor": _player.is_on_floor(),
			"tick": _tick,
		})
	_i = idx
	_t = 0
	_phase = 0
	if idx >= _steps.size():
		return
	var s: Dictionary = _steps[idx]
	_apply_hold(s.get("hold", {}))


func _apply_hold(h: Dictionary) -> void:
	for a in ACTIONS:
		var want := bool(h.get(a, false))
		if want == bool(_held.get(a, false)):
			continue
		_held[a] = want
		if a == "jump" and want:
			_press_frame = _tick
			_press_airborne = not _player.is_on_floor()
			_floor_since_press = false
		if a == "attack" and want:
			_atk_press_frames.append(_tick)
		_inject(a, want)


## 复查注入的按键有没有「掉」。录制窗口一旦失去焦点，引擎会把所有按住的键全部释放
## —— 这是正确行为（玩家切出去时键确实该松开），但注入的键走的是同一套状态，
## 于是「按住方向键一直走」会在失焦那一刻变成「停在原地」，
## 后面的等待步骤永远等不到条件，整段回放从那里开始全偏。
## 实测咬过一次：窗口模式录出来的帧号比无头跑出来的多 200 帧，画面从那一刻起和字幕错位。
##
## 处理方式：每帧复查，连续 2 帧发现状态不对才补一针（刚注入那一帧状态还没刷新，不能算）。
## 补针会打日志，不静默自愈 —— 回放要不要重录，得能看到这件事发生过。
func _resync_holds() -> void:
	for a in ACTIONS:
		if not bool(_held.get(a, false)):
			_drift[a] = 0
			continue
		if Input.is_action_pressed(a):
			_drift[a] = 0
			continue
		_drift[a] = int(_drift.get(a, 0)) + 1
		if _drift[a] >= 2:
			_drift[a] = 0
			_input_drifts += 1
			print("[reel][WARN] f=%d 注入的「按住 %s」掉了（窗口失焦？），已补回" % [_tick, a])
			_inject(a, true)


func _inject(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _observe() -> void:
	if _player == null:
		return

	# 安全网：剧本编排失误把角色送出场景时，救回来并大声报错。
	# 不能静默忽略 —— 掉进虚空说明剧本和我的预期不一致，必须能看见。
	if _player.global_position.y > 420.0:
		printerr("[reel][WARN] 角色掉出场景 y=%.1f @frame %d —— 剧本编排有误" % [
			_player.global_position.y, _tick])
		_player.global_position = Vector2(320.0, 200.0)
		_player.velocity = Vector2.ZERO

	var y_now := _player.global_position.y
	var grounded := _player.is_on_floor()
	var vy := _player.velocity.y

	# 起跳的判定：速度在某帧从「不向上」变成「明显向上」。
	#
	# 注意此时读到的 y 已经比真正起跳的位置高了一帧的量：玩家脚本是在上一帧
	# 里把 velocity.y 定成 -420 并立刻 move_and_slide 的，所以本帧开头读到的
	# 位置已经往上走了 7 px。用 _prev_y 才是起跳那一帧之前的位置。
	var is_impulse := vy < -200.0 and _prev_vy > -200.0
	var just_left := (not grounded) and (not _was_air)

	if is_impulse:
		_flight_start = _prev_y
		_flight_min = _prev_y
		_flight_cause = "jump"
		_jumps.append({
			"n": _jumps.size() + 1,
			"press": _press_frame,
			"dt": _tick - _press_frame,
			"frame": _tick,
			"x": _player.global_position.x,
			"press_air": _press_airborne,
			"mid_floor": _floor_since_press,
		})
		_flash_apex()
	elif just_left:
		# 没按跳就离地了 —— 走出边缘或者被撞飞，记成一次「掉落」而不是「起跳」
		_flight_start = y_now
		_flight_min = y_now
		_flight_cause = "fall"

	if grounded:
		if _was_air:
			_flights.append({
				"n": _flights.size() + 1,
				"cause": _flight_cause,
				"from_y": _flight_start,
				"min_y": _flight_min,
				"h": _flight_start - _flight_min,
			})
		_was_air = false
		_air_frames = 0
	else:
		_was_air = true
		_air_frames += 1
		_flight_min = minf(_flight_min, y_now)

	# 按跳之后、真正起跳之前，脚有没有重新踩到地面？
	#   踩到了   → 这是「跳跃缓冲」（落地瞬间自动接跳）
	#   没踩到   → 这是「土狼时间」（脚下没地面也能跳）
	if grounded and _press_frame >= 0 and _tick > _press_frame:
		_floor_since_press = true

	_observe_combat()

	_prev_vy = vy
	_prev_y = y_now
	_prev_px = _player.global_position.x


## 战斗观测：靶子每一次掉血、每一次闪避的起止位置、靶子每一次死亡。
## 这些数字事后要拿去核对字幕，不能靠「看起来像打中了」。
func _observe_combat() -> void:
	if _dummy == null or _dummy_health == null:
		return
	var hp := int(_dummy_health.hp)
	var hits := int(_dummy.get("hits_taken"))
	if hp != _last_hp or hits != _last_hits:
		_hp_events.append({
			"tick": _tick, "hp": hp, "hits": hits,
			"dmg": int(_dummy.get("total_damage_taken")),
		})
		_last_hp = hp
		_last_hits = hits

	var dead: bool = bool(_dummy_health.is_dead)
	if dead and not _was_dead:
		_kills.append(_tick)
	_was_dead = dead

	var dodges := int(_player.get("dodges_started"))
	if dodges != _last_dodges:
		_last_dodges = dodges
		# 本节点是玩家的父级，_physics_process 先于玩家执行，所以计数器变化要晚一帧才看到，
		# 而这一帧玩家已经闪出去 10 px 了。用上一帧的 x 当起点才准。
		_dodge_from = _prev_px
		_dodge_running = true
	elif _dodge_running and int(_player.get("state")) != 2:
		_dodge_running = false
		_dodge_log.append({
			"tick": _tick,
			"from": _dodge_from,
			"to": _player.global_position.x,
			"dist": absf(_player.global_position.x - _dodge_from),
		})


# ═══════════════════════════════════════════════════════════════════
# 画面叠层
# ═══════════════════════════════════════════════════════════════════

func _make_overlays() -> void:
	# 轨迹线：加在 TestRoom 之后 → 渲染在场景之上
	_trail = Line2D.new()
	_trail.width = 3.0
	_trail.z_index = 5
	_trail.z_as_relative = false
	var grad := Gradient.new()
	grad.set_color(0, Color(COL_TRAIL, 0.0))
	grad.set_color(1, Color(COL_TRAIL, 0.75))
	_trail.gradient = grad
	add_child(_trail)

	_apex_line = Line2D.new()
	_apex_line.width = 1.0
	_apex_line.z_index = 5
	_apex_line.z_as_relative = false
	_apex_line.default_color = Color(0.55, 0.85, 0.95, 0.65)
	_apex_line.visible = false
	add_child(_apex_line)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "SimSun",
		"Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC",
	])

	var panel := PanelContainer.new()
	panel.position = Vector2(6, 6)
	panel.custom_minimum_size = Vector2(470, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	_title_label = _mk_label(font, 9, COL_DIM)
	_title_label.text = "BAILIAN  ·  M1 combat prototype  ·  自动操作回放（无需人工按键）"
	_cap_label = _mk_label(font, 12, COL_HI)
	_tele_label = _mk_label(font, 9, COL_FG)
	_tele_label.text = "…"

	for l in [_title_label, _cap_label, _tele_label]:
		box.add_child(l)


func _mk_label(font: SystemFont, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _update_tele() -> void:
	if _player == null or _tele_label == null:
		return
	var p := _player
	var dummy_txt := "—"
	if _dummy != null and _dummy_health != null:
		dummy_txt = "%d/%d  hits=%d  dmg=%d%s" % [
			_dummy_health.hp, _dummy_health.max_hp,
			int(_dummy.get("hits_taken")), int(_dummy.get("total_damage_taken")),
			"  DEAD" if _dummy_health.is_dead else "",
		]
	_tele_label.text = (
		"player %-7s hp=%d/%d  dodge_cd=%-3d  invul=%-3s  facing=%s  air=%d\n"
		+ "v=(%7.1f, %7.1f)   pos=(%6.1f, %6.1f)   on_floor=%-3s  coyote=%.3f  buffer=%.3f\n"
		+ "dummy  %s   tick=%d"
	) % [
		p.state_name(), _player_health(), _player_max_health(),
		int(p.get("dodge_cooldown")),
		("yes" if _player_invul() else "no"),
		str(p.get("_facing")),
		_air_frames,
		p.velocity.x, p.velocity.y,
		p.global_position.x, p.global_position.y,
		("yes" if p.is_on_floor() else "no"),
		float(p.get("_coyote_timer")),
		float(p.get("_jump_buffer_timer")),
		dummy_txt,
		_tick,
	]


func _player_health() -> int:
	var h := _player.get_node_or_null("Health")
	return int(h.hp) if h != null else 0


func _player_max_health() -> int:
	var h := _player.get_node_or_null("Health")
	return int(h.max_hp) if h != null else 0


func _player_invul() -> bool:
	var h := _player.get_node_or_null("Health")
	return bool(h.invincible) if h != null else false


func _push_trail() -> void:
	if _player == null or _trail == null:
		return
	_pts.append(_player.global_position + Vector2(0.0, 10.0))
	if _pts.size() > TRAIL_MAX:
		_pts = _pts.slice(_pts.size() - TRAIL_MAX)
	_trail.points = PackedVector2Array(_pts)


func _flash_apex() -> void:
	if _player == null or _apex_line == null:
		return
	var y := _player.global_position.y
	_apex_line.points = PackedVector2Array([
		Vector2(0.0, y), Vector2(640.0, y),
	])
	_apex_line.visible = true


# ═══════════════════════════════════════════════════════════════════
# 收尾：把观测结果打出来，供核对字幕是否有夸大
# ═══════════════════════════════════════════════════════════════════

func _finish() -> void:
	if not _running:
		return
	_running = false
	print("[reel] 总帧数 = ", _tick)
	print("[reel] 每步结束时的角色位置（x, y；y=304 表示站在地面）")
	for m in _marks:
		print("   #%02d  x=%6.1f  y=%6.1f  on_floor=%-3s  f=%-4d  %s" % [
			m["step"], m["x"], m["y"],
			("yes" if m["floor"] else "no"), m["tick"], m["cap"],
		])
	print("[reel] 起跳事件（press = 注入跳键的帧；dt = 注入到真正起跳的间隔）")
	for e in _jumps:
		var kind := "地面起跳"
		if e["press_air"] and e["mid_floor"]:
			kind = "跳跃缓冲（按跳时在空中，起跳前落过地）"
		elif e["press_air"]:
			kind = "土狼时间（按跳时在空中，起跳前从未落地）"
		print("   #%d  press@%d  起跳@%d  x=%6.1f  dt=%d  注入时离地=%-3s  %s" % [
			e["n"], e["press"], e["frame"], e["x"], e["dt"], str(e["press_air"]), kind,
		])
	print("[reel] 每次腾空的高度（起跳点 y → 最高点 y）")
	for f in _flights:
		var cause := "起跳" if f["cause"] == "jump" else "掉落"
		print("   %s  从 y=%6.1f → 最高 y=%6.1f  →  高度 %5.1f px" % [
			cause, f["from_y"], f["min_y"], f["h"],
		])

	print("[reel] 靶子掉血时间线（dmg = 累计伤害）")
	for e in _hp_events:
		print("   f=%-5d hp=%3d  挨打 %d 次  累计 %d 点" % [
			e["tick"], e["hp"], e["hits"], e["dmg"],
		])
	print("[reel] 打了 %d 次 J（注入次数，含被取消的那次）／ 靶子被打死 %d 次" % [
		_atk_press_frames.size(), _kills.size()])
	if _input_drifts > 0:
		print("[reel][WARN] 输入掉了 %d 次（见上面的补针日志）—— 这段回放的时间轴可能已经偏了" % [
			_input_drifts])
	for k in _kills:
		print("   死亡帧 f=%d" % k)
	print("[reel] 每次闪避的位移")
	for d in _dodge_log:
		print("   f=%-5d 从 x=%6.1f → x=%6.1f  位移 %5.1f px" % [
			d["tick"], d["from"], d["to"], d["dist"],
		])

	_write_meta()
	await get_tree().create_timer(0.4).timeout
	get_tree().quit()


## 把关键帧号写出来，供后期的慢放合成用 —— 免得把帧号硬编码进合成脚本。
func _write_meta() -> void:
	var ground_h := 0.0
	for f in _flights:
		if f["cause"] == "jump" and is_equal_approx(f["from_y"], 304.0):
			ground_h = maxf(ground_h, f["h"])

	# 慢放区间：每次「在空中按跳」的前后各 14 帧，把 0.1 秒的宽限窗口摊开来看
	var slow: Array = []
	for e in _jumps:
		if e["press_air"]:
			slow.append([maxi(int(e["press"]) - 14, 0), int(e["frame"]) + 14])

	var meta := {
		"fps": 60,
		"total_frames": _tick,
		"ground_jump_height": ground_h,
		"jumps": _jumps,
		"flights": _flights,
		"marks": _marks,
		"slow_ranges": slow,
		"combat": {
			"hp_events": _hp_events,
			"dodge_log": _dodge_log,
			"kill_frames": _kills,
			"attack_presses": _atk_press_frames.size(),
			"dummy_x": _dummy.global_position.x if _dummy != null else 0.0,
		},
	}
	var path := ProjectSettings.globalize_path("res://build/reel/reel_meta.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("[reel] 写 meta 失败: ", path)
		return
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	print("[reel] meta 已写出: ", path)
