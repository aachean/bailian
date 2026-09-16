extends Node
## 头像切换验证：**按真实流程**（先定角色，再进场景 —— HUD 在 _ready 读当前角色）。

func _ready() -> void:
	SaveManager.current_slot = 3
	for cid in ["swordsman", "archer"]:
		SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")
		PlayerState.character_id = cid
		var lv: Node = load("res://scenes/stages/town.tscn").instantiate()
		add_child(lv)
		await _frames(14)
		print("%s → 加载字符=%s" % [cid, PlayerState.character_id])
		await _shot("portrait_%s.png" % cid)
		lv.queue_free()
		await _frames(6)
	print("done")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://build/shots/" + name)
	print("saved", name)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
