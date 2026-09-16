extends Node
## UI 统一巡检：副本 HUD（含提示条）+ 城镇 + 主菜单。

func _ready() -> void:
	SaveManager.current_slot = 3
	SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")
	var lv: Node = load("res://scenes/stages/lichang.tscn").instantiate()
	add_child(lv)
	await _frames(12)
	var player: Node2D = lv.get_node("Player")
	player.global_position = Vector2(905.0, 288.0)
	player.set("velocity", Vector2.ZERO)
	await _frames(6)
	# 触发提示条
	lv.call("_banner", "这一屏还没清空 —— 打完了才能往前走")
	await _frames(10)
	await _shot("ui_1_hud.png")
	lv.queue_free()
	await _frames(4)

	var mm: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(mm)
	await _frames(8)
	await _shot("ui_2_menu.png")
	mm.queue_free()
	await _frames(4)

	var pm: Node = load("res://scenes/ui/pause_menu.tscn").instantiate()
	add_child(pm)
	await _frames(6)
	if pm.has_method("open"):
		pm.call("open")
	await _frames(6)
	await _shot("ui_3_pause.png")
	print("all done")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://build/shots/" + name)
	print("saved", name)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
