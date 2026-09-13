extends Node
## 主菜单截图：确认菜单文字渲染正常（字体缺字不报错，只能看图）。
##     godot --path <项目根> res://tests/shot_menu.tscn

func _ready() -> void:
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("err=%d" % img.save_png("res://build/shots/menu.png"))
	get_tree().quit()
