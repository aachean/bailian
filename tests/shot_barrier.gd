extends Node
## 剑冢实拍：舆图页签（淬火岭 → 剑冢）+ 残剑林开场 + 冢心 Boss。

func _ready() -> void:
	SaveManager.current_slot = 3
	SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")
	var town: Node = load("res://scenes/stages/town.tscn").instantiate()
	add_child(town)
	await _frames(12)
	var atlas: Node = town.find_child("Atlas", true, false)
	atlas.call("open")
	await _frames(8)
	await _shot("tomb_1_atlas_a.png")
	var rows: Array = atlas.call("row_texts")
	print("淬火岭页：")
	for r in rows:
		print("   %s" % r)

	# 按 → 切到剑冢
	var ev := InputEventKey.new()
	ev.keycode = KEY_RIGHT
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(8)
	await _shot("tomb_2_atlas_b.png")
	print("剑冢页：")
	for r in atlas.call("row_texts"):
		print("   %s" % r)
	atlas.call("close")
	town.queue_free()
	await _frames(4)

	# 残剑林开场
	var lv: Node = load("res://scenes/stages/canjianlin.tscn").instantiate()
	add_child(lv)
	await _frames(14)
	var player: Node2D = lv.get_node("Player")
	player.global_position = Vector2(300.0, 280.0)
	player.set("velocity", Vector2.ZERO)
	await _frames(16)
	await _shot("tomb_3_canjianlin.png")
	lv.queue_free()
	await _frames(4)

	# 冢心最后一屏（Boss）
	lv = load("res://scenes/stages/zhongxin.tscn").instantiate()
	add_child(lv)
	await _frames(14)
	player = lv.get_node("Player")
	player.global_position = Vector2(4180.0, 240.0)
	player.set("velocity", Vector2.ZERO)
	await _frames(22)
	await _shot("tomb_4_boss.png")
	print("done")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var viewport := get_viewport()
	viewport.get_texture().get_image().save_png("res://build/shots/" + name)
	print("saved ", name)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
