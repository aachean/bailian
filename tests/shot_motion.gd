extends Node
## 剑客移动帧的实拍：走路 A/B 交替 + 跳跃帧（输出 build/shots/）。
##     godot --path <项目根> res://tests/shot_motion.tscn
##
## 静图只能抓一瞬 —— 走路抓交替中的 B 帧（与 A 明显不同腿），跳跃抓离地上升段。
## 真正的步频/衔接要进游戏按住方向键看，这里只证明「帧在换、姿势在变」。

const LEVEL := preload("res://scenes/stages/lichang.tscn")


func _ready() -> void:
	var lv := LEVEL.instantiate()
	add_child(lv)
	await _frames(6)
	var player := lv.get_node("Player")
	player.global_position = Vector2(400.0, 288.0)
	await _frames(10)

	# 1) 走路：注入向右，跑到步频稳定后抓 B 帧所在瞬间
	Input.action_press("move_right")
	for i in 40:
		await get_tree().physics_frame
		var skin: Sprite2D = player.get_node("Visuals/Skin")
		if skin.texture.resource_path.contains("walk_b"):
			break
	await _shot("motion_walk_b.png")
	# 紧接着抓 A 帧
	for i in 30:
		await get_tree().physics_frame
		var skin: Sprite2D = player.get_node("Visuals/Skin")
		if skin.texture.resource_path.contains("walk_a"):
			break
	await _shot("motion_walk_a.png")
	Input.action_release("move_right")

	# 2) 跳跃：停稳 → 跳 → 上升段抓 jump 帧
	await _frames(12)
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	for i in 30:
		await get_tree().physics_frame
		var skin: Sprite2D = player.get_node("Visuals/Skin")
		if not player.is_on_floor():
			break
	await _frames(2)
	await _shot("motion_jump.png")

	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
