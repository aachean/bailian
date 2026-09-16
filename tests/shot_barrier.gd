extends Node

func _ready() -> void:
	var lv: Node = load("res://scenes/stages/lichang.tscn").instantiate()
	add_child(lv)
	for i in 6:
		await get_tree().physics_frame
	var player: Node2D = lv.get_node("Player")
	player.global_position = Vector2(905.0, 288.0)
	player.set("velocity", Vector2.ZERO)
	for i in 20:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://build/shots/check_barrier.png")
	# 打印场景里第 1/2 屏的地面与背景色情况
	for scr in lv.get_node("Screens").get_children() if lv.has_node("Screens") else []:
		print("screen:", scr.name, scr.position)
	print("done")
	get_tree().quit()
