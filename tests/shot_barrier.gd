extends Node
## 怪种换装巡检：三个副本各停一处，把该屏幕的怪都照进来。

const PLACES := [
	["lichang", "res://scenes/stages/lichang.tscn", Vector2(400, 260)],
	["duancuiqu", "res://scenes/stages/duancuiqu.tscn", Vector2(700, 260)],
	["luhou", "res://scenes/stages/luhou.tscn", Vector2(700, 260)],
]

func _ready() -> void:
	SaveManager.current_slot = 3
	SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")
	for place in PLACES:
		var lv: Node = load(place[1]).instantiate()
		add_child(lv)
		await _frames(12)
		var player: Node2D = lv.get_node("Player")
		player.global_position = place[2]
		player.set("velocity", Vector2.ZERO)
		await _frames(20)
		await _shot("mob_%s.png" % place[0])
		lv.queue_free()
		await _frames(4)
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
