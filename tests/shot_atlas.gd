extends Node
## 舆图、屏号、分段推进、死亡界面的观感截图（输出 `build/shots/`）。
##     godot --path <项目根> res://tests/shot_atlas.tscn
##
## 为什么必须看图：
##   · 舆图的行是**代码建出来的一堆 Label**（没有 tscn 可查）—— 对齐、行距、
##     会不会压住右上角的精铁、「未开放」的灰看起来对不对，断言一条都抓不到。
##   · HUD 上那行屏号是一行小字，挤不挤只有眼睛能判。
##   · **挡墙是看不见的**（这一版特意删掉了可见闸门）：玩家被什么挡住、挡住的
##     那一刻屏幕上有没有话说，只有看图才知道（`test_m9 #2` 只验它挡不挡人）。
##   · **一批怪凭空出现**的过程（淡入）看起来是"来了"还是"闪了一下"。
##   · 死亡界面的两个选项排版、光标标记，断言只验得到"有没有"。
##
## 会动存档槽（要摆出「已通关」的状态）—— 所以和测试一样先备份、跑完还回去。

const TOWN := preload("res://scenes/stages/town.tscn")
const LICHANG := preload("res://scenes/stages/lichang.tscn")
const SaveGuard := preload("res://tests/save_guard.gd")

## 一屏多宽（stage.gd 的 SCREEN_WIDTH）、判"这一波清了"要等的帧数、两波间隔
const SCREEN_W := 960.0
const CLEAR_DELAY := 24
const WAVE_GAP := 45

var _bak: Dictionary = {}


## 冒充关卡根节点：死亡界面只在 `current_scene` 有 `restart()` 时才弹
## （没关卡可重开就退回原地满血）。截图脚本的根节点不是关卡，所以补一个空壳 ——
## 不补的话拍到的是"原地满血站起来了"，和标题对不上
func restart() -> void:
	pass


func _ready() -> void:
	_bak = SaveGuard.backup()
	SaveManager.current_slot = 3
	SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")
	await _shot_pedestal()
	await _shot_atlas_fresh()
	await _shot_atlas_progressed()
	await _shot_screens()
	await _shot_death_menu()
	SaveGuard.restore(_bak)
	get_tree().paused = false
	get_tree().quit()


## 一、安全区的舆图台：走近之后提示要看得见、位置要压不住别的设施
func _shot_pedestal() -> void:
	GameProgress.reset_progress()
	var town := TOWN.instantiate()
	add_child(town)
	await _frames(5)
	var p := town.get_node("Player")
	p.global_position = town.get_node("AtlasPedestal").global_position + Vector2(-30.0, 0.0)
	p.velocity = Vector2.ZERO
	await _frames(12)
	await _shot("atlas_stand.png")
	town.queue_free()
	await _frames(3)


## 二、刚开局打开舆图：砺场可进，另外两个副本「未开放」
func _shot_atlas_fresh() -> void:
	GameProgress.reset_progress()
	var town := TOWN.instantiate()
	add_child(town)
	await _frames(5)
	var atlas := town.get_node("Player/Atlas")
	atlas.call("open")
	await _frames(4)
	await _shot("atlas_fresh.png")
	atlas.call("close")
	await _frames(2)
	town.queue_free()
	await _frames(3)


## 三、通关之后：砺场那行变「已通关」，光标停在那儿
func _shot_atlas_progressed() -> void:
	SaveManager.mark_cleared(&"lichang")
	var town := TOWN.instantiate()
	add_child(town)
	await _frames(5)
	var atlas := town.get_node("Player/Atlas")
	atlas.call("open")
	await _frames(4)
	await _shot("atlas_progressed.png")
	atlas.call("close")
	await _frames(2)
	town.queue_free()
	await _frames(3)


## 四、第 1 屏：第 1 批怪、HUD 写「砺场 · 第 1 屏 / 共 3 屏」
## 五、跑到最右侧：被**看不见的挡墙**挡住，横幅给一句人话
## 六、打完第 1 批：第 2 批淡入（分批出怪的观感）
## 七、清完第 1 屏之后走进第 2 屏：屏号变成 2、挡墙没了
func _shot_screens() -> void:
	GameProgress.reset_progress()
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _frames(6)
	for e in get_tree().get_nodes_in_group("enemy"):
		if lv.is_ancestor_of(e):
			e.set("ai_enabled", false)
	var p := lv.get_node("Player")
	p.global_position = Vector2(320.0, 288.0)
	p.velocity = Vector2.ZERO
	await _frames(20)
	await _shot("screen_batch1.png")

	# 贴到挡墙前：这里是**看不见的**，所以图上该看到的是"人撞住了 + 一行提示"。
	# **得真的跑过去撞上** —— 提示的触发条件是人离墙 20px 以内，
	# 站在 40px 外摆姿势是拍不到的（第一版就是这么拍的，图上什么都没有）
	p.global_position = Vector2(SCREEN_W - 120.0, 288.0)
	p.velocity = Vector2.ZERO
	await _frames(6)
	_press("move_right")
	await _frames(45)
	_release("move_right")
	await _frames(12)
	await _shot("screen_blocked.png")

	# 打死第 1 批 → 等够间隔 → 第 2 批刚淡入那一刻
	_kill_batch(lv, 0)
	await _frames(CLEAR_DELAY + WAVE_GAP + 6)
	await _shot("screen_batch2.png")

	# 把这一屏剩下的两批也打完，然后走进第 2 屏
	for _i in 2:
		_kill_batch(lv, 0)
		await _frames(CLEAR_DELAY + WAVE_GAP + 10)
	p.global_position = Vector2(SCREEN_W + 120.0, 288.0)
	p.velocity = Vector2.ZERO
	await _frames(24)
	await _shot("screen_advanced.png")
	lv.queue_free()
	await _frames(3)


## 打死第 i 屏场上**还活着**的那一批（尸体留在组里，不跳过的话会把它们数进去）
func _kill_batch(lv: Node, i: int) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not lv.is_ancestor_of(e):
			continue
		var s := lv.get_node_or_null("Screen%d" % (i + 1))
		if s == null or not s.is_ancestor_of(e):
			continue
		var h := e.get_node("Health") as Health
		if not h.is_dead:
			h.take_damage(9999, Vector2.ZERO, true, 1)


## 八、倒下之后弹的二选一：两个选项、光标在「重新开始」上
func _shot_death_menu() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _frames(6)
	var p := lv.get_node("Player")
	(p.get_node("Health") as Health).take_damage(9999, Vector2.ZERO, true, 1)
	await _frames(int(ceil(float(p.get("revive_delay")) * 60.0)) + 30)
	await _shot("death_menu.png")
	lv.queue_free()
	await _frames(3)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


## 注入一次「按下 / 松开」。窗口脚本里注入的输入会被整帧跳过（process 与 physics
## 不同步），所以调用方要留够帧数，必要时循环重试到状态量真的变了
func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)


func _release(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	ev.strength = 0.0
	Input.parse_input_event(ev)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
