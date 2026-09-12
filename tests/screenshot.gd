extends Node
## 截图工具：把几个关键画面存到 build/shots/（该目录已被 .gitignore 忽略）。
##
##     godot --path <项目根> res://tests/screenshot.tscn
##
## 用途：M3 起换真正的美术资源后，不必手动玩就能确认渲染是否正确。
## 注意：它是【窗口模式】运行，会真的弹一个窗口，截完自己退出。

const ROOM := preload("res://scenes/stages/test_room.tscn")
const OUT := "res://build/shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	add_child(ROOM.instantiate())
	await _frames(60)

	await _shot("01_idle")

	_send("move_right", true)
	await _frames(30)
	await _shot("02_run_right")
	_send("move_right", false)
	await _frames(30)

	_send("move_left", true)
	await _frames(30)
	await _shot("03_run_left")
	_send("move_left", false)
	await _frames(30)

	_send("jump", true)
	await _frames(2)
	_send("jump", false)
	await _frames(10)
	await _shot("04_jump")

	print("截图输出目录：", ProjectSettings.globalize_path(OUT))
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _send(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	var err := img.save_png(path)
	print("  %s  err=%d  size=%s" % [name, err, str(img.get_size())])
