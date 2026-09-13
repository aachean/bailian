extends Node
## 对话系统截图：城镇里的 NPC 提示 / 对话框（打字机进行中）。
##     godot --path <项目根> res://tests/shot_dialogue.tscn

const TOWN := preload("res://scenes/stages/town.tscn")
const SMITH_INTRO := "res://data/dialogue/smith_intro.tres"


func _ready() -> void:
	var town := TOWN.instantiate()
	add_child(town)
	await _frames(5)
	var player := town.get_node("Player")
	PlayerState.set_equipment({}, [])
	PlayerState.flags.clear()

	# ── 一、站在铁匠跟前，头顶顶着「按 J 交谈」 ──
	player.global_position = Vector2(440.0, 288.0)
	player.velocity = Vector2.ZERO
	var n := 0
	while not player.is_on_floor() and n < 60:
		await get_tree().physics_frame
		n += 1
	await _frames(6)
	await _shot("npc_town.png")

	# ── 二、对话中：等打字机走到一半再截，正好看得见「字还没显完」的样子 ──
	player.global_position = Vector2(456.0, 288.0)
	await _frames(6)
	var box := player.get_node("DialogueBox")
	box.call("open", load(SMITH_INTRO))
	await _frames(7)
	await _shot("dialogue.png")
	get_tree().paused = false
	get_tree().quit()


func _shot(name: String) -> void:
	# 等这一帧真的画完再取图，否则截到的是上一帧
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
