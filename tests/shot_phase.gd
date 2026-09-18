extends Node
## 相位护罩的截图（视觉只能靠眼睛验 —— 断言测不了「它长什么样」）。
##
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/shot_phase.tscn
##
## 出四张图到 `res://build/shots/`：架势（护罩渐亮）/ 相位（满亮 + 呼吸）/
## 砍在护罩上（冷色火花）/ 恢复（碎闪 + 可反击）。
##
## ── 为什么这件事必须靠截图 ────────────────────────────────────
## 护罩是 `EnemyShield` 用 `_draw()` 手画的（没有节点可查）：圈画歪、太小吃看不见、
## 冷蓝白跟场景背景糊在一起、碎闪没出来 —— 全是「测试全绿但玩起来不对」。
## 顺带验「打不动的反馈」：**这一张是玩家唯一能看出「不是没打中，是被挡住了」的东西**。
##
## 用**真玩家真挥砍**（不是直接调 take_damage）—— 反馈走的是
## `Hitbox.hit_blocked → player._on_hit_blocked` 那条真路径，
## 直接调 take_damage 只会发信号，火花根本不会出现（那就成了假截图）。

const ROOM := preload("res://scenes/stages/test_room.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/boss.tscn")
const BOSS_DATA := preload("res://data/enemies/boss.tres")

var _room: Node = null
var _boss: Node2D = null
var _player: Node = null


func _ready() -> void:
	await get_tree().process_frame
	_room = ROOM.instantiate()
	add_child(_room)
	await _pframes(3)
	_room.get_node("Walker").set("ai_enabled", false)
	var hint := _room.get_node_or_null("Hint")
	if hint != null:
		hint.visible = false
	_player = _room.get_node("Player")

	var d: EnemyData = BOSS_DATA.duplicate()
	d.phase_warn_frames = 40      # 拉长，好在每一段里停下来截图
	d.phase_frames = 60
	d.phase_interval_frames = 30
	d.phase_recover_frames = 40
	d.phase_move = EnemyData.PhaseMove.STILL
	_boss = BOSS_SCENE.instantiate()
	_boss.set("data", d)
	_room.add_child(_boss)
	_boss.global_position = Vector2(372.0, 300.0)

	# 玩家站到 Boss 左边、面朝右 —— 近战判定要够得着
	_player.global_position = Vector2(320.0, 288.0)
	_player.set("velocity", Vector2.ZERO)
	_player.set("_facing", 1)
	await _pframes(20)

	# ① 架势：护罩亮到一半，这时候**还能打**
	await _until(func() -> bool: return int(_boss.get("phases_started")) >= 1)
	await _pframes(20)
	await _shot("phase_1_warn.png")

	# ② 相位：护罩满亮 + 呼吸；这一帧砍上去，火花是冷蓝白的
	await _until(func() -> bool: return bool(_boss.call("is_phasing")))
	await _pframes(6)
	await _shot("phase_2_invuln.png")

	# ③ 砍在护罩上：等「铛」真的响了再截（等不到就是那条反馈断了）
	Audio.reset_counts()
	var clanged := false
	for _i in 90:
		Input.action_press("attack")
		await get_tree().physics_frame
		Input.action_release("attack")
		await get_tree().physics_frame
		if Audio.play_count(&"clang") > 0 and bool(_boss.call("is_phasing")):
			clanged = true
			break
	# **截图要顺便自证**：火花节点真的在场吗？不然「图里看不见」分不清是
	# 「根本没生成」还是「生成了但画不出来」—— 那种分不清最耗时间
	var fx := 0
	for n in get_tree().current_scene.get_children():
		if str(n.scene_file_path).ends_with("hit_fx.tscn"):
			fx += 1
	print("clang 触发=%s（必须 true）／ 在场火花节点=%d" % [str(clanged), fx])
	await _pframes(2)
	await _shot("phase_3_blocked.png")

	# ④ 恢复：护罩碎、原地硬直，可以放心打
	await _until(func() -> bool: return int(_boss.get("state")) == 7)
	await _pframes(6)
	await _shot("phase_4_recover.png")

	# ⑤ 单独验一下火花本身画不画得出来（留一张基准图）——
	# 「图里看不见」要先分清是「没生成」还是「画不出来」，否则会白查很久
	var probe: Node2D = (preload("res://scenes/components/hit_fx.tscn") as PackedScene).instantiate()
	probe.setup(Color(0.62, 0.88, 1.0), 16, 90.0, 0.9)
	get_tree().current_scene.add_child(probe)
	probe.global_position = Vector2(200.0, 240.0)
	await _pframes(6)
	await _shot("phase_5_spark_probe.png")

	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


func _until(pred: Callable) -> void:
	for _i in 600:
		if bool(pred.call()):
			return
		await get_tree().physics_frame
	push_error("等不到目标状态（600 帧超时）")


func _pframes(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
