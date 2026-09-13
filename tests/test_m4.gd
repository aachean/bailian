extends Node
## 《百炼》M3 增量 1 自动验收：等级 / 经验 / 蓝量 / 技能 / 角色面板
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m4.tscn

const ROOM := preload("res://scenes/stages/test_room.tscn")

var _pass := 0
var _fail := 0
var _room: Node2D
var _player: Node
var _walker: Node
var _dummy: Node


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》M3 增量 1 自动验收 ═══")
	_room = ROOM.instantiate()
	add_child(_room)
	for i in 5:
		await get_tree().physics_frame
	_player = _room.get_node("Player")
	_walker = _room.get_node("Walker")
	_dummy = _room.get_node("TargetDummy")
	_walker.ai_enabled = false          # 隔离：只测成长系统，不让怪搅局

	await _t1_kill_gives_exp()
	await _t2_level_up()
	await _t3_skill_needs_mp()
	await _t4_skill_casts_and_hits()
	await _t5_mp_regen()
	await _t6_panel_toggles()
	await _t7_growth_survives_snapshot()

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-3s %s\n              %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-3s %s\n              %s" % [id, desc, detail])


func _pframes(n: int) -> void:
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
	Input.parse_input_event(ev)


func _place(x: float) -> void:
	_player.global_position = Vector2(x, 288.0)
	_player.velocity = Vector2.ZERO
	await _pframes(2)
	# 等真落地：技能要求站地上，悬空的最后几帧会让 can_cast 悄悄失败
	var n := 0
	while not _player.is_on_floor() and n < 60:
		await get_tree().physics_frame
		n += 1
	await _pframes(2)


## 杀怪给经验
func _t1_kill_gives_exp() -> void:
	await _place(500.0)
	var exp0: int = PlayerState.exp
	var walker_h: Health = _walker.get_node("Health")
	var reward: int = _walker.get("data").exp_reward
	walker_h.take_damage(9999, Vector2.ZERO, true, 1)
	await _pframes(2)
	var gained: int = PlayerState.exp - exp0
	_check("1", "杀怪得经验：击杀游荡者 +8 经验",
		gained == reward,
		"经验 %d → %d（+预期 %d）" % [exp0, PlayerState.exp, reward])


## 升级链路：经验够 → 等级 +1、血上限 +15、血蓝回满
func _t2_level_up() -> void:
	var lv0: int = PlayerState.level
	var ups: int = PlayerState.add_exp(999)      # 直接灌经验，必升多级
	var lv1: int = PlayerState.level
	var max_hp: int = (_player.get_node("Health") as Health).max_hp
	var expect_hp: int = 100 + (lv1 - 1) * 15
	var mp_full: bool = int(_player.get("mp")) == int(_player.get("max_mp"))
	_check("2", "经验够了就升级：血上限成长、血蓝回满",
		ups >= 1 and lv1 > lv0 and max_hp == expect_hp and mp_full,
		"Lv.%d → Lv.%d　血上限 %d（期望 %d）　蓝满=%s" % [
			lv0, lv1, max_hp, expect_hp, str(mp_full)])


## 蓝不够放不出技能
func _t3_skill_needs_mp() -> void:
	await _place(500.0)
	_player.set("mp", 5)
	var casts0: int = _player.casts_started
	_press("skill")
	await _pframes(4)
	_release("skill")
	await _pframes(4)
	var casts: int = _player.casts_started - casts0
	_check("3", "蓝不够时按 L 放不出技能，蓝也不被扣",
		casts == 0 and int(_player.get("mp")) < 30,
		"施放 %d 次（期望 0）　蓝 %d（<30 = 没被扣）" % [casts, int(_player.get("mp"))])


## 蓝够：扣蓝、进技能状态、大范围判定真的命中
func _t4_skill_casts_and_hits() -> void:
	await _place(540.0)
	var h: Health = _player.get_node("Health")
	h.restore(h.max_hp)
	_player.set("mp", int(_player.get("max_mp")))
	_dummy.health.heal_full()
	var dummy_hp0: int = _dummy.health.hp
	var mp0: int = int(_player.get("mp"))
	var casts0: int = _player.casts_started

	_press("skill")
	await _pframes(4)
	print("  [dbg] state=%d casts=%d mp=%d cd=%d can_cast=%s floor=%s skill_loaded=%s" % [
		int(_player.state), _player.casts_started, int(_player.get("mp")),
		int(_player.get("skill_cooldown")), str(_player.can_cast()),
		str(_player.is_on_floor()), str(_player.get("skill") != null)])
	_release("skill")
	await _pframes(30)

	var casted: bool = _player.casts_started > casts0
	var mp_spent: int = mp0 - int(_player.get("mp"))
	var dealt: int = dummy_hp0 - _dummy.health.hp
	# 扣蓝断言容忍 ±1（自然回蓝混进窗口）；伤害容忍 ±15% 浮动的下限
	_check("4", "技能旋风斩：扣 30 蓝、周身大范围命中",
		casted and mp_spent >= 29 and dealt >= 12,
		"施放=%s　扣蓝 %d（期望 30±1）　命中打 %d 点（14±15% → ≥12）" % [
			str(casted), mp_spent, dealt])


## 蓝量自然恢复
func _t5_mp_regen() -> void:
	await _place(320.0)
	_player.set("mp", 10)
	await _pframes(80)               # 80 帧 ≈ 1.3 秒，回 2 点以上
	var mp: int = int(_player.get("mp"))
	_check("5", "蓝量站着也会慢慢回（每半秒 1 点）",
		mp >= 12,
		"10 → %d（80 帧内）" % mp)


## C 键开关角色面板
func _t6_panel_toggles() -> void:
	var hud := _player.get_node_or_null("HUD")
	if hud == null:
		_check("6", "C 键开关角色面板", false, "找不到 HUD")
		return
	var was: bool = hud.get_node("CharPanel").visible
	_press("panel")
	await _pframes(4)
	_release("panel")
	var opened: bool = hud.get_node("CharPanel").visible
	_press("panel")
	await _pframes(4)
	_release("panel")
	var closed: bool = not hud.get_node("CharPanel").visible
	_check("6", "C 键开关角色面板（属性总览）",
		(not was) and opened and closed,
		"初始关=%s　按后开=%s　再按关=%s" % [str(not was), str(opened), str(closed)])


## 等级 / 经验 / 蓝进快照 —— 练出来的等级不能被「继续」吐回去
func _t7_growth_survives_snapshot() -> void:
	_player.set("level", 6)
	_player.set("exp_pts", 33)
	_player.set("mp", 21)
	var snap := _room.call("collect") as Dictionary
	_player.set("level", 1)
	_player.set("exp_pts", 0)
	_player.set("mp", 50)
	_room.call("_apply_state", snap)
	await _pframes(2)
	var lv: int = int(_player.get("level"))
	var xp: int = int(_player.get("exp_pts"))
	var mp: int = int(_player.get("mp"))
	_check("7", "等级 / 经验 / 蓝进快照，读档原样回来",
		lv == 6 and xp == 33 and mp == 21,
		"Lv.%d（期望 6）　经验 %d（期望 33）　蓝 %d（期望 21）" % [lv, xp, mp])
