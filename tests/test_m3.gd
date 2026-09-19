extends Node
## 《百炼》M2 增量 3 自动验收：相机跟随 / 城镇与关卡 / 传送门 / 两种新怪
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m3.tscn
##
## 前情：M1 的 33 条（tests/test_m1）+ M2 增量 2 的 6 条（tests/test_m2）必须全绿。
## 场景切换的「真传送」不在这里测：change_scene_to_file 会把本测试场景整个换掉。
## 传送门验证「武装逻辑」（玩家站在门里不触发），真实穿越走人工验收。

const TOWN := preload("res://scenes/stages/town.tscn")
const LICHANG := preload("res://scenes/stages/lichang.tscn")

const IRON_SWORD := "res://data/items/wp_u5251_0_u94c1u5251.tres"  # 普通剑｜平铺攻 1-3，强化上限 3

var _pass := 0
var _fail := 0
## 测试房的地面：被测实体（怪 / 碎片 / 玩家）在无重力环境里下落会让
## 距离类断言抖动（第一遍过第二遍挂就是它）—— 都站在这块地上就稳定了
var _ground: StaticBody2D = null


func _ensure_ground() -> void:
	if _ground != null:
		return
	_ground = StaticBody2D.new()
	_ground.collision_layer = 4
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000, 24)
	shape.shape = rect
	_ground.add_child(shape)
	_ground.position = Vector2(0, 332)
	add_child(_ground)


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》M2 增量 3 自动验收 ═══")
	await _t1_scenes_wired()
	await _t2_camera_bounds()
	await _t3_spearman_throws()
	await _t4_dasher_is_distinct()
	await _t5_pedestal_prompts_when_near()
	await _t6_town_walkable()
	await _t7_boss_present()
	await _t8_drop_and_pickup()
	await _t9_forge_at_anvil()
	await _t10_forge_survives_snapshot()
	await _t11_shards_survive_scene_change()
	await _t12_hud_shows_player_state()
	await _t16_forge_station()

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


## 注入一次**真实按键**。铁匠铺这类「上下选 + 确认」的界面按的是具体键位
## （KEY_J / KEY_UP），用 _press 那种 InputEventAction 注入它们收不到 ——
## 事件类型对不上，界面在自己那一层就静默返回了
func _tap_key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)


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


func _make_action(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


## 城镇完整链路：从出生点一路向右，必须能走到出口传送门。
## 「装饰物把通道堵死」这种 bug 只有真的走一遍才抓得到 ——
## 用户实测：房子碰撞体比视觉大，把唯一的路堵死，整局没法往后玩。
func _t6_town_walkable() -> void:
	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(5)
	var player := town.get_node("Player")
	player.global_position = Vector2(120.0, 280.0)
	player.velocity = Vector2.ZERO
	await _pframes(10)

	_press("move_right")
	var n := 0
	while n < 600 and player.global_position.x < 1150.0:
		await get_tree().physics_frame
		n += 1
	_release("move_right")
	var reached: bool = player.global_position.x >= 1150.0
	_check("6", "城镇畅通：从出生点一路向右能走到最里侧的舆图台",
		reached,
		"按住 → 走 %d 帧，到 x=%.0f（目标 ≥1150，出生 x=120）" % [
			n, player.global_position.x])
	town.queue_free()
	await _pframes(2)


## 城镇与砺场都摆得出来：入口是舆图台；砺场是**一个三屏的副本**
##
## 这条断言跟着粒度改过三次，每次都是产品决策变了：
##   线性三关时代 → 测「门对门」
##   三层结构第一版（一屏一个独立关卡）→ 测「三段各自是独立场景」
##   粒度重定（副本 = 一条多屏的路）→ 测「一个场景里三个屏分组、
##   每屏都有怪、Boss 只在最后一屏」
func _t1_scenes_wired() -> void:
	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(3)
	var pedestal := town.get_node_or_null("AtlasPedestal")
	var town_ok: bool = pedestal != null \
		and town.get_node_or_null("Player/Atlas") != null \
		and town.get_node_or_null("Player/Camera") != null
	var no_portal: bool = town.get_node_or_null("ExitPortal") == null
	town.queue_free()
	await _pframes(2)

	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(3)
	var screens := 0
	var counts: Array[int] = []
	var kinds := {}
	var boss_screen := -1
	for i in 4:
		var s := lv.get_node_or_null("Screen%d" % (i + 1))
		if s == null:
			continue
		screens += 1
		var n := 0
		# 数**场景里摆着的**，不数 `enemy` 组 —— 分批出怪之后，还没轮到出场的那几批
		# 是休眠的、已经退出了那个组，按组数只会数到第 1 批
		for w in s.get_children():
			if not w.is_in_group("wave"):
				continue
			for e in w.get_children():
				n += 1
				# 按数据表分种类，不按脚本 —— 疾行者继承游荡者的脚本，是数据不同
				kinds[str(e.get("data").id)] = true
				if str(e.get("data").id) == "boss":
					boss_screen = screens - 1
		counts.append(n)
	var bound: Rect2 = lv.get("bounds")
	lv.queue_free()
	await _pframes(2)

	_check("1", "城镇有舆图台（没有传送门了）；砺场是三屏副本：每屏有怪、Boss 在最后一屏",
		town_ok and no_portal and screens == 3 \
			and counts[0] >= 9 and counts[1] >= 9 and counts[2] >= 5 \
			and boss_screen == 2 and bound.size.x >= 2880.0,
		"城镇：舆图台=%s 无传送门=%s　砺场 %d 屏，各屏怪数 %s，副本宽 %.0f　Boss 在第 %d 屏" % [
			str(pedestal != null), str(no_portal), screens, str(counts),
			bound.size.x, boss_screen + 1])


## 多屏副本：相机跟着玩家走，但到两端就停（一屏时代这里测的是「视野钉死」）
func _t2_camera_bounds() -> void:
	var level := LICHANG.instantiate()
	add_child(level)
	await _pframes(3)
	var player := level.get_node("Player")
	var cam := player.get_node("Camera") as Camera2D

	player.global_position = Vector2(60.0, 288.0)
	await _pframes(30)
	var left_center: float = cam.get_screen_center_position().x

	player.global_position = Vector2(2820.0, 288.0)
	await _pframes(60)
	var right_center: float = cam.get_screen_center_position().x

	# 半屏 320：左界中心 = 320，右界中心 = 副本宽 2880 - 320 = 2560
	_check("2", "多屏副本的相机跟着玩家走，但到副本两端就停住",
		absf(left_center - 320.0) <= 2.0 and absf(right_center - 2560.0) <= 2.0,
		"最左时视野中心 x=%.0f（应为 320）　最右时 x=%.0f（应为 2560）" % [
			left_center, right_center])
	level.queue_free()
	await _pframes(2)


## 掷矛手真的会投矛且矛真的打得动人 —— 数据驱动的新怪不能只「存在」
func _t3_spearman_throws() -> void:
	var level := LICHANG.instantiate()
	add_child(level)
	await _pframes(3)
	var player := level.get_node("Player")
	# 掷矛手在**最后一屏的第 1 批**里。分批出怪之后，怪是按屏出场的 ——
	# 不把玩家挪进那一屏，它一直是休眠的（这正是"分批"该有的样子）
	player.global_position = Vector2(2500.0, 288.0)
	player.velocity = Vector2.ZERO
	await _pframes(10)
	var spear := level.get_node_or_null("Screen3/Wave1/Spearman3")
	if spear == null:
		_check("3", "掷矛手会投矛，矛飞过去真的打得动人", false, "砺场第 3 屏第 1 批里找不到掷矛手")
		level.queue_free()
		await _pframes(2)
		return
	# 同批还有两只游荡者，AI 关掉并挪走：本用例只关心掷矛手，
	# 它们会跑过来近身打断节奏，让"有没有被矛打中"变得不可测
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not level.is_ancestor_of(e) or e == spear:
			continue
		e.set("ai_enabled", false)
		(e as Node2D).global_position = Vector2(100.0, 288.0)
	var hp0: int = (player.get_node("Health") as Health).hp

	var threw := false
	var hit := false
	for i in 600:
		await get_tree().physics_frame
		if int(spear.throws_started) > 0:
			threw = true
		if (player.get_node("Health") as Health).hp < hp0:
			hit = true
			break

	_check("3", "掷矛手会投矛，矛飞过去真的打得动人",
		threw and hit,
		"投掷=%s　命中=%s（等 %d 帧内）" % [str(threw), str(hit), 600])
	level.queue_free()
	await _pframes(2)


## 疾行者不是「换了名字的 walker」：数据必须真的不一样（更快更脆）
func _t4_dasher_is_distinct() -> void:
	var dasher := (load("res://scenes/enemies/dasher.tscn") as PackedScene).instantiate()
	add_child(dasher)
	await _pframes(2)
	var d = dasher.get("data")
	var dasher_speed: float = d.chase_speed
	var dasher_hp: int = d.max_hp
	dasher.queue_free()
	await _pframes(2)

	var walker := (load("res://scenes/enemies/walker.tscn") as PackedScene).instantiate()
	add_child(walker)
	await _pframes(2)
	var w = walker.get("data")
	var walker_speed: float = w.chase_speed
	var walker_hp: int = w.max_hp
	walker.queue_free()
	await _pframes(2)

	_check("4", "疾行者与游荡者是两种手感：更快、更脆",
		dasher_speed > walker_speed * 1.4 and dasher_hp < walker_hp * 0.7,
		"速度 %0.f vs %0.f（>1.4×）　血 %d vs %d（<0.7×）" % [
			dasher_speed, walker_speed, dasher_hp, walker_hp])


## 舆图台：走近才提示「按 P 打开舆图」，走开提示收起来
##
## 原来是测传送门的防穿回（站在门里不触发）。三层结构之后**城镇没有传送门了**，
## 这条换成同一套语言里还活着的那个设施：舆图台也是「走近 → 出提示」，
## 只是按键从 J 换成 P。防的是「提示一直挂着」或「走近了却没提示」这种静默失败
func _t5_pedestal_prompts_when_near() -> void:
	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(3)
	var player := town.get_node("Player")
	var pedestal := town.get_node("AtlasPedestal") as Area2D
	var hint := pedestal.get_node("Hint") as Label

	player.global_position = Vector2(120.0, 280.0)     # 出生点，离舆图台很远
	await _pframes(10)
	var far_text := hint.text

	player.global_position = pedestal.global_position
	await _pframes(10)
	var near_text := hint.text

	_check("5", "舆图台：走近才提示「按 P 打开舆图」，走开提示收起来",
		far_text.is_empty() and near_text == tr("UI_PEDESTAL_HINT"),
		"远处提示「%s」（应为空）　走近提示「%s」" % [far_text, near_text])
	town.queue_free()
	await _pframes(2)


## Boss 在副本最后一屏，且是真 Boss：血厚、一击沉重（重击）
func _t7_boss_present() -> void:
	var level := LICHANG.instantiate()
	add_child(level)
	await _pframes(3)
	var boss := level.get_node_or_null("Screen3/Wave3/Boss")
	if boss == null:
		_check("7", "Boss 镇守副本最后一屏", false, "砺场第 3 屏最后一批里找不到 Boss")
		level.queue_free()
		await _pframes(2)
		return
	var d = boss.get("data")
	var boss_hp: int = d.max_hp
	var smash: SkillData = d.attack_skill
	level.queue_free()
	await _pframes(2)

	_check("7", "Boss 镇守关底：血厚、重击",
		boss_hp >= 150 and smash != null and smash.heavy and smash.damage >= 12,
		"血 %d（≥150）　技能 \"%s\" 伤害 %d 重击=%s" % [
			boss_hp, smash.display_name if smash != null else "?",
			smash.damage if smash != null else -1, str(smash.heavy) if smash != null else "?"])


## 怪死掉碎片、玩家走过捡起来计数 —— 循环的「掉落」半环
func _t8_drop_and_pickup() -> void:
	_ensure_ground()
	var walker := (load("res://scenes/enemies/walker.tscn") as PackedScene).instantiate()
	add_child(walker)
	walker.global_position = Vector2(300.0, 280.0)
	await _pframes(2)
	var before: int = int(walker.get("data").drop_shards)
	walker.call("_drop_shards")
	await _pframes(1)

	# 数一数场上碎片
	var spawned := 0
	var target: Node2D = null
	for c in get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("pickup.gd"):
			spawned += 1
			target = c

	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await _pframes(1)
	PlayerState.shards = 0
	if target != null:
		player.global_position = target.global_position
	await _pframes(20)
	var got: int = PlayerState.shards
	walker.queue_free()
	player.queue_free()
	await _pframes(2)

	_check("8", "怪死掉精铁碎片，玩家走过自动拾取计数",
		before >= 1 and spawned >= before and got >= before,
		"配置掉落 %d　场上生成 %d　玩家拾到 %d" % [before, spawned, got])


## 铁砧强化：3 碎片 → 1 级，攻击伤害倍率真的上去
## 铁匠铺：站上铁砧按 J 开面板 → 面板里选中一件按 J 强化 → 倍率涨、精铁扣。
##
## 2026-09-14 改：原来是「按一下 J 就把【全局强化等级】+1」。
## 强化改成**逐件 + 按品质封顶**之后（设计原则 5.2 / 5.4），铁砧只负责把界面叫出来 ——
## 「练哪一件」是玩家的决定。所以断言改成盯：面板开没开、光标选中的是不是那一件、
## 强化的是不是**那一件**、别的有没有被牵连
func _t9_forge_at_anvil() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.shards = 10
	var uid: String = PlayerState.add_item(IRON_SWORD)
	PlayerState.equip(uid)
	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(3)
	var player := town.get_node("Player")
	var anvil := town.get_node("Anvil")
	var panel := player.get_node("ForgePanel")
	player.global_position = anvil.global_position + Vector2(0, -8)
	await _pframes(6)
	var scale0: float = (player.get_node("Hitbox") as Hitbox).damage_scale

	var flat0: int = (player.get_node("Hitbox") as Hitbox).attack_flat

	var cost: int = PlayerState.forge_cost(uid)      # 成本从数据取，不写死
	_press("attack")                 # 站上铁砧按 J → 开铁匠铺
	await _pframes(4)
	_release("attack")
	await _pframes(2)
	# 暂停状态要在**打开那一刻**存下来：下面 detail 里的求值发生在 Esc 之后，
	# 那时已经恢复运行，直接写 get_tree().paused 会打出一句与事实相反的话
	var paused_when_open: bool = get_tree().paused
	var opened: bool = bool(panel.call("is_open")) and paused_when_open
	var picked: String = str(panel.call("selected_uid"))

	_tap_key(KEY_J)                  # 面板里按 J → 强化光标那一件
	await _pframes(4)
	var lv := PlayerState.forge_level(uid)
	var shards: int = PlayerState.shards
	var scale1: float = (player.get_node("Hitbox") as Hitbox).damage_scale
	var flat1: int = (player.get_node("Hitbox") as Hitbox).attack_flat

	_tap_key(KEY_ESCAPE)             # Esc 关掉
	await _pframes(4)
	var closed: bool = not bool(panel.call("is_open")) and not get_tree().paused

	# ADR-0029：damage_scale = 1 + 等级% + **武器**强化%（武器是唯一攻击杠杆）。
	# 这里强化的就是装备着的武器，所以 weapon_atk_pct() == 这把武器的 forge_mult
	var expect: float = 1.0 + PlayerState.progression.atk_bonus_at(PlayerState.level) \
		+ PlayerState.weapon_atk_pct()
	var rolled := int(PlayerState.stat_of(uid).get("atk", 0))
	town.queue_free()
	await _pframes(2)

	_check("9", "铁匠铺：站上铁砧按 J 开面板 → 选中那件按 J 强化（倍率涨、按成本扣精铁）",
		opened and picked == uid and lv == 1 and shards == 10 - cost \
			and is_equal_approx(scale1, expect) and closed \
			and flat1 == rolled and flat1 == flat0,
		"开面板=%s（当时暂停=%s）　光标选中=穿着的武器=%s　强化 +%d　精铁 10→%d（成本 %d）　"
		% [str(opened), str(paused_when_open), str(picked == uid), lv, shards, cost]
		+ "倍率 %.3f → %.3f（期望 %.3f）　平铺攻击 %d（不受强化影响）　Esc 关掉=%s" % [
			scale0, scale1, expect, flat1, str(closed)])


## 强化与碎片进快照 —— 「继续游戏」不能把练好的武器吐回去
## 强化等级与装备实例进快照 —— 「继续游戏」不能把练好的武器吐回去，
## 也不能把装备认成「另一件同型号的」（那样强化等级就丢了）
func _t10_forge_survives_snapshot() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.shards = 7
	var uid: String = PlayerState.add_item(IRON_SWORD)
	PlayerState.equip(uid)
	var cost: int = PlayerState.forge_cost(uid)  # 成本从数据取，不写死
	PlayerState.forge_once(uid)                  # 花掉一次的钱，+1 级

	var room := (load("res://scenes/stages/test_room.tscn") as PackedScene).instantiate()
	add_child(room)
	await _pframes(3)
	var snap := room.call("collect") as Dictionary

	# 现场清零，再从快照恢复
	PlayerState.shards = 0
	PlayerState.forge.clear()
	PlayerState.set_equipment({}, [])
	room.call("_apply_state", snap)
	await _pframes(2)
	var shards: int = PlayerState.shards
	var lv := PlayerState.forge_level(uid)
	var same_uid: bool = PlayerState.equipped_uid(&"weapon") == uid
	room.queue_free()
	await _pframes(2)

	_check("10", "强化等级与装备实例进快照，继续游戏原样回来",
		shards == 7 - cost and lv == 1 and same_uid,
		"精铁 %d（期望 %d = 7 - %d）　武器强化 +%d（期望 1）　实例 id 一致=%s" % [
			shards, 7 - cost, cost, lv, str(same_uid)])


## 精铁跨场景保持 —— 用户实测：在关卡里捡的碎片，回城镇全没了。
##
## 根因（当时）：碎片存在玩家节点上，切场景玩家整个重建，东西就丢了。
## 2026-09-14 起**玩家节点上那份删掉了**，精铁只住在 PlayerState ——
## 所以这条测试换了个问法：不是「有没有写回」，而是「根本不依赖节点」。
## 关卡里捡到 5 块，切到另一个场景，数字照样是 5
func _t11_shards_survive_scene_change() -> void:
	PlayerState.reset_for_new_game()

	var level := LICHANG.instantiate()
	add_child(level)
	await _pframes(3)
	var level_player := level.get_node("Player")
	for _i in 5:
		level_player.call("collect_shard")
	var in_level: int = PlayerState.shards
	level.queue_free()
	await _pframes(3)

	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(3)
	var after_switch: int = PlayerState.shards
	town.queue_free()
	await _pframes(2)

	_check("11", "关卡里捡的精铁，切场景之后还在（不依赖玩家节点）",
		in_level == 5 and after_switch == 5,
		"关卡里捡到 %d 块　切到城镇之后 %d 块" % [in_level, after_switch])
	PlayerState.shards = 0


func _t12_hud_shows_player_state() -> void:
	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(3)
	var player := town.get_node("Player")
	var hud := player.get_node_or_null("HUD")
	if hud == null:
		_check("12", "HUD 显示玩家状态", false, "玩家下找不到 HUD")
		town.queue_free()
		await _pframes(2)
		return

	PlayerState.gold = 7
	PlayerState.shards = 4
	hud.call("refresh")
	await _pframes(2)
	var bag: String = (hud.get_node("Bag/Count") as Label).text
	var lv: String = (hud.get_node("Status/Level") as Label).text
	# 主界面只显示元宝（2026-09-18 神圈注）；精铁搬进**背包面板的材料行** ——
	# 所以这里要开一次背包，材料行的「精铁4」才算数
	hud.call("_unhandled_input", _make_action("bag"))
	await _pframes(2)
	var mat_row: String = (hud.get_node("BagPanel/MatRow") as Label).text
	hud.call("_unhandled_input", _make_action("bag"))
	await _pframes(2)
	# 属性块并入 B 面板（C 键废除）：StatsLabel 顶部该有「等级」属性行
	hud.call("_unhandled_input", _make_action("bag"))
	await _pframes(2)
	var panel_all: String = (hud.get_node("BagPanel/StatsL") as Label).text
	hud.call("_unhandled_input", _make_action("bag"))
	await _pframes(2)
	town.queue_free()
	await _pframes(2)

	_check("12", "左上状态栏 / 右上元宝 / 材料行与角色属性块各显其职",
		bag.contains("7") and not bag.contains("精铁") and lv.begins_with("Lv.") \
			and mat_row.contains("精铁4") and panel_all.contains("等级"),
		"右上「%s」　材料行含精铁4=%s　状态「%s」　属性块含等级行=%s" % [
			bag, str(mat_row.contains("精铁4")), lv, str(panel_all.contains("等级"))])


## 锻造台（2026-09-18 神要求补上）：打造藏在铁砧面板的 Tab 页里玩家没找到 ——
## 现在城镇里单独一座台子，走近按 J **直接落打造页**。
## 断言三件事：台子存在且是打造台；open_craft 落在打造页；打造页的牌子写的是「打造」
func _t16_forge_station() -> void:
	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(3)
	var forge := town.get_node_or_null("Forge")
	var exists := forge != null and bool(forge.get("opens_craft"))
	var player := town.get_node("Player")
	var panel := player.get_node("ForgePanel")
	panel.call("open_craft")
	await _pframes(2)
	var opened := bool(panel.call("is_open"))
	var page := int(panel.get("_page"))
	var title: String = (panel.get_node("Root/Panel/Title") as Label).text
	panel.call("close")
	await _pframes(2)
	town.queue_free()
	await _pframes(2)
	_check("16", "锻造台：城镇里有座打造台，走近按 J 直接落在打造页",
		exists and opened and page == 1 and title == tr("UI_CRAFT_TITLE"),
		"台子存在且 opens_craft=%s　面板开=%s　页=%d（1=打造）　标题「%s」" % [
			str(exists), str(opened), page, title])
