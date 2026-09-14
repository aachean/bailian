extends Node
## 舆图、屏号、三屏推进的观感截图（输出 `build/shots/`）。
##     godot --path <项目根> res://tests/shot_atlas.tscn
##
## 为什么必须看图：
##   · 舆图的行是**代码建出来的一堆 Label**（没有 tscn 可查）—— 对齐、行距、
##     会不会压住右上角的精铁、「未开放」的灰看起来对不对，断言一条都抓不到。
##   · HUD 上那行屏号是一行小字，挤不挤只有眼睛能判。
##   · **闸门**是一道竖着的色块：清空前后看起来差多少、挡不挡住视线，
##     也只有看图才知道（`test_m9 #2` 只验它挡不挡人）。
##
## 会动存档槽（要摆出「已通关」的状态）—— 所以和测试一样先备份、跑完还回去。

const TOWN := preload("res://scenes/stages/town.tscn")
const LICHANG := preload("res://scenes/stages/lichang.tscn")
const SaveGuard := preload("res://tests/save_guard.gd")

var _bak: Dictionary = {}


func _ready() -> void:
	_bak = SaveGuard.backup()
	SaveManager.current_slot = 3
	SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")
	await _shot_pedestal()
	await _shot_atlas_fresh()
	await _shot_atlas_progressed()
	await _shot_screens()
	SaveGuard.restore(_bak)
	get_tree().paused = false
	get_tree().quit()


## 一、安全区的舆图台：走近之后提示要看得见、位置要压不住别的设施
func _shot_pedestal() -> void:
	GameProgress.reset_progress()
	var town := TOWN.instantiate()
	add_child(town)
	await _frames(5)
	var p := town.get_node("Player")
	p.global_position = town.get_node("AtlasPedestal").global_position + Vector2(-30.0, 0.0)
	p.velocity = Vector2.ZERO
	await _frames(12)
	await _shot("atlas_stand.png")
	town.queue_free()
	await _frames(3)


## 二、刚开局打开舆图：砺场可进，另外两个副本「未开放」
func _shot_atlas_fresh() -> void:
	GameProgress.reset_progress()
	var town := TOWN.instantiate()
	add_child(town)
	await _frames(5)
	var atlas := town.get_node("Player/Atlas")
	atlas.call("open")
	await _frames(4)
	await _shot("atlas_fresh.png")
	atlas.call("close")
	await _frames(2)
	town.queue_free()
	await _frames(3)


## 三、通关之后：砺场那行变「已通关」，光标停在那儿
func _shot_atlas_progressed() -> void:
	SaveManager.mark_cleared(&"lichang")
	var town := TOWN.instantiate()
	add_child(town)
	await _frames(5)
	var atlas := town.get_node("Player/Atlas")
	atlas.call("open")
	await _frames(4)
	await _shot("atlas_progressed.png")
	atlas.call("close")
	await _frames(2)
	town.queue_free()
	await _frames(3)


## 四、第 1 屏：闸门挡在右边、HUD 写「砺场 · 第 1 屏 / 共 3 屏」
## 五、清空第 1 屏之后走到第 2 屏：闸门没了、屏号变成 2
func _shot_screens() -> void:
	GameProgress.reset_progress()
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _frames(6)
	for e in get_tree().get_nodes_in_group("enemy"):
		if lv.is_ancestor_of(e):
			e.set("ai_enabled", false)
	var p := lv.get_node("Player")
	p.global_position = Vector2(500.0, 288.0)
	p.velocity = Vector2.ZERO
	await _frames(20)
	await _shot("screen_gate_locked.png")

	# 清空**第 1 屏**（只打屏 1 的怪）→ 走到第 2 屏。
	# 不能遍历全部怪：那样副本直接通关了，拍到的就是通关横幅而不是「推进」——
	# 第一版就是这么错的，图和标题对不上
	var s1 := lv.get_node_or_null("Screen1")
	for e in get_tree().get_nodes_in_group("enemy"):
		if s1 != null and is_instance_valid(e) and s1.is_ancestor_of(e):
			(e.get_node("Health") as Health).take_damage(9999, Vector2.ZERO, true, 1)
	await _frames(40)
	p.global_position = Vector2(900.0, 288.0)
	p.velocity = Vector2.ZERO
	await _frames(20)
	await _shot("screen_advanced.png")
	lv.queue_free()
	await _frames(3)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
