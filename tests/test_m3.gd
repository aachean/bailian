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


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》M2 增量 3 自动验收 ═══")
	await _t1_scenes_wired()
	await _t2_camera_bounds()
	await _t3_spearman_throws()
	await _t4_dasher_is_distinct()
	await _t5_portal_not_armed_inside()

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

	_check("1", "城镇与 3 屏关卡都摆得出来：门对门、四种怪各就位",
		town_ok and portal_script.contains("level_1") and enemies == 4 and kinds.size() == 3
			and back_portal.contains("town"),
		"城镇出口→%s　关卡回城→%s　怪 %d 只 / %d 种（walker/dasher/spearman）" % [
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
