extends Node
## 屏障位置实拍 + 地形/敌人视觉尺寸现场核查。

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
	for m in lv.find_children("*", "CharacterBody2D", true, false):
		if m.global_position.x > 900.0:
			continue
		var sk: Sprite2D = m.get_node_or_null("Visuals/Skin")
		if sk != null:
			print("%-9s skin_pos_y=%.1f scale=%s" % [m.name, sk.position.y, sk.scale])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://build/shots/check_barrier.png")
	print("shot done")
	get_tree().quit()
