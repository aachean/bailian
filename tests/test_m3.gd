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
const LEVEL1 := preload("res://scenes/stages/level_1.tscn")

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
	await _t5_portal_not_armed_inside()
	await _t6_town_walkable()
	await _t7_boss_present()
	await _t8_drop_and_pickup()
	await _t9_anvil_upgrade()
	await _t10_upgrade_survives_snapshot()
	await _t11_shards_survive_scene_change()
	await _t12_hud_shows_player_state()

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
	_check("6", "城镇畅通：从出生点一路向右能走到出口传送门",
		reached,
		"按住 → 走 %d 帧，到 x=%.0f（目标 ≥1150，出生 x=120）" % [
			n, player.global_position.x])
	town.queue_free()
	await _pframes(2)


## 两个新场景结构齐全：城镇有出口、关卡有回城门和四种怪、玩家带相机
func _t1_scenes_wired() -> void:
	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(3)
	var town_ok: bool = town.get_node_or_null("ExitPortal") != null \
		and town.get_node_or_null("Player/Camera") != null \
		and town.get_node_or_null("Player") != null
	var portal_script: String = str(town.get_node("ExitPortal").get("target_scene"))
	town.queue_free()
	await _pframes(2)

	var level := LEVEL1.instantiate()
	add_child(level)
	await _pframes(3)
	var enemies := 0
	var kinds := {}
	for e in level.get_tree().get_nodes_in_group("enemy"):
		if level.is_ancestor_of(e):
			enemies += 1
			# 按数据表分种类，不按脚本 —— 疾行者继承游荡者的脚本，是数据不同
			kinds[str(e.get("data").id)] = true
	var back_portal: String = str(level.get_node("HomePortal").get("target_scene"))
	level.queue_free()
	await _pframes(2)

	_check("1", "城镇与 3 屏关卡都摆得出来：门对门、怪各就位",
		town_ok and portal_script.contains("level_1") and enemies >= 4
			and kinds.size() >= 3 and kinds.has("boss")
			and back_portal.contains("town"),
		"城镇出口→%s　关卡回城→%s　怪 %d 只 / %d 种（含 boss）" % [
			portal_script.get_file(), back_portal.get_file(), enemies, kinds.size()])


## 相机到边就停：玩家在最左，视野中心不越过左界；最右同理
func _t2_camera_bounds() -> void:
	var level := LEVEL1.instantiate()
	add_child(level)
	await _pframes(3)
	var player := level.get_node("Player")
	var cam := player.get_node("Camera") as Camera2D

	player.global_position = Vector2(60.0, 288.0)
	await _pframes(30)
	var left_center: float = cam.get_screen_center_position().x

	player.global_position = Vector2(1860.0, 288.0)
	await _pframes(60)
	var right_center: float = cam.get_screen_center_position().x

	# 半屏 320：左界中心 ≥ 0+320，右界中心 ≤ 1920-320
	_check("2", "相机跟着玩家走，但到关卡两端就停住",
		left_center >= 319.0 and right_center <= 1601.0,
		"最左时视野中心 x=%.0f（≥320）　最右时 x=%.0f（≤1600）" % [left_center, right_center])
	level.queue_free()
	await _pframes(2)


## 掷矛手真的会投矛且矛真的打得动人 —— 数据驱动的新怪不能只「存在」
func _t3_spearman_throws() -> void:
	var level := LEVEL1.instantiate()
	add_child(level)
	await _pframes(3)
	var player := level.get_node("Player")
	var spear := level.get_node("Spearman1")
	var hp0: int = (player.get_node("Health") as Health).hp

	# 站进它的警戒圈：与掷矛手相距 ~190（aggro 220 内），同时躲开疾行者的警戒圈
	player.global_position = Vector2(1430.0, 288.0)
	player.velocity = Vector2.ZERO

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


## 玩家站在门里时传送门不武装 —— 否则新场景出生点挨着门会被立刻弹回去
func _t5_portal_not_armed_inside() -> void:
	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(3)
	var player := town.get_node("Player")
	var portal := town.get_node("ExitPortal")
	player.global_position = portal.global_position + Vector2(0, -8)
	await _pframes(10)
	var armed_inside: bool = bool(portal.get("_armed"))
	player.global_position = Vector2(120.0, 280.0)
	await _pframes(10)
	var armed_after_leave: bool = bool(portal.get("_armed"))
	_check("5", "传送门防穿回：门里不触发，离开过一次才武装",
		not armed_inside and armed_after_leave,
		"门里武装=%s（应为 false）　离开后武装=%s（应为 true）" % [
			str(armed_inside), str(armed_after_leave)])
	town.queue_free()
	await _pframes(2)


## Boss 在关卡尽头，且是真 Boss：血厚、一击沉重（重击）
func _t7_boss_present() -> void:
	var level := LEVEL1.instantiate()
	add_child(level)
	await _pframes(3)
	var boss := level.get_node_or_null("Boss")
	if boss == null:
		_check("7", "Boss 镇守关卡尽头", false, "level_1 里找不到 Boss")
		level.queue_free()
		await _pframes(2)
		return
	var d = boss.get("data")
	var boss_hp: int = d.max_hp
	var smash: SkillData = d.attack_skill
	level.queue_free()
	await _pframes(2)

	_check("7", "Boss 镇守关卡尽头：血厚、重击",
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
	player.set("shards", 0)
	if target != null:
		player.global_position = target.global_position
	await _pframes(20)
	var got: int = int(player.get("shards"))
	walker.queue_free()
	player.queue_free()
	await _pframes(2)

	_check("8", "怪死掉精铁碎片，玩家走过自动拾取计数",
		before >= 1 and spawned >= before and got >= before,
		"配置掉落 %d　场上生成 %d　玩家拾到 %d" % [before, spawned, got])


## 铁砧强化：3 碎片 → 1 级，攻击伤害倍率真的上去
func _t9_anvil_upgrade() -> void:
	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(3)
	var player := town.get_node("Player")
	var anvil := town.get_node("Anvil")

	player.global_position = anvil.global_position + Vector2(0, -8)
	player.set("shards", 3)
	player.set("upgrade_level", 0)
	player.call("_apply_upgrade")
	await _pframes(6)
	var scale0: float = (player.get_node("Hitbox") as Hitbox).damage_scale

	_press("attack")
	await _pframes(4)
	_release("attack")
	await _pframes(4)
	var scale1: float = (player.get_node("Hitbox") as Hitbox).damage_scale
	var lvl: int = int(player.get("upgrade_level"))
	var shards: int = int(player.get("shards"))
	town.queue_free()
	await _pframes(2)

	_check("9", "铁砧强化：3 碎片换 1 级，攻击伤害倍率 +20%",
		is_equal_approx(scale0, 1.0) and is_equal_approx(scale1, 1.2)
			and lvl == 1 and shards == 0,
		"倍率 %.2f → %.2f　等级 %d　碎片剩 %d" % [scale0, scale1, lvl, shards])


## 强化与碎片进快照 —— 「继续游戏」不能把练好的武器吐回去
func _t10_upgrade_survives_snapshot() -> void:
	var room := (load("res://scenes/stages/test_room.tscn") as PackedScene).instantiate()
	add_child(room)
	await _pframes(3)
	var player := room.get_node("Player")
	player.set("shards", 7)
	player.set("upgrade_level", 2)
	var snap := room.call("collect") as Dictionary

	# 现场清零，再从快照恢复
	player.set("shards", 0)
	player.set("upgrade_level", 0)
	room.call("_apply_state", snap)
	await _pframes(2)
	var shards: int = int(player.get("shards"))
	var lvl: int = int(player.get("upgrade_level"))
	var scale: float = (player.get_node("Hitbox") as Hitbox).damage_scale
	room.queue_free()
	await _pframes(2)

	_check("10", "碎片与强化等级进快照，继续游戏原样回来",
		shards == 7 and lvl == 2 and is_equal_approx(scale, 1.4),
		"碎片 %d（期望 7）　等级 %d（期望 2）　倍率 %.2f（期望 1.40）" % [shards, lvl, scale])


## 碎片跨场景保持 —— 用户实测：在关卡里捡的碎片，回城镇全没了。
## 根因：碎片存在玩家节点上，切场景玩家整个重建。现在住在 PlayerState（autoload），
## 玩家 _exit_tree 写回、_ready 读出。这条测试模拟完整的「城镇 → 关卡」重建。
func _t11_shards_survive_scene_change() -> void:
	PlayerState.shards = 0
	PlayerState.upgrade_level = 0

	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(3)
	var town_player := town.get_node("Player")
	town_player.set("shards", 5)
	town_player.set("upgrade_level", 1)
	town.queue_free()               # 触发 _exit_tree 写回 PlayerState
	await _pframes(3)

	var wrote_back: bool = PlayerState.shards == 5 and PlayerState.upgrade_level == 1

	var level := LEVEL1.instantiate()
	add_child(level)
	await _pframes(3)
	var level_player := level.get_node("Player")
	var carried: bool = int(level_player.get("shards")) == 5 \
		and int(level_player.get("upgrade_level")) == 1
	var scale: float = (level_player.get_node("Hitbox") as Hitbox).damage_scale
	level.queue_free()
	await _pframes(2)

	_check("11", "关卡里捡的碎片，回城镇还在（跨场景不丢）",
		wrote_back and carried and is_equal_approx(scale, 1.2),
		"写回 autoload=%s　新场景带过来=%s　强化倍率 %.2f（期望 1.20）" % [
			str(wrote_back), str(carried), scale])
	PlayerState.shards = 0
	PlayerState.upgrade_level = 0


## HUD：左上角色状态、右上背包，数字跟玩家走
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

	player.set("shards", 4)
	hud.call("refresh")
	await _pframes(2)
	var bag: String = (hud.get_node("Bag/Count") as Label).text
	var lv: String = (hud.get_node("Status/Level") as Label).text
	# 开角色面板：武器强化等级现在住在面板里（HUD 等级位显示角色等级）
	hud.call("_unhandled_input", _make_action("panel"))
	await _pframes(2)
	var panel_text: String = (hud.get_node("CharPanel/Text") as Label).text
	hud.call("_unhandled_input", _make_action("panel"))
	await _pframes(2)
	town.queue_free()
	await _pframes(2)

	_check("12", "左上状态栏 / 右上背包 / 角色面板各显其职",
		bag.contains("4") and lv.begins_with("Lv.") and panel_text.contains("精铁"),
		"背包「%s」　状态「%s」　面板含精铁行=%s" % [bag, lv, str(panel_text.contains("精铁"))])
