extends Node
## 主菜单版本号验证。

func _ready() -> void:
	var mm: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(mm)
	await _frames(10)
	var ver: Label = mm.get_node_or_null("Version")
	print("版本号节点=%s 文本='%s' 位置=%s" % [
		str(ver != null), ver.text if ver else "-", str(ver.position) if ver else "-"])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/shots/mainmenu_version.png")
	print("saved")
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
