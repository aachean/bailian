extends Node

func _ready() -> void:
	var lv: Node = load("res://scenes/stages/lichang.tscn").instantiate()
	add_child(lv)
	for i in 10:
		await get_tree().physics_frame
	var player: Node2D = lv.get_node("Player")
	var mob: Node2D = null
	for m in get_tree().get_nodes_in_group("enemy"):
		if m.get("data") != null and str(m.get("data").get("id")) == "walker":
			mob = m
			break
	if mob == null:
		print("no walker found")
		get_tree().quit()
		return
	player.global_position = Vector2(300.0, 288.0)
	mob.global_position = Vector2(420.0, 288.0)
	mob.set("_target_alpha", 1.0)
	mob.set("_alpha", 1.0)
	mob.set("modulate", Color(1, 1, 1, 1))
	for i in 20:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://build/shots/debug_goblin.png")
	print("shot saved, mob modulate=", mob.modulate, " skin visible=", mob.get_node("Visuals/Skin").visible)
	get_tree().quit()
