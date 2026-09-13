extends Node
## 技能特效截图：施放旋风斩、判定帧期间截屏。
##     godot --path <项目根> res://tests/shot_skill.tscn

func _ready() -> void:
	var room := (load("res://scenes/stages/test_room.tscn") as PackedScene).instantiate()
	add_child(room)
	await _frames(5)
	var player := room.get_node("Player")
	room.get_node("Walker").ai_enabled = false
	player.global_position = Vector2(480.0, 288.0)
	player.set("mp", int(player.get("max_mp")))
	await _frames(30)

	var ev := InputEventAction.new()
	ev.action = "skill"
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)
	await _frames(14)          # 越过 8 帧前摇，进判定 + 特效窗口
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("err=%d" % img.save_png("res://build/shots/skill_fx.png"))
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
