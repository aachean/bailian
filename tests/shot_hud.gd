extends Node
## HUD 观感截图：圆形角色头像 + 环形经验条 + 缩小后的技能栏。
##     godot --path <项目根> res://tests/shot_hud.tscn
##
## 为什么这件事必须靠截图：头像和环全是 _draw() 画出来的像素 ——
## 斗笠盖没盖住脸、形状有没有超出内圆画成方角、经验弧从哪个角度起、
## 技能栏缩了以后在关卡里还挡不挡路，断言一条都抓不到（自绘像素没有节点可查）。
## tests/test_m4 的 #16 只锁得住「环的数值语义」和「结构存在」。

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
	# 9 级：五个技能槽正好被 Lv1/2/3/4/5 的技能填满 ——
	# 五格全有图标才看得出缩小后的辨识度
	PlayerState.level = 9
	player.set("level", 9)
	player.call("_apply_upgrade")
	player.call("_sync_skill_slots")
	player.set("mp", int(player.get("max_mp")))
	player.global_position = Vector2(320.0, 288.0)
	player.velocity = Vector2.ZERO
	var n := 0
	while not player.is_on_floor() and n < 60:
		await get_tree().physics_frame
		n += 1
	await _frames(4)
	player.set("_facing", 1)

	var needed: int = PlayerState.exp_needed(9)

	# ── 一、经验环低进度：看得清「没长满」是什么样 ────────────────
	player.set("exp_pts", int(float(needed) * 0.12))
	await _frames(3)
	await _shot("hud_exp_low.png")

	# ── 二、经验环高进度 + 蓝条不满 ─────────────────────────────
	player.set("exp_pts", int(float(needed) * 0.78))
	player.set("mp", int(float(player.get("max_mp")) * 0.55))
	await _frames(3)
	await _shot("hud_exp_high.png")

	# ── 三、战斗中的全景：技能栏在关卡里到底挡不挡路 ──────────────
	player.set("exp_pts", int(float(needed) * 0.45))
	room.get_node("Walker").ai_enabled = true
	room.get_node("Walker").global_position = Vector2(430.0, 288.0)
	await _frames(30)
	await _shot("hud_ingame.png")

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
