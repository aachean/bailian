extends Node
## 舆图与关卡段号的观感截图（输出 `build/shots/`）。
##     godot --path <项目根> res://tests/shot_atlas.tscn
##
## 为什么必须看图：舆图的行是**代码建出来的一堆 Label**（没有 tscn 可查），
## 段号是 HUD 上一行小字 —— 对齐、行距、会不会压住右上角的精铁、
## 「锁」与「未开放」两种灰看起来分不分得清，断言一条都抓不到。
## tests/test_m9 的 #7 只锁得住「这些行存在、且不是翻译 key」。
##
## 会动存档槽（要摆出「已通关」「未解锁」两种状态）——
## 所以和测试一样先备份、跑完原样还回去。

const TOWN := preload("res://scenes/stages/town.tscn")
const LICHANG_1 := preload("res://scenes/stages/lichang_1.tscn")
const SaveGuard := preload("res://tests/save_guard.gd")

var _bak: Dictionary = {}


func _ready() -> void:
	_bak = SaveGuard.backup()
	SaveManager.current_slot = 3
	SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")
	await _shot_pedestal()
	await _shot_atlas_fresh()
	await _shot_atlas_progressed()
	await _shot_stage_hud()
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


## 二、刚开局打开舆图：只有第 1 段可进，后两段锁着，另外两个副本「未开放」
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


## 三、打完之后：三段都开了，砺场标「已通关」，光标停在列表里
func _shot_atlas_progressed() -> void:
	SaveManager.unlock_stage(&"lichang", 2)
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


## 四、关卡里的 HUD：右上那行段号「砺场 · 第 2 段 / 共 3 段」够不够清楚、
## 会不会和上面的精铁计数挤在一起
func _shot_stage_hud() -> void:
	var lv := LICHANG_1.instantiate()
	add_child(lv)
	await _frames(6)
	lv.get_node("Walker1").ai_enabled = false
	lv.get_node("Walker2").ai_enabled = false
	await _frames(8)
	await _shot("stage_hud.png")
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
