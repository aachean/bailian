extends Node
## 主菜单截图：默认视图 + 读档面板各一张（字体缺字 / 布局只能看图）。
##     godot --path <项目根> res://tests/shot_menu.tscn

func _ready() -> void:
	var menu := (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	for i in 10:
		await get_tree().process_frame
	await _shot("menu")
	menu.call("_on_load")
	for i in 10:
		await get_tree().process_frame
	await _shot("menu_slots")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/%s.png" % name)])
