extends Node
## 界面语言渲染截图：中英各截一张，存到 build/shots/（已被 .gitignore 忽略）。
##
##     godot --path <项目根> res://tests/shot_i18n.tscn
##
## 为什么要单独截图：Godot 遇到字体缺字**不报错**，只是画出空白或方框。
## 断言测不出这一层，只能看图。窗口模式运行，会弹窗。
##
## 换字体 / 扩字符集之后（见 tools/build_font.py），跑这个确认没缺字。

const ROOM := preload("res://scenes/stages/test_room.tscn")
const OUT := "res://build/shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	add_child(ROOM.instantiate())
	for _i in 30:
		await get_tree().physics_frame

	await _shot("i18n_zh")

	GameSettings.set_language("en")
	for _i in 6:
		await get_tree().physics_frame
	await _shot("i18n_en")

	GameSettings.set_language("zh_CN")
	print("截图输出目录：", ProjectSettings.globalize_path(OUT))
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [OUT, name])
	print("  %s  err=%d  size=%s" % [name, err, str(img.get_size())])
