extends Node
## 城镇巡检：房子贴图 + 告示牌（走近 → J 阅读）。

func _ready() -> void:
	SaveManager.current_slot = 3
	SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")
	var lv: Node = load("res://scenes/stages/town.tscn").instantiate()
	add_child(lv)
	await _frames(12)
	var player: Node2D = lv.get_node("Player")

	# 1) 全景：民居 + 铁匠铺 + 老铁匠
	player.global_position = Vector2(300.0, 300.0)
	player.set("velocity", Vector2.ZERO)
	await _frames(14)
	print("--- 顶层子节点 ---")
	for c in lv.get_children():
		print("   %s (%s)" % [c.name, c.get_class()])
	for n in ["House1", "House2", "SignBasic", "SignCombat", "Smith"]:
		var node: Node = lv.get_node_or_null(n)
		if node != null:
			var vis: Node = node.get_node_or_null("Visual") if node.get_node_or_null("Visual") else node.get_node_or_null("Skin")
			print("%-11s pos=%s 视觉=%s" % [n, node.position, vis.get_class() if vis else "-"])
	await _shot("town_1_overview.png")

	# 2) 走近第一块告示牌（应在范围内 → 出现「按 J 交谈」）
	player.global_position = Vector2(300.0, 300.0)
	await _frames(10)
	var sign1: Node = lv.get_node("SignBasic")
	print("告示牌1 提示文字='%s'" % sign1.get_node("Hint").text)
	print("告示牌1 名字='%s'" % sign1.get_node("Name").text)
	var sk: Sprite2D = sign1.get_node_or_null("Skin")
	print("告示牌1 Skin=%s tex=%s pos=%.1f 色块隐藏=%s" % [
		str(sk != null), sk.texture.resource_path.get_file() if sk and sk.texture else "-",
		sk.position.y if sk else 0.0, str(sign1.get_node_or_null("Body") == null)])
	await _shot("town_2_sign_hint.png")

	# 3) 按 J 读牌
	Input.action_press("attack")
	await _frames(3)
	Input.action_release("attack")
	await _frames(8)
	var box: Node = get_tree().get_first_node_in_group("dialogue_box")
	print("对话开着=%s" % (box != null and box.call("is_open")))
	await _shot("town_3_sign_open.png")
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
