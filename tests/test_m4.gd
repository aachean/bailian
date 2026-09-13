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
	await _t8_skill_bar_cooldown()
	await _t9_whirl_fx_visible()
	await _t10_level_up_feedback()
	await _t11_exp_bar_moves_on_kill()
	await _t12_pause_menu_saves()

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


## 暂停菜单保存走的是 current_scene——测试环境下就是本测试根。
## 转发给测试房间；真实游戏里对应挂 stage.gd 的关卡，同一契约。
func collect() -> Dictionary:
	return _room.collect()


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


## 技能栏的冷却遮罩：释放后出现、随冷却缩回、冷却完消失 —— 造梦西游式
func _t8_skill_bar_cooldown() -> void:
	await _place(320.0)
	_player.set("mp", int(_player.get("max_mp")))
	var hud := _player.get_node("HUD")
	var cd := hud.get_node("SkillBar/Cooldown") as ColorRect
	_player.set("skill_cooldown", 0)   # #4 刚放过技能，冷却没走完会按不动
	_press("skill")
	await _pframes(6)
	_release("skill")
	var shown: bool = cd.visible
	var ratio: float = cd.scale.y
	# 等冷却走完（whirl 全程 32 帧 + 90 帧冷却）
	await _pframes(140)
	var gone: bool = not cd.visible
	_check("8", "技能栏冷却遮罩：释放后出现、随冷却缩回、结束消失",
		shown and ratio > 0.5 and gone,
		"释放后遮罩=%s（scale.y=%.2f）　冷却走完消失=%s" % [str(shown), ratio, str(gone)])


## 技能特效：判定窗口里剑光可见，结束后收起
func _t9_whirl_fx_visible() -> void:
	await _place(320.0)
	_player.set("mp", int(_player.get("max_mp")))
	var fx := _player.get_node("Visuals/WhirlFx") as Node2D
	var was: bool = fx.visible
	_press("skill")
	await _pframes(14)               # 前摇 8 帧后进入判定 + 特效窗口
	var during: bool = fx.visible and fx.modulate.a > 0.3
	await _pframes(60)
	var after: bool = fx.visible
	_check("9", "旋风斩有技能效果：判定期间剑光旋转可见，结束收起",
		(not was) and during and (not after),
		"释放前=%s　判定期间=%s（alpha %.2f）　结束后=%s" % [
			str(was), str(during), fx.modulate.a, str(after)])


## 升级有反馈：金光标记 + 「升级！」飘字节点出现
func _t10_level_up_feedback() -> void:
	await _place(320.0)
	var host := get_tree().current_scene
	var labels_before := 0
	for c in host.get_children():
		if c is Label:
			labels_before += 1
	PlayerState.add_exp(999)
	await _pframes(3)
	var labels_after := 0
	for c in host.get_children():
		if c is Label and (c as Label).text == tr("UI_LEVELUP"):
			labels_after += 1
	_check("10", "升级有仪式感：金光 + 「升级！」飘字",
		labels_after >= 1,
		"「升级！」飘字节点 %d 个" % labels_after)


## 经验条当场涨 —— HUD 读的是玩家节点的 exp_pts，杀怪加的是 PlayerState.exp，
## 两者不同步的话条就只会在切场景后跳起来（用户实测）
func _t11_exp_bar_moves_on_kill() -> void:
	_place(500.0)
	var walker_h: Health = _walker.get_node("Health")
	walker_h.heal_full()
	_walker.global_position = Vector2(480.0, 288.0)
	await _pframes(2)
	var hud := _player.get_node("HUD")
	var fill := hud.get_node("ExpBar/Fill") as ColorRect
	var before: float = fill.scale.x
	var ps_before: int = PlayerState.exp

	walker_h.take_damage(9999, Vector2.ZERO, true, 1)
	await _pframes(3)
	var after: float = fill.scale.x

	_check("11", "打怪后经验条当场涨绿（玩家节点与存档层同步）",
		PlayerState.exp > ps_before and after > before,
		"存档层经验 %d → %d　经验条 %.2f → %.2f" % [
			ps_before, PlayerState.exp, before, after])


## 暂停菜单：Esc 打开（真暂停）→ 保存写档 → Esc 关闭恢复
func _t12_pause_menu_saves() -> void:
	_place(320.0)
	var pm := _player.get_node("PauseMenu")
	var root := pm.get_node("Root") as Control
	var save_btn := root.get_node("Panel/Box/Save") as Button
	var h: Health = _player.get_node("Health")

	# 弄一个可辨识的状态再保存
	h.take_damage(20, Vector2.ZERO, false, 1)
	_player.global_position = Vector2(410.0, 288.0)
	_player.velocity = Vector2.ZERO   # 清掉击退速度，不然保存的是滑行中的位置
	await _pframes(20)               # 等击退滑行完全衰减，否则保存的是滑行中的位置

	_press("ui_cancel")
	await _pframes(4)
	_release("ui_cancel")
	await _pframes(2)
	var opened: bool = root.visible and get_tree().paused

	save_btn.pressed.emit()
	await _pframes(2)
	var slot_state := SaveManager.read_state()
	var saved_player := slot_state.get("player", {}) as Dictionary
	var saved_ok: bool = int(saved_player.get("hp", -1)) == h.hp \
		and absf(float(saved_player.get("x", 0)) - 410.0) < 12.0

	_press("ui_cancel")
	await _pframes(4)
	_release("ui_cancel")
	await _pframes(2)
	var closed: bool = (not root.visible) and (not get_tree().paused)

	_check("12", "Esc 暂停菜单：打开即暂停、保存写当前快照、关闭即恢复",
		opened and saved_ok and closed,
		"打开+暂停=%s　保存的快照正确=%s（血 %s @x %s）　关闭+恢复=%s" % [
			str(opened), str(saved_ok),
			str(saved_player.get("hp")), str(saved_player.get("x")), str(closed)])
	get_tree().paused = false          # 测试安全网：绝不能带着暂停退出
