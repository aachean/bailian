extends Node
## 《百炼》M1 自动验收测试
##
## 跑法（无头，不开窗口）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m1.tscn
##
## 做法：把 test_room 加载进来，用代码注入输入事件，逐帧测量物理量，
## 对着 M1 验收清单逐条断言。退出码 0 = 全通过，1 = 有失败项。
##
## 唯一测不了的：手感「爽不爽」。那是人的判断，脚本测不出来。
##
## ── 两条时序约定（踩过坑，别改）─────────────────────────────
## 1) Input.parse_input_event 是排队处理的：本帧调用，玩家要到【下一帧】才读得到。
##    所以按下按键后必须等 2 个物理帧，玩家的 _physics_process 才会处理完这次输入。
## 2) CharacterBody2D.is_on_floor() 是上一次 move_and_slide() 的结果，
##    瞬移位置后要等 1 帧才会反映出来。所有"瞬移到空中"的操作后面都要先等 1 帧。
##
## ── 一条覆盖纪律（2026-09-13 补）─────────────────────────────
## 凡是用「瞬移角色」做的断言，都只证明了碰撞盒和数值存在，证明不了玩家做得到。
## 断言里至少要留一条走「完整操作链」的：真的助跑、真的按跳、真的落上去（见 #12）。
## 配套的可视化回放在 tests/demo_reel.gd，它把同一批机制演一遍并把遥测打在画面上。
##
## ── 战斗部分的两条额外纪律（2026-09-13 补）────────────────────
## 3) 「按了键 → 状态变了」不算验证。必须断言【结果】：靶子掉了多少血、
##    闪避位移是多少、无敌窗口到底挡住了哪一帧的伤害。
## 4) 一次挥砍的判定帧有好几帧，但只许结算一次伤害。这条单独测（见 #15）——
##    多段结算的 bug 在只测「有没有掉血」的断言下完全看不出来。

const ROOM := preload("res://scenes/stages/test_room.tscn")
const FPS := 60.0
const SPAWN := Vector2(320.0, 280.0)

## 本测试房间的参照物。运行时从场景里读真实位置（见 _ready），
## 不在代码里写死 —— 挪靶子 / 挪地面的时候，测试不该跟着改一遍。
## 靶子站在高台右侧的空地上：从出生点到高台的助跑路线必须保持畅通，
## 靶子摆在中间会把助跑拦腰截断（车身碰撞会挡住玩家）。
var DUMMY_X := 0.0
var GROUND_STAND_Y := 0.0

## player.gd 里的 State 枚举
const ST_FREE := 0
const ST_ATTACK := 1
const ST_DODGE := 2

var _room: Node2D
var _player             # CharacterBody2D；不标类型，才能访问 player.gd 里的 @export
var _visuals: Node2D
var _dummy              # 训练靶子
var _dummy_health: Health
var _walker             # 会还手的敌人（M2 增量 1；test_room 里默认 ai_enabled=false）

var _pass := 0
var _fail := 0


func _ready() -> void:
	_room = ROOM.instantiate()
	add_child(_room)
	_player = _room.get_node("Player")
	_visuals = _player.get_node("Visuals")
	_dummy = _room.get_node("TargetDummy")
	_dummy_health = _dummy.get_node("Health")
	_walker = _room.get_node_or_null("Walker")

	# 参照物从场景里读，不写死
	DUMMY_X = _dummy.global_position.x
	GROUND_STAND_Y = _body_top(_room.get_node("Ground")) - 16.0

	await _settle()

	print("")
	print("═══ 《百炼》M1 自动验收 ═══")
	print("Godot %s ｜ 物理 %d Hz ｜ 重力 %s ｜ 项目 %s" % [
		Engine.get_version_info().string,
		Engine.physics_ticks_per_second,
		str(ProjectSettings.get_setting("physics/2d/default_gravity")),
		str(ProjectSettings.get_setting("application/config/name")),
	])
	print("")
	print("── 移动 / 跳跃 ──")
	await _t1_accel()
	await _t2_stop()
	await _t3_both_dirs()
	await _t4_jump_height()
	await _t5_rise_vs_fall()
	await _t6_coyote()
	await _t7_buffer()
	await _t8_facing()
	await _t10_platforms()
	await _t12_run_jump_onto_platform()
	print("")
	print("── 战斗 ──")
	await _t11_combat_wired()
	await _t13_attack_startup()
	await _t14_attack_damage()
	await _t15_single_hit_per_swing()
	await _t16_combo_three_hits()
	await _t17_finisher_locks()
	await _t18_no_move_during_attack()
	await _t19_dodge_distance()
	await _t20_dodge_invincible()
	await _t21_dodge_cooldown()
	await _t22_dodge_cancels_attack()
	await _t23_dummy_revives()
	await _t24_full_chain()

	print("")
	print("── 界面语言 ──")
	await _t25_i18n()

	print("")
	print("── 敌人（M2 增量 1）──")
	await _t28_enemy_chase()
	await _t29_enemy_hurts_player()
	await _t30_player_hurt_stun()
	await _t31_player_death_revive()

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	print("")

	get_tree().quit(0 if _fail == 0 else 1)


# ─────────────────────────────────────────────────────────────
# 断言与工具
# ─────────────────────────────────────────────────────────────

func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-3s %s\n              %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-3s %s\n              %s" % [id, desc, detail])


func _step(n: int = 1) -> void:
	for _i in n:
		await get_tree().physics_frame


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)


func _release(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	ev.strength = 0.0
	Input.parse_input_event(ev)


func _release_all() -> void:
	for a in ["move_left", "move_right", "jump", "attack", "dodge"]:
		_release(a)


## 按下某个动作键：保持 hold 个物理帧后松开。
## 返回时玩家已经处理过这次输入（见文件头时序约定 1）。
func _tap(action: String, hold: int = 2) -> void:
	_press(action)
	await _step(hold)
	_release(action)


## 把玩家放回出生点，等它落到地面并静止。
func _settle() -> void:
	_release_all()
	await _step(2)
	_player.global_position = SPAWN
	_player.velocity = Vector2.ZERO
	var n := 0
	while n < 150:
		await get_tree().physics_frame
		n += 1
		if _player.is_on_floor() and absf(_player.velocity.x) < 0.01:
			break
	await _step(3)


## 把玩家摆到指定 x、朝右、真正站到地面上。
##
## 瞬移之后 is_on_floor() 还保留着上一帧的结果（通常是 true），所以必须先等一帧
## 让物理把真实状态反映出来，再判断有没有落地。这个坑咬过一次：条件写在 await 之前，
## 循环立刻退出，玩家悬在离地 16px 的空中 —— 而「攻击要求站在地上」把后面
## 所有战斗断言全废了，症状却是「按 J 没反应」。
func _place_player(x: float) -> void:
	_release_all()
	await _step(2)
	_player.global_position = Vector2(x, GROUND_STAND_Y - 16.0)
	_player.velocity = Vector2.ZERO
	_player._facing = 1
	_visuals.scale.x = 1.0
	await get_tree().physics_frame
	var n := 0
	while n < 90 and not _player.is_on_floor():
		await get_tree().physics_frame
		n += 1
	await _step(2)


## 把玩家摆到靶子左边 gap 像素处，并把靶子恢复到满血干净状态。
## 战斗断言的前提是「玩家和靶子的相对位置固定」，所以每条战斗测试都从这里起步。
func _face_dummy(gap: float = 40.0) -> void:
	await _place_player(DUMMY_X - gap)
	_dummy.health.heal_full()
	_dummy.hits_taken = 0
	_dummy.total_damage_taken = 0
	_dummy.modulate.a = 1.0
	_dummy.set_collision_layer_value(2, true)
	_dummy.get_node("HealthBar").visible = true
	await _step(2)


## 取一个 StaticBody2D 碰撞盒的顶面 y。
func _body_top(body: Node2D) -> float:
	var cs: CollisionShape2D = body.get_node("CollisionShape2D")
	var half: float = (cs.shape as RectangleShape2D).size.y * 0.5
	return body.position.y - half


# ─────────────────────────────────────────────────────────────
# 移动 / 跳跃
# ─────────────────────────────────────────────────────────────

## #1 按住方向键：很快到匀速，不是慢慢加速
func _t1_accel() -> void:
	await _settle()
	_press("move_right")
	await get_tree().physics_frame          # 等输入生效
	var n := 0
	var reached := false
	while n < 180:
		await get_tree().physics_frame
		n += 1
		if absf(_player.velocity.x) >= _player.max_speed * 0.99:
			reached = true
			break
	_release_all()
	var limit := ceili(_player.accel_time * FPS) + 2
	_check("1", "按住 →：很快到匀速，不是慢慢加速",
		reached and n <= limit,
		"到全速用 %d 帧（上限 %d 帧，accel_time=%.2fs）" % [n, limit, _player.accel_time])
	await _settle()


## #2 松开方向键：很快停住，几乎不滑行
func _t2_stop() -> void:
	await _settle()
	_press("move_right")
	await _step(40)
	var x_at_release: float = _player.global_position.x
	_release("move_right")
	var n := 0
	while n < 180:
		await get_tree().physics_frame
		n += 1
		if absf(_player.velocity.x) < 1.0:
			break
	await _step(6)
	var slide: float = absf(_player.global_position.x - x_at_release)
	var limit := ceili(_player.friction_time * FPS) + 2
	_check("2", "松开 →：很快停住，几乎不滑行",
		n <= limit and slide <= 12.0,
		"停住用 %d 帧（上限 %d 帧），滑行 %.1f px（friction_time=%.2fs）" % [
			n, limit, slide, _player.friction_time])
	await _settle()


## #3 同时按左右：色块不动
func _t3_both_dirs() -> void:
	await _settle()
	_press("move_left")
	_press("move_right")
	await _step(40)
	var vx: float = _player.velocity.x
	_release_all()
	_check("3", "同时按 ← →：色块不动",
		absf(vx) < 0.5,
		"velocity.x = %.3f px/s" % vx)
	await _settle()


## #4 跳跃高度：够得着最高的那块平台
func _t4_jump_height() -> void:
	await _settle()
	var need: float = _body_top(_room.get_node("Ground")) - _body_top(_room.get_node("PlatformB"))
	var y0: float = _player.global_position.y
	await _tap("jump")
	var peak := y0
	var n := 0
	while n < 240:
		await get_tree().physics_frame
		n += 1
		peak = minf(peak, _player.global_position.y)
		if n > 4 and _player.is_on_floor():
			break
	var h: float = y0 - peak
	_check("4", "按 Space：跳得起，够上最高的平台",
		h >= need + 1.0,
		"实跳 %.1f px ／ 需要 ≥ %.1f px（平台B 高出地面 %.0f px）" % [h, need + 1.0, need])
	await _settle()


## #5 上升比下落慢（跳跃手感偏脆，不飘）
func _t5_rise_vs_fall() -> void:
	await _settle()
	await _tap("jump")
	var rise := 0
	while _player.velocity.y < 0.0 and rise < 240:
		await get_tree().physics_frame
		rise += 1
	var fall := 0
	while not _player.is_on_floor() and fall < 240:
		await get_tree().physics_frame
		fall += 1
	_check("5", "上升慢、下落快（跳跃手感偏脆，不飘）",
		rise > fall and rise > 0 and fall > 0,
		"上升 %d 帧 ／ 下落 %d 帧（fall_gravity_scale=%.2f）" % [
			rise, fall, _player.fall_gravity_scale])
	await _settle()


## #6 土狼时间：刚走出平台边缘那一瞬按跳，还能跳起来
func _t6_coyote() -> void:
	var best := -1
	for d in range(0, 13):
		var ok: bool = await _coyote_jumps(d)
		if ok:
			best = d
		elif best >= 0:
			break
	var expect := int(floor(_player.coyote_time * FPS))
	# 实测窗口会比配置值窄 1~3 帧：输入注入一帧延迟 + is_on_floor 一帧滞后，
	# 这两帧都被算进了"宽限"里。所以只断言"窗口存在、量级正确"。
	_check("6", "刚掉出边缘那一瞬按跳：还能跳（土狼时间）",
		best >= 3 and best <= expect + 4,
		"实测宽限 %d 帧 ／ 配置 %d 帧（coyote_time=%.2fs）" % [
			best, expect, _player.coyote_time])


## 把玩家向上挪 40px 模拟「刚走出平台边缘」，延迟 delay 帧后按跳，看能否起跳。
func _coyote_jumps(delay: int) -> bool:
	await _settle()
	_player.global_position.y -= 40.0
	_player.velocity = Vector2.ZERO
	await get_tree().physics_frame          # 等 is_on_floor 反映为 false
	for _i in delay:
		await get_tree().physics_frame
	await _tap("jump")                      # 内部已等 2 帧，玩家处理完毕
	var jumped: bool = _player.velocity.y < -100.0
	await _settle()
	return jumped


## #7 跳跃缓冲：落地前提前按跳，落地瞬间自动接上
func _t7_buffer() -> void:
	var total := await _measure_fall()
	var best := -1
	for d in range(0, 13):
		var ok: bool = await _buffer_jumps(d, total)
		if ok:
			best = d
		elif best >= 0:
			break
	var expect := int(floor(_player.jump_buffer_time * FPS))
	_check("7", "落地前提前按跳：落地自动接上（跳跃缓冲）",
		best >= 3 and best <= expect + 4,
		"实测可提前 %d 帧 ／ 配置 %d 帧（jump_buffer_time=%.2fs，下落共 %d 帧）" % [
			best, expect, _player.jump_buffer_time, total])


## 从 80px 高处自由落体，量出落到地面用几帧。
func _measure_fall() -> int:
	await _settle()
	_player.global_position.y -= 80.0
	_player.velocity = Vector2.ZERO
	await get_tree().physics_frame          # 等 is_on_floor 反映为 false
	var n := 0
	while not _player.is_on_floor() and n < 300:
		await get_tree().physics_frame
		n += 1
	await _settle()
	return n


## 在「距落地还有 advance 帧」时按下跳跃，看落地后是否自动起跳。
func _buffer_jumps(advance: int, total: int) -> bool:
	await _settle()
	_player.global_position.y -= 80.0
	_player.velocity = Vector2.ZERO
	await get_tree().physics_frame          # 等 is_on_floor 反映为 false
	# 提前 2 帧调用 _press，补偿「输入排队一帧 + 玩家处理一帧」
	for _i in maxi(total - advance - 2, 0):
		await get_tree().physics_frame
	await _tap("jump")
	var jumped := false
	var n := 0
	while n < 60:
		await get_tree().physics_frame
		n += 1
		if _player.velocity.y < -100.0:
			jumped = true
			break
	await _settle()
	return jumped


## #8 / #9 朝向：向左移动时翻面，停下后保持不弹回
func _t8_facing() -> void:
	await _settle()
	_press("move_left")
	await _step(30)
	var sx_left: float = _visuals.scale.x
	_release("move_left")
	await _step(45)
	var sx_still: float = _visuals.scale.x
	var vx: float = _player.velocity.x
	_check("8", "按住 ←：白色小方块翻到左边",
		sx_left < 0.0,
		"移动中 Visuals.scale.x = %.1f" % sx_left)
	_check("9", "停下不动：朝向保持，不弹回右边",
		sx_still < 0.0 and absf(vx) < 0.01,
		"停下后 Visuals.scale.x = %.1f，velocity.x = %.3f" % [sx_still, vx])
	await _settle()


## #10 两块平台都站得住
func _t10_platforms() -> void:
	var results: Array[String] = []
	var all_ok := true
	for pname in ["PlatformA", "PlatformB"]:
		var p: Node2D = _room.get_node(pname)
		var top: float = _body_top(p)
		_release_all()
		_player.global_position = Vector2(p.position.x, top - 24.0)
		_player.velocity = Vector2.ZERO
		await _step(40)
		var ok: bool = _player.is_on_floor()
		all_ok = all_ok and ok
		results.append("%s %s (y=%.0f)" % [pname, "站得住" if ok else "站不住", _player.global_position.y])
	_check("10", "两块平台都站得住",
		all_ok,
		" ／ ".join(results))
	await _settle()


## #12 助跑起跳，把高台当台阶踩上去。
##
## 为什么单列这一条：#10 是把角色瞬移到平台正上方自由落体，只能证明「碰撞盒生效」，
## 测不出「助跑起跳的抛物线能不能落在台面上」——而后者才是玩家实际会做的事。
## 这个漏洞是 2026-09-13 录自动操作回放时才暴露的：当时剧本里角色落地后一直
## 按着右键，径直走出台面掉回地面，测试却全绿。
func _t12_run_jump_onto_platform() -> void:
	await _settle()
	var p: Node2D = _room.get_node("PlatformB")
	var stand_y: float = _body_top(p) - 16.0
	_press("move_right")
	var n := 0
	while n < 300 and _player.global_position.x < 390.0:
		await get_tree().physics_frame
		n += 1
	await _tap("jump", 2)
	var landed := false
	n = 0
	while n < 220:
		await get_tree().physics_frame
		n += 1
		if n > 6 and _player.is_on_floor():
			landed = absf(_player.global_position.y - stand_y) < 4.0
			break
	_release_all()
	_check("12", "助跑起跳：能把高台当台阶踩上去（不只是「碰撞盒存在」）",
		landed,
		"落脚 (%.1f, %.1f)，台面站立高度 %.1f" % [
			_player.global_position.x, _player.global_position.y, stand_y])
	await _settle()


# ─────────────────────────────────────────────────────────────
# 战斗
# ─────────────────────────────────────────────────────────────

## #11 按 J / K 都有反应（这一条在战斗实现之前是「没反应」，现在反过来）
func _t11_combat_wired() -> void:
	await _face_dummy()
	var a0: int = _player.attacks_started
	await _tap("attack", 2)
	await _step(24)
	var attacked: bool = _player.attacks_started > a0

	await _settle()
	await _step(45)                          # 等闪避冷却清空
	var d0: int = _player.dodges_started
	await _tap("dodge", 2)
	await _step(4)
	var dodged: bool = _player.dodges_started > d0

	_check("11", "按 J / K：都有反应（M1 战斗已接入）",
		attacked and dodged,
		"J 出招=%s，K 闪避=%s" % [attacked, dodged])
	await _settle()


## #13 出招有前摇：不是按下就生效，得先「抡」几帧
func _t13_attack_startup() -> void:
	await _face_dummy()
	var before: int = _dummy.hits_taken
	_press("attack")
	var hit_at := -1
	var n := 0
	while n < 30:
		await get_tree().physics_frame
		n += 1
		if n == 2:
			_release("attack")
		if hit_at < 0 and _dummy.hits_taken > before:
			hit_at = n
	_release_all()
	var cfg: int = _player.attack_combo[0].startup_frames
	# 理论命中帧 = 输入排队 1 帧 + 前摇 6 帧 + 判定第一帧 ≈ 8。留出调度余量。
	_check("13", "按 J：先出手，过一小会儿才打到（有前摇，不是按下就生效）",
		hit_at >= cfg and hit_at <= cfg + 7,
		"按下后第 %d 帧命中（配置前摇 %d 帧）" % [hit_at, cfg])
	await _settle()


## #14 打到靶子：掉血，且掉的量在设定范围内
func _t14_attack_damage() -> void:
	await _face_dummy()
	var hp0: int = _dummy_health.hp
	await _tap("attack", 2)
	await _step(24)
	var dealt: int = hp0 - _dummy_health.hp
	var sk: SkillData = _player.attack_combo[0]
	var lo := int(floor(float(sk.damage) * (1.0 - sk.damage_variance)))
	var hi := int(ceil(float(sk.damage) * (1.0 + sk.damage_variance)))
	_check("14", "站到靶子面前按 J：靶子掉血，掉的量在设定范围内",
		dealt >= lo and dealt <= hi,
		"这一下打掉 %d 点（配置 %d ±%d%%，区间 %d~%d）" % [
			dealt, sk.damage, int(sk.damage_variance * 100.0), lo, hi])
	await _settle()


## #15 一次挥砍只结算一次伤害
##
## 判定框在 4 帧里都开着，如果不去重，一下会掉 4 次血。
## 只测「有没有掉血」的断言完全看不出这个问题，所以单独列一条。
func _t15_single_hit_per_swing() -> void:
	await _face_dummy()
	await _tap("attack", 2)
	await _step(26)
	var sk: SkillData = _player.attack_combo[0]
	_check("15", "一次挥砍：判定持续好几帧，但只扣一次血",
		_dummy.hits_taken == 1,
		"命中 %d 次（判定持续 %d 帧）" % [_dummy.hits_taken, sk.active_frames])
	await _settle()


## #16 连按三次 J：三段连招全部打出来，且是「一段比一段重」
func _t16_combo_three_hits() -> void:
	await _face_dummy()
	var before: int = _player.attacks_started
	var hp0: int = _dummy_health.hp
	var max_idx := -1

	for i in 3:
		_press("attack")
		await _step(3)
		_release("attack")
		await _step(7)

	var n := 0
	while n < 90:
		await get_tree().physics_frame
		n += 1
		max_idx = maxi(max_idx, _player.attack_index)
	_release_all()

	var segs: int = _player.attacks_started - before
	var dealt: int = hp0 - _dummy_health.hp
	var heavies := 0
	for s in _player.attack_combo:
		if (s as SkillData).heavy:
			heavies += 1
	_check("16", "连按三次 J：打出完整三段，不是三次第一段",
		segs == 3 and max_idx == 2 and _dummy.hits_taken == 3 and dealt > 0,
		"出招 %d 段，最深到第 %d 段，靶子挨 %d 下共 %d 点（其中重击段 %d 个）" % [
			segs, max_idx + 1, _dummy.hits_taken, dealt, heavies])
	await _settle()


## #17 第 3 段是收招硬直：一直按 J 也不能把它取消掉
##
## 做法是和第 1 段做对照 —— 同样是「进入这一段之后猛按 J」：
##   第 1 段 用 10 帧就被下一段接走（可以取消）
##   第 3 段 必须走满全部帧数（不能取消）
## 只断言「第 3 段时间长」没有意义，长度可能是随便配的；对照组才说明它「不接受取消」。
func _t17_finisher_locks() -> void:
	var gap_early := await _chain_gap(0)
	var gap_finish := await _chain_gap(2)
	var first: SkillData = _player.attack_combo[0]
	var third: SkillData = _player.attack_combo[2]
	_check("17", "第 3 段打完有收招硬直：一直按 J 也接不上下一段（前两段则一按就接）",
		third.chainable == false and gap_finish < 0
			and gap_early > 0 and gap_early <= first.active_to() + 5,
		"第 1 段 %d 帧就被接走（可取消）／第 3 段猛按 J %s（配置 chainable=%s，全程 %d 帧）" % [
			gap_early, "也没能接上" if gap_finish < 0 else "接上了", str(third.chainable),
			third.total_frames()])
	await _settle()


## 进入第 index 段后每一帧交替按下/松开 J，测到「出招计数再次增加」用了多少帧。
## 返回 -1 表示这一段结束前都没能接上（= 不可取消）。
##
## 故意站到靶子够不着的地方：打中会触发顿帧，顿帧会把动作时序整体推后，
## 混进来就看不出「能不能取消」这条规则本身了。
func _chain_gap(index: int) -> int:
	await _place_player(180.0)
	_player.attacks_started = 0
	_player.call("_start_attack", index)
	var n := 0
	while n < 200:
		await get_tree().physics_frame
		n += 1
		if n % 2 == 1:
			_press("attack")
		else:
			_release("attack")
		if _player.attacks_started >= 2:
			_release_all()
			return n
		if _player.state != ST_ATTACK:
			_release_all()
			return -1
	_release_all()
	return -1


## #18 出招期间按方向键不会移动：位移只由招式本身的前冲决定
func _t18_no_move_during_attack() -> void:
	await _face_dummy()
	var x0: float = _player.global_position.x
	_press("attack")
	await _step(2)
	_release("attack")
	_press("move_right")
	await _step(12)
	_release_all()
	var moved: float = absf(_player.global_position.x - x0)

	# 对照：同样 12 帧，不攻击、只按住方向键能走多远。
	# 往【左】走 —— 往右会撞上靶子的车身（靶子就站在这个站位右边 40 px），
	# 撞上之后走出来的距离是「被挡住的距离」，不是「走路能走多远」，对照就失效了。
	await _face_dummy()
	var walk0: float = _player.global_position.x
	_press("move_left")
	await _step(12)
	_release_all()
	var walked: float = absf(_player.global_position.x - walk0)

	_check("18", "出招当中按方向键：不跟着走，位移只由招式本身的前冲决定",
		moved < 12.0 and walked > moved * 2.0,
		"出招中 12 帧只挪 %.1f px；同样 12 帧纯走路 %.1f px" % [moved, walked])
	await _settle()


## #19 按 K：朝当前方向闪出去一段，明显快过走路
func _t19_dodge_distance() -> void:
	_release_all()
	await _step(2)
	_player.global_position = Vector2(240.0, GROUND_STAND_Y - 16.0)
	_player.velocity = Vector2.ZERO
	_player._facing = 1
	_visuals.scale.x = 1.0
	await _step(12)

	var x0: float = _player.global_position.x
	await _tap("dodge", 2)
	var n := 0
	while n < 90 and _player.state == ST_DODGE:
		await get_tree().physics_frame
		n += 1
	await _step(4)
	var dodged: float = absf(_player.global_position.x - x0)
	var walk_ref: float = _player.max_speed * float(n) / FPS
	var sk: SkillData = _player.dodge_skill
	_check("19", "按 K：朝前闪出一段，明显快过走路",
		dodged > walk_ref * 1.2,
		"闪了 %.1f px（%d 帧）；同样帧数全程走满速也只有 %.1f px" % [dodged, n, walk_ref])
	await _settle()


## #20 闪避的无敌窗口：窗口内打不中，窗口外打得中
##
## 现在场上没有会打人的敌人（靶子不还手），所以只能直接往角色身上注入伤害来验证。
## 这不理想 —— 但比「不验证」强，而且它测的正是玩家最在意的那件事：
## 「闪的那一下是不是真的免伤」。
func _t20_dodge_invincible() -> void:
	var hp: Health = _player.get_node("Health")
	await _settle()
	await _step(45)                          # 等冷却

	hp.heal_full()
	_player.call("_start_dodge")
	await _step(6)                           # 落在无敌窗口里（配置 2..18 帧）
	var blocked := hp.take_damage(10)

	# 等闪避走完 + 受击无敌过期，再打一次，这次必须打得中
	await _step(50)
	var hp_before := hp.hp
	var through := hp.take_damage(10)
	hp.heal_full()

	var sk: SkillData = _player.dodge_skill
	_check("20", "闪避当中有无敌帧：那几帧打不中，闪完就打得到",
		blocked == 0 and through > 0 and hp_before > 0,
		"窗口内注入 10 点 → 实际受伤 %d；闪完后注入 10 点 → 实际受伤 %d（无敌帧 %d~%d）" % [
			blocked, through, sk.invincible_from, sk.invincible_to])
	await _settle()


## #21 闪避有冷却：刚闪完再按没反应，冷却过了才又能闪
func _t21_dodge_cooldown() -> void:
	await _settle()
	await _step(60)                          # 保证从冷却完毕的状态起步
	_player.call("_start_dodge")
	await _step(6)
	var before: int = _player.dodges_started
	await _tap("dodge", 2)
	await _step(6)
	var denied: bool = _player.dodges_started == before
	var cd_left: int = _player.dodge_cooldown

	await _step(50)                          # 跨过剩余冷却
	await _tap("dodge", 2)
	await _step(4)
	var allowed: bool = _player.dodges_started > before

	_check("21", "闪避有冷却：刚闪完再按没反应，冷却过了才能再闪",
		denied and allowed,
		"冷却中再按 %s（当时还剩 %d 帧），等冷却结束再按 %s" % [
			"没反应" if denied else "居然闪了", cd_left,
			"闪出去了" if allowed else "还是没反应"])
	await _settle()


## #22 闪避能打断自己的攻击
func _t22_dodge_cancels_attack() -> void:
	await _face_dummy()
	await _step(45)                          # 清掉可能残留的闪避冷却
	_player.call("_start_attack", 0)
	await _step(3)
	var attacking: bool = _player.state == ST_ATTACK
	await _tap("dodge", 2)
	await _step(3)
	var now_dodging: bool = _player.state == ST_DODGE
	_check("22", "出招当中按 K：能打断自己的攻击闪出去",
		attacking and now_dodging and _player.dodge_cancels_attack,
		"按 K 前在攻击中=%s，按之后闪避中=%s（允许取消=%s）" % [
			str(attacking), str(now_dodging), str(_player.dodge_cancels_attack)])
	await _settle()


## #23 靶子打死了会满血重生
func _t23_dummy_revives() -> void:
	await _face_dummy()
	var full: int = _dummy_health.max_hp
	_dummy_health.take_damage(full + 50)
	await _step(4)
	var died: bool = _dummy_health.is_dead

	var wait_frames := int(ceil(_dummy.revive_delay * FPS)) + 20
	await _step(wait_frames)
	var back: bool = _dummy_health.hp == full and not _dummy_health.is_dead
	_check("23", "把靶子打死：它会满血重生，可以继续打",
		died and back,
		"打死=%s；等 %.1f 秒后 → 血量 %d/%d，可打=%s" % [
			str(died), _dummy.revive_delay, _dummy_health.hp, full, str(not _dummy_health.is_dead)])
	await _settle()


## #24 完整操作链：走过去 → 连按三次 J → 靶子掉血
##
## 这是战斗部分唯一一条「真的走过去、真的按键、真的打到」的断言。
## 前面几条为了稳定都先把玩家摆到靶子面前，那种摆位证明不了「玩家自己走得到」。
func _t24_full_chain() -> void:
	_release_all()
	await _step(2)
	_dummy.health.heal_full()
	_dummy.hits_taken = 0
	_dummy.modulate.a = 1.0
	_dummy.set_collision_layer_value(2, true)

	_player.global_position = Vector2(200.0, GROUND_STAND_Y - 16.0)
	_player.velocity = Vector2.ZERO
	_player._facing = 1
	_visuals.scale.x = 1.0
	await _step(14)

	var hp0: int = _dummy_health.hp
	var before: int = _player.attacks_started

	# ① 真的走过去
	_press("move_right")
	var n := 0
	while n < 240 and _player.global_position.x < DUMMY_X - 42.0:
		await get_tree().physics_frame
		n += 1
	_release("move_right")
	await _step(8)
	var stood: float = _player.global_position.x

	# ② 连按三次
	for i in 3:
		_press("attack")
		await _step(3)
		_release("attack")
		await _step(7)
	await _step(50)
	_release_all()

	var dealt: int = hp0 - _dummy_health.hp
	var segs: int = _player.attacks_started - before
	var walk_frames := n
	_check("24", "完整操作链：走过去 → 连按三次 J → 靶子掉血",
		segs == 3 and dealt > 0 and _dummy.hits_taken == 3 and stood < DUMMY_X,
		"走了 %d 帧到 x=%.1f，出招 %d 段，靶子挨 %d 下共 %d 点" % [
			walk_frames, stood, segs, _dummy.hits_taken, dealt])
	await _settle()


# ─────────────────────────────────────────────────────────────
# 界面语言
# ─────────────────────────────────────────────────────────────
#
# 三条断言分别防三种翻车：
#   #25 默认跑成英文（或跟随系统语言，中文玩家打开是英文）
#   #26 漏翻 —— CSV 里只填了一边，界面直接把 key 显示出来
#   #27 切了语言但画面不刷新，得重开游戏才生效
#
# 中文缺字形（方框）在这里测不出来：Godot 遇到缺字不报错，只是画空白。
# 那一层靠 tests/shot_i18n 截图看，以及 build_font.py 结尾的字形自检。

## Hint 里用到的全部 key，必须和 scripts/ui/hint.gd 的 LINES 一致
const HINT_KEYS := [
	"UI_HINT_TITLE", "UI_HINT_MOVE", "UI_HINT_JUMP", "UI_HINT_ATTACK", "UI_HINT_DODGE",
]


func _t25_i18n() -> void:
	var hint := _room.get_node_or_null("Hint") as Label
	if hint == null:
		_check("25", "默认中文", false, "找不到 Hint 节点")
		_check("26", "中英译文齐全", false, "找不到 Hint 节点")
		_check("27", "切语言即时刷新", false, "找不到 Hint 节点")
		return

	# #25 默认就是中文，而且标题带 CJK 字形 —— 不是把 key 原样显示出来
	var title_zh := tr("UI_HINT_TITLE")
	_check("25", "界面默认中文（默认值写死中文，不跟随系统语言）",
		GameSettings.DEFAULT_LOCALE == "zh_CN"
			and GameSettings.language == "zh_CN"
			and title_zh != "UI_HINT_TITLE"
			and _has_cjk(title_zh),
		"默认=%s　当前=%s　标题=\"%s\"" % [
			GameSettings.DEFAULT_LOCALE, GameSettings.language, title_zh])

	# #26 每个 key 在两种语言下都有非空译文、且互不相同
	var bad := PackedStringArray()
	for k in HINT_KEYS:
		TranslationServer.set_locale("zh_CN")
		var zh := TranslationServer.translate(k)
		TranslationServer.set_locale("en")
		var en := TranslationServer.translate(k)
		if zh == k or en == k or zh.strip_edges().is_empty() or en.strip_edges().is_empty() or zh == en:
			bad.append(k)
	TranslationServer.set_locale("zh_CN")
	_check("26", "指引每一条都有中英两份，且内容不同（漏翻会直接显示 key）",
		bad.is_empty(),
		"查 %d 条，问题 %d 条%s" % [
			HINT_KEYS.size(), bad.size(), "" if bad.is_empty() else "：" + ", ".join(bad)])

	# #27 切语言 → 画面上的字跟着变，切回来也回得去
	var before := hint.text
	GameSettings.set_language("en")
	await _step(1)
	var switched := hint.text
	GameSettings.set_language("zh_CN")
	await _step(1)
	var restored := hint.text
	_check("27", "切语言后画面上的指引立刻跟着变（不用重开游戏）",
		not before.is_empty() and before != switched and restored == before,
		"中「%s」→ 英「%s」" % [_first_line(before), _first_line(switched)])
	await _settle()


func _has_cjk(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x4E00 and c <= 0x9FFF:
			return true
	return false


func _first_line(s: String) -> String:
	var parts := s.split("\n")
	return parts[0] if parts.size() > 0 else ""


# ─────────────────────────────────────────────────────────────
# 敌人（M2 增量 1）：会还手的小怪
# ─────────────────────────────────────────────────────────────
#
# test_room 里的 Walker 默认 ai_enabled=false（就是一只靶子），
# 前面 27 条测试靠这个隔离「移动手感」和「敌人行为」。
# 这一段把 AI 打开，从头到尾真实地追、真的打、真的被打。

## walker.gd 的 State 枚举
const W_PATROL := 0
const W_CHASE := 1
const W_ATTACK := 2
const W_HURT := 3
const W_DEAD := 4


func _t28_enemy_chase() -> void:
	_release_all()
	await _settle()
	await _step(2)
	if _walker == null:
		_check("28", "敌人追击", false, "test_room 里找不到 Walker")
		_check("29", "敌人攻击掉血", false, "test_room 里找不到 Walker")
		_check("30", "受击硬直", false, "test_room 里找不到 Walker")
		_check("31", "死亡重生", false, "test_room 里找不到 Walker")
		return

	# 玩家站进警戒圈：walker 巡逻中心 x=20，aggro 半径 150。
	# 站 x=85（PlatformA 左缘 92 以内、够不着右侧路线），追击全程无地形阻挡。
	_walker.ai_enabled = true
	_player.global_position = Vector2(85.0, GROUND_STAND_Y - 16.0)
	_player.velocity = Vector2.ZERO
	await _step(6)

	var x0: float = _walker.global_position.x
	var saw_chase := false
	for i in 120:
		await get_tree().physics_frame
		if int(_walker.state) == W_CHASE:
			saw_chase = true
			if i > 12:
				break
	var moved: float = _walker.global_position.x - x0
	_check("28", "敌人会追人：进了警戒圈就逼近，不是站着挨打",
		saw_chase and moved > 15.0,
		"进入追击=%s　逼近 %.1f px（x %.0f → %.0f）" % [
			str(saw_chase), moved, x0, x0 + moved])


## 玩家站在原地，等 walker 追上来打 —— 断言「真的会掉血」，不是状态变了就算
func _t29_enemy_hurts_player() -> void:
	var hp0: int = _player.get_node("Health").hp
	var hit := false
	for i in 600:                   # 最多等 10 秒（追过去 + 攻击节奏都算在内）
		await get_tree().physics_frame
		if _player.get_node("Health").hp < hp0:
			hit = true
			break
	var hp1: int = _player.get_node("Health").hp
	var atk: int = _walker.attacks_started
	_walker.ai_enabled = false      # 掉血证据到手，后面全是时序测试，别让敌人继续捣乱
	_check("29", "敌人真的打得动你：被追上挨一下，血量下降",
		hit and atk > 0 and hp1 < hp0,
		"出招 %d 次　血量 %d → %d" % [atk, hp0, hp1])


## 挨打要停一拍：受击无敌挡补刀 + 硬直里输入无效
func _t30_player_hurt_stun() -> void:
	# #29 断言完成时玩家刚挨打（同一物理帧进入硬直）；万一错过，等下一波
	var guard := 0
	while int(_player.state) != 3 and guard < 30:
		await get_tree().physics_frame
		guard += 1
	var in_hurt := int(_player.state) == 3

	# 【第一时间】注入补刀：受击无敌窗口（0.10 s = 6 帧）内必须被挡。
	# 上一版在这里先按了 4 帧 J 再注入，无敌窗口早过了 —— 测试时序错，不是代码错。
	var blocked: int = -1
	if in_hurt:
		blocked = _player.get_node("Health").take_damage(5, Vector2.ZERO, false, 1)

	# 硬直中按 J：不许出招
	var atk0: int = _player.attacks_started
	if in_hurt:
		_press("attack")
		await _step(4)
		_release("attack")
	var during: int = _player.attacks_started - atk0

	_check("30", "挨打会硬直：硬直里按 J 不出招，受击无敌挡住补刀",
		in_hurt and during == 0 and blocked == 0,
		"硬直中=%s　硬直里出招 %d 次　补刀受伤 %d（0=被无敌挡住）" % [
			str(in_hurt), during, blocked])
	await _settle()


## 血归零 → 死亡锁输入 → 在出生点满血复活
func _t31_player_death_revive() -> void:
	var h: Health = _player.get_node("Health")
	var deaths0: int = _player.deaths

	h.take_damage(9999, Vector2.ZERO, true, 1)
	await _step(2)
	var dead := int(_player.state) == 4              # State.DEAD
	var pos_at_death: Vector2 = _player.global_position

	var revive_frames := int(ceil(_player.revive_delay * 60.0)) + 40
	var revived := false
	for i in revive_frames:
		await get_tree().physics_frame
		if int(_player.state) != 4:
			revived = int(_player.state) == 0        # State.FREE
			break

	var full := h.hp == h.max_hp
	var dx := absf(_player.global_position.x - _player._spawn_point.x)
	_check("31", "死了会在出生点满血重来，不是黑屏卡死",
		dead and revived and full and dx < 24.0,
		"死亡=%s　复活=%s　血量 %d/%d　离出生点 %.1f px（死时 %.0f 处）" % [
			str(dead), str(revived), h.hp, h.max_hp, dx, pos_at_death.x])
	await _settle()

