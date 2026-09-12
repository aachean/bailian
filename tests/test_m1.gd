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

const ROOM := preload("res://scenes/stages/test_room.tscn")
const FPS := 60.0
const SPAWN := Vector2(320.0, 280.0)

var _room: Node2D
var _player             # CharacterBody2D；不标类型，才能访问 player.gd 里的 @export
var _visuals: Node2D

var _pass := 0
var _fail := 0


func _ready() -> void:
	_room = ROOM.instantiate()
	add_child(_room)
	_player = _room.get_node("Player")
	_visuals = _player.get_node("Visuals")

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
	_t11_not_implemented()

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


## 取一个 StaticBody2D 碰撞盒的顶面 y。
func _body_top(body: Node2D) -> float:
	var cs: CollisionShape2D = body.get_node("CollisionShape2D")
	var half: float = (cs.shape as RectangleShape2D).size.y * 0.5
	return body.position.y - half


# ─────────────────────────────────────────────────────────────
# 逐条验收
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


## #11 攻击/闪避：输入映射已就绪，但尚未接入逻辑 —— 按了没反应是预期
func _t11_not_implemented() -> void:
	var mapped := true
	for a in ["attack", "dodge"]:
		if not InputMap.has_action(a):
			mapped = false
	var f := FileAccess.open("res://scripts/characters/player.gd", FileAccess.READ)
	var src: String = f.get_as_text() if f != null else ""
	var wired: bool = src.contains("\"attack\"") or src.contains("\"dodge\"")
	_check("11", "按 J / K：没反应（攻击、闪避尚未实现，预期）",
		mapped and not wired,
		"输入映射已就绪=%s，脚本中已接入=%s" % [mapped, wired])
