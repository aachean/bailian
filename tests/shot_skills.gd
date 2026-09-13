extends Node
## 技能系统截图：技能栏（5 格）/ 技能面板（V）/ 技能特效。
##     godot --path <项目根> res://tests/shot_skills.tscn

const ROOM := preload("res://scenes/stages/test_room.tscn")


func _ready() -> void:
	var room := ROOM.instantiate()
	add_child(room)
	await _frames(5)
	var player := room.get_node("Player")
	room.get_node("Walker").ai_enabled = false
	room.get_node("Hint").visible = false
	PlayerState.set_equipment({}, [])
	PlayerState.flags.clear()
	PlayerState.level = 9
	player.set("level", 9)
	player.set("max_mp", 130)
	player.set("mp", 130)              # 蓝要够，技能栏才不会全暗
	player.call("_apply_upgrade")
	player.call("_sync_skill_slots")
	player.global_position = Vector2(320.0, 288.0)
	player.velocity = Vector2.ZERO
	var n := 0
	while not player.is_on_floor() and n < 60:
		await get_tree().physics_frame
		n += 1
	await _frames(4)
	player.set("_facing", 1)

	# ── 一、技能栏：放一个技能，让 1 号格挂上冷却遮罩 ──────────
	player.call("_start_cast", 0)
	await _frames(4)
	await _shot("skill_bar.png")
	# 等动作结束，免得面板截图时人还在出招
	await _frames(60)

	# ── 二、技能面板（V） ─────────────────────────────────────
	player.get_node("HUD").call("toggle_skill_panel")
	await _frames(4)
	await _shot("skill_panel.png")
	player.get_node("HUD").call("toggle_skill_panel")
	await _frames(4)

	# ── 三、崩山击的大范围重击 ────────────────────────────────
	player.set("mp", 130)
	var cds: Array = player.get("skill_cooldowns")
	for i in cds.size():
		cds[i] = 0
	player.call("_start_cast", 4)      # 5 号格 = 崩山击
	var waited := 0
	while int(player.state) != 1 and waited < 30:
		await get_tree().physics_frame
		waited += 1
	await _frames(14)                  # 走到判定帧
	await _shot("skill_quake.png")

	get_tree().paused = false
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
