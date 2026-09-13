extends Node
## 第 2/3 关的实机截图：断口 / 封印的门 / 第二个 Boss / 中途复活点 / 第 3 关高台。
##     godot --path <项目根> res://tests/shot_levels.tscn        （窗口模式，会弹窗）
##
## 构图要按**相机夹取后的落点**算：关卡贴到右边界时，相机中心停在
## `bounds.end.x - 320`，屏幕上能看到的只有最后 640px。摆错位置会拍出空景。

const LEVEL2 := preload("res://scenes/stages/level_2.tscn")
const LEVEL3 := preload("res://scenes/stages/level_3.tscn")


func _ready() -> void:
	# ── 一、第 2 关中段：断口 + 掷火者 ──────────────────────────
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _frames(6)
	_quiet(lv)
	var player := lv.get_node("Player")
	player.global_position = Vector2(1000.0, 296.0)
	await _frames(30)
	await _shot("level2_gap.png")

	# ── 二、第二个 Boss「石甲卫」挥锤的判定帧 ────────────────────
	var boss := lv.get_node("Boss2")
	player.global_position = Vector2(2520.0, 296.0)
	boss.global_position = Vector2(2680.0, 288)
	await _frames(30)
	# 让 Boss 真的把这锤挥出去：`ai_enabled = false` 时状态机整个不跑，
	# 只调 `_start_attack()` 等于「举了手但不挥」—— 截图里什么都看不到
	boss.set("ai_enabled", true)
	boss.set("_facing", -1)                 # 朝左（玩家在左边）—— AI 关着不会自己转向
	boss.call("_start_attack")
	boss.call("_enter", 2)                  # State.ATTACK
	await _frames(20)                       # 前摇 18 帧 → 此刻正好在判定窗口
	await _shot("level2_boss.png")
	boss.set("ai_enabled", false)

	# ── 三、被 Boss 封着的门 + 「封锁中」提示 ────────────────────
	# 把门挪到相机能完整看到的范围内：它本来贴着关卡最右边界，
	# 提示框（宽 220）会被视口右边切掉一半
	var gate := lv.get_node("Gate2") as Node2D
	gate.global_position = Vector2(2700.0, 290.0)
	player.global_position = Vector2(2640.0, 296.0)
	boss.global_position = Vector2(2790.0, 288)
	await _frames(30)
	gate.call("_flash_hint")
	await _frames(2)
	await _shot("level2_locked_gate.png")
	lv.queue_free()
	await _frames(4)

	# ── 四、中途复活点踩亮的样子 ─────────────────────────────────
	lv = LEVEL2.instantiate()
	add_child(lv)
	await _frames(6)
	_quiet(lv)
	player = lv.get_node("Player")
	var cp := lv.get_node("Checkpoint1") as Node2D
	player.global_position = cp.global_position
	await _frames(30)
	await _shot("checkpoint.png")
	lv.queue_free()
	await _frames(4)

	# ── 五、第 3 关：高台上一排掷火者 ────────────────────────────
	var lv3 := LEVEL3.instantiate()
	add_child(lv3)
	await _frames(6)
	_quiet(lv3)
	var p3 := lv3.get_node("Player")
	p3.global_position = Vector2(2190.0, 236.0)   # 站上高台
	await _frames(40)
	await _shot("level3_terrace.png")

	get_tree().paused = false
	get_tree().quit()


## 关掉 AI：截图要的是「看得清」，不是「打起来」——
## 一群怪围上来会把构图搅乱，人物还会被推离取景点
func _quiet(lv: Node) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and lv.is_ancestor_of(e):
			e.set("ai_enabled", false)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
