extends Node
## 五处背景巡检：三个副本 + 城镇 + 主菜单，各截一张。

const PLACES := [
	["lichang", "res://scenes/stages/lichang.tscn", Vector2(905, 288)],
	["duancuiqu", "res://scenes/stages/duancuiqu.tscn", Vector2(900, 288)],
	["luhou", "res://scenes/stages/luhou.tscn", Vector2(900, 288)],
	["town", "res://scenes/stages/town.tscn", Vector2(420, 288)],
]


func _ready() -> void:
	SaveManager.current_slot = 3
	SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")
	for place in PLACES:
		var lv: Node = load(place[1]).instantiate()
		add_child(lv)
		await _frames(10)
		var player: Node2D = lv.get_node_or_null("Player")
		if player != null:
			player.global_position = place[2]
			player.set("velocity", Vector2.ZERO)
		await _frames(12)
		await _shot("bg_%s.png" % place[0])
		lv.queue_free()
		await _frames(4)

	var mm: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(mm)
	await _frames(8)
	await _shot("bg_mainmenu.png")
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
