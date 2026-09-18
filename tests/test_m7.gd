extends Node
## 《百炼》M3 增量 4 自动验收：技能树（7 个技能 / 5 个携带格）
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m7.tscn

const ROOM := preload("res://scenes/stages/test_room.tscn")

const WHIRL := "res://data/skills/whirl.tres"
const THRUST := "res://data/skills/thrust.tres"
const IRONWALL := "res://data/skills/ironwall.tres"
const SWORD_WAVE := "res://data/skills/sword_wave.tres"
const QUAKE := "res://data/skills/quake.tres"
const BREATHE := "res://data/skills/breathe.tres"
const UPCUT := "res://data/skills/upcut.tres"

var _pass := 0
var _fail := 0
var _room: Node2D
var _player: Node
var _walker: Node
var _dummy: Node


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》M3 增量 4 自动验收 · 技能树 ═══")
	_room = ROOM.instantiate()
	add_child(_room)
	for i in 5:
		await get_tree().physics_frame
	_player = _room.get_node("Player")
	_walker = _room.get_node("Walker")
	_dummy = _room.get_node("TargetDummy")
	_walker.ai_enabled = false

	await _t1_pool_is_complete()
	await _t2_locked_by_level()
	await _t3_level_up_unlocks_and_fills()
	await _t4_only_five_carried()
	await _t5_key2_casts_slot2()
	await _t6_cooldowns_are_per_slot()
	await _t7_ironwall_guards()
	await _t8_breathe_heals()
	await _t9_sword_wave_fires_projectile()
	await _t10_skill_panel_toggles()
	await _t11_panel_equip_and_unequip()
	await _t12_panel_assign_by_number()
	await _t13_skills_survive_snapshot()
	await _t14_skill_bar_shows_five()
	await _t15_no_key_leak()
	await _t16_locked_skill_cannot_toggle()

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().paused = false
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


func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)


## 按一下某个技能键（skill_1..skill_5）
func _tap_skill(n: int) -> void:
	_press("skill_%d" % n)
	await _pframes(3)
	_release("skill_%d" % n)
	await _pframes(3)


func _place(x: float) -> void:
	_player.global_position = Vector2(x, 288.0)
	_player.velocity = Vector2.ZERO
	await _pframes(2)
	var n := 0
	while not _player.is_on_floor() and n < 60:
		await get_tree().physics_frame
		n += 1
	await _pframes(2)
	# 把技能冷却清干净，免得上一条用例的冷却污染这一条
	var cds: Array = _player.get("skill_cooldowns")
	for i in cds.size():
		cds[i] = 0
	_player.set("mp", int(_player.get("max_mp")))
	(_player.get_node("Health") as Health).heal_full()
	# 朝向统一朝右：技能判定框按朝向镜像，朝向是左的话全打空
	_player.set("_facing", 1)


## 等玩家回到 FREE 状态（出招 / 硬直中都按不出下一招，那是刻意的）
func _wait_free() -> void:
	var guard := 0
	while int(_player.state) != 0 and guard < 90:
		await get_tree().physics_frame
		guard += 1


func _set_level(n: int) -> void:
	PlayerState.level = n
	_player.set("level", n)
	# 等级直接改的话，蓝上限 / 血上限 / 攻击倍率都得跟着重算 ——
	# 游戏里这条链是 _on_level_up 走的，测试里绕开了它，就得自己补上
	_player.set("max_mp", 50 + (n - 1) * 10)
	_player.set("mp", int(_player.get("max_mp")))
	_player.call("_apply_upgrade")
	_player.call("_sync_skill_slots")
	await _pframes(2)


func _reset() -> void:
	PlayerState.set_equipment({}, [])
	PlayerState.flags.clear()
	PlayerState.level = 1
	PlayerState.exp = 0
	PlayerState.skill_slots = ["", "", "", "", ""]
	_player.set("level", 1)
	_player.set("exp_pts", 0)
	PlayerState.set_equipment(PlayerState.equipped, PlayerState.bag, {})   # 强化钉回基线（逐件之后没有全局等级了）


func _cooldowns() -> Array:
	return _player.get("skill_cooldowns")


func _slots() -> Array:
	return PlayerState.skill_slots


# ─────────────────────────────────────────────────────────────

## 技能池完整：7 个技能，都有名字 key，解锁等级递增
func _t1_pool_is_complete() -> void:
	var pool: Array = _player.call("skill_pool_paths")
	var named := 0
	var levels: Array[int] = []
	var bad := PackedStringArray()
	for p in pool:
		var sk := load(str(p)) as SkillData
		if sk == null:
			bad.append(str(p))
			continue
		if sk.name_key != &"":
			named += 1
		levels.append(sk.unlock_level)
	var ascending := true
	for i in range(1, levels.size()):
		if levels[i] < levels[i - 1]:
			ascending = false
	_check("1", "技能池 7 个技能，都有名字，解锁等级从低到高",
		pool.size() == 7 and named == 7 and bad.is_empty() and ascending,
		"技能数 %d　有名字 %d　解锁等级 %s　坏数据 %s" % [
			pool.size(), named, str(levels),
			"无" if bad.is_empty() else ", ".join(bad)])


## 等级不够的技能拿不到
func _t2_locked_by_level() -> void:
	_reset()
	await _pframes(2)
	var at1: int = _player.call("unlocked_skill_paths").size()
	await _set_level(4)
	var at4: int = _player.call("unlocked_skill_paths").size()
	await _set_level(5)
	var at5: int = _player.call("unlocked_skill_paths").size()
	var upcut_locked: bool = not bool(_player.call("is_skill_unlocked", UPCUT))
	# 等级上限抬到 100 之后，解锁点跟着拉开了 —— 上撩斩排在最靠后的 55 级。
	# 这里断言的是「解锁点在拉开」，不是某一个具体数字：
	# Lv4 还没拿到第二招（它在 5 级），Lv5 拿到了，最后一招要到 Lv55
	await _set_level(55)
	var upcut_at55: bool = bool(_player.call("is_skill_unlocked", UPCUT))
	_check("2", "技能按等级解锁，且解锁点被拉开（不是前几级就发完）",
		at1 == 1 and at4 == 1 and at5 == 2 and upcut_locked and upcut_at55,
		"Lv1 %d 个　Lv4 %d 个　Lv5 %d 个　上撩斩在 Lv4 锁定=%s　Lv55 解锁=%s" % [
			at1, at4, at5, str(upcut_locked), str(upcut_at55)])


## 升级解锁的新技能会自动补进空槽
func _t3_level_up_unlocks_and_fills() -> void:
	_reset()
	await _pframes(2)
	await _set_level(1)
	var filled1 := _count_carried()
	await _set_level(5)
	var filled5 := _count_carried()
	# 30 级正好解锁到第 5 招（崩山击）—— 槽位满了就停在 5 个
	await _set_level(30)
	var filled30 := _count_carried()
	var has_quake: bool = PlayerState.carries(QUAKE)
	_check("3", "升级后新解锁的技能自动补进空槽（槽满了就停在 5 个）",
		filled1 == 1 and filled5 == 2 and filled30 == 5 and has_quake,
		"Lv1 带 %d 个　Lv5 带 %d 个　Lv30 带 %d 个　含崩山击=%s" % [
			filled1, filled5, filled30, str(has_quake)])


## 槽位上限 5：解锁 7 个也不会挤进来
func _t4_only_five_carried() -> void:
	await _set_level(60)          # 7 个技能的解锁点分布在 1~55 级，60 级时全部到手
	var unlocked: int = _player.call("unlocked_skill_paths").size()
	var carried := _count_carried()
	_check("4", "携带格上限就是 5：7 个全解锁了也只带 5 个",
		unlocked == 7 and carried == 5,
		"已解锁 %d 个　携带 %d 个（上限 5）" % [unlocked, carried])


func _count_carried() -> int:
	var n := 0
	for p in _slots():
		if str(p) != "":
			n += 1
	return n


## 数字键 2 放的是 2 号槽的技能，扣的是那个技能的蓝
func _t5_key2_casts_slot2() -> void:
	await _place(320.0)
	PlayerState.set_skill_slot(1, THRUST)
	await _pframes(2)
	var thrust := load(THRUST) as SkillData
	var casts0: int = _player.casts_started
	var mp0: int = int(_player.get("mp"))
	await _tap_skill(2)
	var casted: bool = _player.casts_started > casts0
	var spent: int = mp0 - int(_player.get("mp"))
	_check("5", "数字键 2 放的是 2 号槽的技能，扣它自己的蓝",
		casted and spent >= thrust.mp_cost - 1,
		"施放=%s　蓝 %d → %d（扣 %d，期望 %d±1）" % [
			str(casted), mp0, int(_player.get("mp")), spent, thrust.mp_cost])


## 冷却各算各的：放完 1 号槽，2 号槽立刻还能放
func _t6_cooldowns_are_per_slot() -> void:
	await _place(320.0)
	await _tap_skill(1)
	var cds_after_1: Array = _cooldowns().duplicate()
	await _pframes(30)
	await _place(320.0)                      # 清冷却，重来
	await _tap_skill(1)
	await _pframes(30)                       # 冷却还在走
	var slot1_cd: int = int(_cooldowns()[0])
	var slot2_free: bool = int(_cooldowns()[1]) == 0
	await _wait_free()
	var casts0: int = _player.casts_started
	await _tap_skill(2)
	var second_cast: bool = _player.casts_started > casts0
	_check("6", "五个槽各算各的冷却：1 号槽在冷却中，2 号槽照样能放",
		int(cds_after_1[0]) > 0 and slot1_cd > 0 and slot2_free and second_cast,
		"放完 1 号槽：冷却 %d 帧　此时 2 号槽冷却 %d　2 号槽能放=%s" % [
			slot1_cd, int(_cooldowns()[1]), str(second_cast)])


## 铁壁：出招期间减伤大幅提高，动作结束恢复。
## v2 起装备的防御是**平铺点数**，走 `Health.armor_reduction()` 的护甲曲线；
## 技能给的那一份是**比例**（`guard_reduction`），两者由 Health 取 max 后再统一卡 0.6。
## 所以这里读 `effective_reduction()`（真正生效的那个数），而不是某个原始字段 ——
## 铁壁写的是 0.8，被天花板压到 0.6，这条断言顺带把天花板也钉住了
func _t7_ironwall_guards() -> void:
	await _place(320.0)
	# 技能槽按顺序是 [旋风斩, 突刺斩, 铁壁, 调息, 剑气斩]（由自动补位填的）
	PlayerState.set_skill_slot(2, IRONWALL)
	await _pframes(2)
	var h := _player.get_node("Health") as Health
	var before: float = h.effective_reduction()
	await _tap_skill(3)
	await _pframes(6)                        # 进到铁壁的持续段
	var during: float = h.effective_reduction()
	var raw_guard: float = h.guard_reduction
	await _pframes(50)                       # 等动作彻底结束
	var after: float = h.effective_reduction()
	var wall := load(IRONWALL) as SkillData
	var want := minf(wall.guard_reduction, Health.MAX_DAMAGE_REDUCTION)
	_check("7", "铁壁：出招期间减伤提到技能表里的值（卡 0.6 上限），动作结束回到原来的值",
		is_equal_approx(before, 0.0) and is_equal_approx(raw_guard, wall.guard_reduction) \
			and is_equal_approx(during, want) and is_equal_approx(after, before),
		"开打前 %.2f → 铁壁期间 %.2f（技能表 %.2f，卡上限到 %.2f）→ 结束后 %.2f" % [
			before, during, wall.guard_reduction, want, after])


## 调息：真的把血回上去
func _t8_breathe_heals() -> void:
	await _place(320.0)
	PlayerState.set_skill_slot(3, BREATHE)
	await _pframes(2)
	var h := _player.get_node("Health") as Health
	h.take_damage(60, Vector2.ZERO, false, 0)
	await _pframes(2)
	var hp0: int = h.hp
	await _wait_free()                       # 挨打有 14 帧硬直，硬直里按键无效
	await _tap_skill(4)
	await _pframes(8)
	var hp1: int = h.hp
	var breathe := load(BREATHE) as SkillData
	_check("8", "调息：放一次把血回上去（头顶飘绿字）",
		hp1 > hp0 and hp1 - hp0 == mini(breathe.heal_amount, h.max_hp - hp0),
		"血 %d → %d（回 %d，期望 %d）" % [
			hp0, hp1, hp1 - hp0, breathe.heal_amount])


## 剑气斩：甩出一道会飞的剑气，打得到敌人
func _t9_sword_wave_fires_projectile() -> void:
	await _place(400.0)
	PlayerState.set_skill_slot(3, BREATHE)
	PlayerState.set_skill_slot(4, SWORD_WAVE)
	await _pframes(2)
	# 把游荡者放在右边当靶子（剑气飞得完的距离：速度 460 × 1 秒）
	_walker.global_position = Vector2(560.0, 288.0)
	(_walker.get_node("Health") as Health).heal_full()
	await _pframes(2)
	var wave_hp0: int = int(_walker.get_node("Health").hp)
	await _tap_skill(5)
	await _pframes(6)                        # 剑气在前摇 9 帧后甩出
	var fired := _count_waves()
	await _pframes(50)                       # 让它飞过去
	var wave_hp1: int = int(_walker.get_node("Health").hp)
	var hurt: bool = wave_hp1 < wave_hp0
	_check("9", "剑气斩：甩出一道飞出去的剑气，飞到敌人身上造成伤害",
		fired >= 1 and hurt,
		"场上剑气 %d 道　怪血 %d → %d" % [fired, wave_hp0, wave_hp1])


func _count_waves() -> int:
	var n := 0
	var host := get_tree().current_scene
	if host == null:
		return 0
	for c in host.get_children():
		if c.name.begins_with("SwordWave"):
			n += 1
	return n


## 技能面板：V 开关、真暂停
func _t10_skill_panel_toggles() -> void:
	await _place(320.0)
	var hud := _player.get_node("HUD")
	var panel := hud.get_node("SkillPanel") as Panel
	var was: bool = panel.visible
	_press("skill_panel")
	await _pframes(3)
	_release("skill_panel")
	await _pframes(2)
	var opened: bool = panel.visible and bool(hud.call("is_skill_panel_open")) and get_tree().paused
	var rows := (hud.get_node("SkillPanel/Rows") as VBoxContainer).get_child_count()
	_press("skill_panel")
	await _pframes(3)
	_release("skill_panel")
	await _pframes(2)
	var closed: bool = (not panel.visible) and (not get_tree().paused)
	_check("10", "V 键开关技能面板：打开即暂停，列出技能池 7 行",
		(not was) and opened and closed and rows == 7,
		"初始关=%s　打开+暂停=%s　行数 %d（期望 7）　再按关闭=%s" % [
			str(not was), str(opened), rows, str(closed)])


## 面板里 J 装 / 卸
func _t11_panel_equip_and_unequip() -> void:
	await _set_level(12)
	PlayerState.skill_slots = ["", "", "", "", ""]
	await _pframes(2)
	var hud := _player.get_node("HUD")
	_press("skill_panel")
	await _pframes(3)
	_release("skill_panel")
	await _pframes(3)

	var carried0 := _count_carried()
	_key(KEY_J)                              # 光标在第 1 行 → 装上
	await _pframes(3)
	var carried1 := _count_carried()
	var first_path := str(_player.call("skill_pool_paths")[0])
	var took_first: bool = PlayerState.carries(first_path)
	_key(KEY_J)                              # 再按一次 → 卸下
	await _pframes(3)
	var carried2 := _count_carried()

	_press("skill_panel")
	await _pframes(3)
	_release("skill_panel")
	await _pframes(2)
	_check("11", "技能面板里按 J：装上 / 再按一次卸下",
		carried0 == 0 and carried1 == 1 and took_first and carried2 == 0,
		"携带 %d → %d（J 装上，首个技能）→ %d（再按卸下）" % [
			carried0, carried1, carried2])


## 面板里数字键把技能装到指定格
func _t12_panel_assign_by_number() -> void:
	await _set_level(12)
	PlayerState.skill_slots = ["", "", "", "", ""]
	await _pframes(2)
	var hud := _player.get_node("HUD")
	_press("skill_panel")
	await _pframes(3)
	_release("skill_panel")
	await _pframes(3)

	_key(KEY_DOWN)                           # 光标移到第 2 行
	await _pframes(2)
	_key(KEY_5)                              # 装到 5 号格
	await _pframes(3)
	var slots := _slots()
	var fifth := str(slots[4])
	var second_path := str(_player.call("skill_pool_paths")[1])
	var ok: bool = fifth == second_path and str(slots[0]) == ""

	_press("skill_panel")
	await _pframes(3)
	_release("skill_panel")
	await _pframes(2)
	_check("12", "技能面板里按数字键：把选中的技能装到指定格",
		ok,
		"5 号格 = %s（期望 %s）　1 号格空=%s" % [
			fifth.get_file(), second_path.get_file(), str(str(slots[0]) == "")])


## 携带的技能进存档，读档原样回来
func _t13_skills_survive_snapshot() -> void:
	await _set_level(12)
	PlayerState.skill_slots = ["", "", "", "", ""]
	await _pframes(2)
	PlayerState.set_skill_slot(0, WHIRL)
	PlayerState.set_skill_slot(3, QUAKE)
	var before := _slots().duplicate()
	var snap := _room.call("collect") as Dictionary

	PlayerState.skill_slots = ["", "", "", "", ""]
	await _pframes(1)
	var wiped := _count_carried() == 0
	_room.call("_apply_state", snap)
	await _pframes(3)
	var after := _slots()
	var same := true
	for i in before.size():
		if str(before[i]) != str(after[i]):
			same = false
	_check("13", "携带的 5 格技能进快照，读档原样回来",
		wiped and same,
		"清空成功=%s　读档后 %s" % [str(wiped), str(after)])


## 技能栏：5 个格子，图标跟着携带的技能走，用过的槽出现冷却遮罩
func _t14_skill_bar_shows_five() -> void:
	await _set_level(12)
	await _place(320.0)
	var hud := _player.get_node("HUD")
	var bar := hud.get_node("SkillBar") as HBoxContainer
	var cells := bar.get_child_count()
	var icon1 := bar.get_node_or_null("Cell1/Icon") as SkillIcon
	var icon2 := bar.get_node_or_null("Cell2/Icon") as SkillIcon
	var cd1 := bar.get_node_or_null("Cell1/Cooldown") as ColorRect

	await _tap_skill(1)
	var cd_shown: bool = cd1.visible and cd1.scale.y > 0.3
	await _pframes(120)
	var cd_gone: bool = not cd1.visible

	# 技能栏压在左下角，横着占太宽就盖住地面和怪（用户实测反馈「挡视野」）。
	# 卡死上限：单格 ≤ 40×30、整条 ≤ 240px（屏幕宽 640 的 37.5%）、底边不出屏。
	# 注意不能用 get_viewport_rect()：那是 CanvasItem 的方法，本测试 extends Node
	# 拿不到它（解析期报错 → 脚本整个不加载 → 场景没人 quit，引擎会一直空转）
	var cell_size: Vector2 = (bar.get_child(0) as Control).size
	var bar_w: float = bar.size.x
	var bar_bottom: float = bar.position.y + bar.size.y
	var vp := get_viewport().get_visible_rect().size
	var slim: bool = cell_size.x <= 40.0 and cell_size.y <= 30.0 \
		and bar_w <= 240.0 and bar_bottom <= vp.y

	_check("14", "技能栏 5 格：图标跟着携带的技能，用过的槽有冷却遮罩，且够小不挡视野",
		cells == 5 and icon1 != null and icon1.skill_id != &"" \
			and icon2 != null and icon2.skill_id != &"" and cd_shown and cd_gone and slim,
		"格子 %d 个　1 号格图标 %s　2 号格图标 %s　冷却遮罩出现=%s 消失=%s\n              单格 %.0f×%.0f（≤40×30）　整条宽 %.0f（≤240）　底边 %.0f（屏高 %.0f）" % [
			cells, str(icon1.skill_id), str(icon2.skill_id),
			str(cd_shown), str(cd_gone),
			cell_size.x, cell_size.y, bar_w, bar_bottom, vp.y])


## 技能面板上的文字不能出现翻译 key 本身
func _t15_no_key_leak() -> void:
	await _set_level(12)
	var hud := _player.get_node("HUD")
	_press("skill_panel")
	await _pframes(3)
	_release("skill_panel")
	await _pframes(3)
	var texts: Array = hud.call("panel_texts")
	var leaks := PackedStringArray()
	var re := RegEx.new()
	re.compile("(UI|SKILL|STAT|PANEL|HUD)_[A-Z_0-9]+")
	for t in texts:
		for m in re.search_all(str(t)):
			leaks.append(m.get_string())
	_press("skill_panel")
	await _pframes(3)
	_release("skill_panel")
	await _pframes(2)
	_check("15", "技能面板与技能栏文本里不出现翻译 key 本身",
		leaks.is_empty(),
		"扫了 %d 段文本　泄漏：%s" % [
			texts.size(), "无" if leaks.is_empty() else ", ".join(leaks)])


## 未解锁的技能 J 也装不上（黑盒验收抓到的洞：数字键装槽有解锁检查，J 漏了 ——
## 面板里灰色的「未解锁」其实装得上）。装上的门以 is_skill_unlocked 为准，
## 与等级走：同一个键，解锁之后自然就能装了
func _t16_locked_skill_cannot_toggle() -> void:
	await _set_level(1)
	PlayerState.skill_slots = ["", "", "", "", ""]
	await _pframes(2)
	_press("skill_panel")
	await _pframes(3)
	_release("skill_panel")
	await _pframes(3)
	_key(KEY_DOWN)
	await _pframes(2)
	_key(KEY_DOWN)                # 光标到第 3 行 = 铁壁（12 级解锁，1 级时是灰的）
	await _pframes(2)
	_key(KEY_J)
	await _pframes(3)
	var carried := _count_carried()
	var ironwall_locked: bool = not PlayerState.carries(IRONWALL) \
		and not bool(_player.call("is_skill_unlocked", IRONWALL))
	# 锁定行必须把**怎么解锁**写出来（几级开），不能只写「未解锁」让玩家瞎猜
	var shows_level := false
	for t in (_player.get_node("HUD") as Object).call("panel_texts"):
		if "Lv.12" in str(t):
			shows_level = true
	_press("skill_panel")
	await _pframes(3)
	_release("skill_panel")
	await _pframes(2)
	_check("16", "未解锁的技能 J 装不上，且行文本标明几级解锁",
		carried == 0 and ironwall_locked and shows_level,
		"Lv1 对铁壁按 J：携带 %d 件，铁壁在带=%s，行文本带解锁等级=%s" % [
			carried, str(PlayerState.carries(IRONWALL)), str(shows_level)])
