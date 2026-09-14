extends Node
## 《百炼》副本粒度自动验收：**一个副本 = 一条三屏的路**。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m9.tscn
##
## 前情：m1..m8 全绿。
##
## 这一组盯的是粒度重定（2026-09-14，神玩过第一版之后）带来的东西：
##   · **闸门真的挡人** —— 屏 1 没清空之前跑不过去（能冲过去 = 分段推进没生效）
##   · **清空一屏不回舆图** —— 只开闸门。这是神明确要的那一条
##     （第一版清完就弹舆图，他的反馈是「一关一屏不够，点进出频繁」）
##   · **整个副本打完才弹舆图**，光标落在**因此解锁的下一个副本**上
##   · 屏号跟着玩家走（HUD 上的「第 2 屏 / 共 3 屏」不是摆设）
##   · 副本通关写进存档、读档之后还在
##   · 舆图上「未开放」照实标（静默的空行 = bug）
##   · 死在里面 → 重开这个副本
##   · 地形在跳跃预算之内（看得见却跳不上去的台子）

const SaveGuard := preload("res://tests/save_guard.gd")

const LICHANG := preload("res://scenes/stages/lichang.tscn")
const ATLAS := preload("res://scenes/ui/atlas.tscn")

## 关卡根节点判「这一屏清空了」要等的帧数（stage.gd 的常量）
const CLEAR_DELAY := 24
## 通关横幅停留时间对应的帧数（BANNER_SEC 1.4 秒 × 60）+ 余量
const BANNER_FRAMES := 110
## 一屏多宽（stage.gd 的 SCREEN_WIDTH）
const SCREEN_W := 640.0

var _pass := 0
var _fail := 0
var _bak: Dictionary = {}
var _slot_before := 1
## 本测试根节点冒充「关卡根节点」：死亡时 player 会找 current_scene 上的
## restart()。测试里 current_scene 就是本节点 —— 于是能观测到「有没有被叫」
var _restart_called := false


## 冒充关卡根节点的重启入口。**刻意只记一笔、不真的重载** ——
## 真重载会把测试场景整个换掉，后面的用例全挂
func restart() -> void:
	_restart_called = true


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》副本粒度自动验收：三屏推进 ═══")
	_bak = SaveGuard.backup()
	_slot_before = SaveManager.current_slot
	SaveManager.current_slot = 1
	SaveManager.start_new_game(1, "res://scenes/stages/town.tscn")
	GameProgress.reset_progress()
	await _t1_structure()
	await _t2_gate_blocks()
	await _t3_clear_screen_opens_gate_no_atlas()
	await _t4_advance_and_clear_second()
	await _t5_clear_last_clears_dungeon()
	await _t6_progress_survives_save()
	await _t7_atlas_rows()
	await _t8_death_restarts_dungeon()
	await _t9_terrain_and_width()
	SaveManager.current_slot = _slot_before
	SaveGuard.restore(_bak)

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ── 工具 ───────────────────────────────────────────────────────

func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-3s %s\n              %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-3s %s\n              %s" % [id, desc, detail])


func _pframes(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _pkframes(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## 关掉整关的怪 AI。本组只关心结构与推进 ——
## 让一群怪围上来打玩家只会让断言随机会红
func _quiet(lv: Node) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and lv.is_ancestor_of(e):
			e.set("ai_enabled", false)


func _screen_node(lv: Node, i: int) -> Node2D:
	return lv.get_node_or_null("Screen%d" % (i + 1)) as Node2D


## 打死第 i 屏（0 起）的全部怪。走 Health.take_damage 的真实链路，
## 不是直接改 is_dead —— 那样测不出「打死了会不会清屏」
func _kill_screen(lv: Node, i: int) -> int:
	var s := _screen_node(lv, i)
	if s == null:
		return 0
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not s.is_ancestor_of(e):
			continue
		(e.get_node("Health") as Health).take_damage(9999, Vector2.ZERO, true, 1)
		n += 1
	return n


func _atlas_of(lv: Node) -> Node:
	return lv.get_node_or_null("Player/Atlas")


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


# ── 用例 ───────────────────────────────────────────────────────

## 副本数据与场景对得上：三屏、每屏有怪、Boss 在最后一屏、屏数与数据声明一致
func _t1_structure() -> void:
	var d := GameProgress.dungeon(&"lichang")
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var counts: Array[int] = []
	var boss_screen := -1
	var screens: int = lv.call("screen_count")
	for i in screens:
		var s := _screen_node(lv, i)
		var n := 0
		for e in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or s == null or not s.is_ancestor_of(e):
				continue
			n += 1
			if str(e.get("data").id) == "boss":
				boss_screen = i
		counts.append(n)
	var declared: int = d.screen_count if d != null else -1
	lv.queue_free()
	await _pframes(3)
	# 数据的 screen_count 与场景里实际摆的屏**必须相等** ——
	# 界面上的「共 N 屏」直接读数据，对不上就是显示错数字
	_check("1", "砺场：三屏、每屏都有怪、Boss 在最后一屏，且数据声明的屏数与场景一致",
		d != null and d.is_ready() and screens == 3 and declared == screens \
			and counts[0] >= 3 and counts[1] >= 3 and counts[2] >= 2 and boss_screen == 2,
		"屏数 %d（数据声明 %d）　各屏怪数 %s　Boss 在第 %d 屏" % [
			screens, declared, str(counts), boss_screen + 1])


## **闸门真的挡人** —— 这条不成立的话，「分段推进」就只是句口号
func _t2_gate_blocks() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var player := lv.get_node("Player")
	# 跑道上要**只剩闸门**：屏 1 的怪挪到起点身后去。
	# 怪的车身（collision_layer = enemy）是会挡人的 —— 第一版把玩家放在 450，
	# 正好撞上 x=470 的那只游荡者，被物理推着只动了 3px，
	# 而断言当时只看「x 有没有超过 620」，居然算通过（这就是那条断言现在
	# 还要检查「有没有真的跑到闸门跟前」的原因）
	for i in 3:
		var w := lv.get_node_or_null("Screen1/Walker%d" % (i + 1))
		if w != null:
			w.global_position = Vector2(60.0 + 40.0 * float(i), 288.0)
	# 起点在台阶右边（台阶占 x 220~380），前面到闸门是一条直路
	player.global_position = Vector2(420.0, 288.0)
	player.velocity = Vector2.ZERO
	await _pframes(10)
	# 真的按右跑过去（不是瞬移）—— 挡不挡人只有走一遍才知道
	_press("move_right")
	await _pframes(200)
	_release("move_right")
	await _pframes(4)
	var stopped_x: float = player.global_position.x
	var shape := lv.get_node("Gate1/CollisionShape2D") as CollisionShape2D
	var still_solid := shape != null and not shape.disabled
	lv.queue_free()
	await _pframes(3)
	_check("2", "屏 1 没清空之前，往右跑会被闸门挡在这一屏里",
		stopped_x > 560.0 and stopped_x < 620.0 and still_solid,
		"按右跑了 200 帧，停在 x=%.0f（应当贴着闸门停在 600 上下；闸门在 640，碰撞仍在=%s）" % [
			stopped_x, str(still_solid)])


## 清空屏 1：只开闸门，**不回舆图**（神明确要的那一条）
func _t3_clear_screen_opens_gate_no_atlas() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var killed := _kill_screen(lv, 0)
	await _pframes(CLEAR_DELAY + 10)
	var opened: bool = lv.call("is_screen_cleared", 0)
	var shape := lv.get_node("Gate1/CollisionShape2D") as CollisionShape2D
	var passable := shape != null and shape.disabled
	var atlas := _atlas_of(lv)
	var atlas_open := atlas != null and bool(atlas.call("is_open"))
	var dungeon_done: bool = lv.call("is_dungeon_cleared")
	lv.queue_free()
	await _pframes(3)
	_check("3", "清空第 1 屏 → 闸门放行，但**不回舆图**、副本也不算通关",
		killed >= 3 and opened and passable and not atlas_open and not dungeon_done,
		"打死 %d 只　放行=%s（碰撞已关=%s）　舆图弹出=%s　副本通关=%s" % [
			killed, str(opened), str(passable), str(atlas_open), str(dungeon_done)])


## 推进到屏 2：屏号跟着玩家走；清空屏 2 开第二道闸门
func _t4_advance_and_clear_second() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var player := lv.get_node("Player")
	_kill_screen(lv, 0)
	await _pframes(CLEAR_DELAY + 10)
	# 清完屏 1 之后往右走：这次应该能过去，而且屏号变成 2
	player.global_position = Vector2(560.0, 288.0)
	player.velocity = Vector2.ZERO
	await _pframes(6)
	_press("move_right")
	await _pframes(90)
	_release("move_right")
	await _pframes(4)
	var passed_x: float = player.global_position.x
	var screen_now: int = lv.call("current_screen")
	var killed2 := _kill_screen(lv, 1)
	await _pframes(CLEAR_DELAY + 10)
	var opened2: bool = lv.call("is_screen_cleared", 1)
	var atlas := _atlas_of(lv)
	var atlas_open := atlas != null and bool(atlas.call("is_open"))
	lv.queue_free()
	await _pframes(3)
	_check("4", "闸门开了就能走过界；屏号跟着玩家走；清空第 2 屏开第二道闸门（仍不回舆图）",
		passed_x > 660.0 and screen_now == 2 and killed2 >= 3 and opened2 and not atlas_open,
		"跑过界到 x=%.0f（>640）　屏号=%d　第 2 屏打死 %d 只　放行=%s　舆图弹出=%s" % [
			passed_x, screen_now, killed2, str(opened2), str(atlas_open)])


## 清空最后一屏（含 Boss）→ 副本通关 → **这时才弹舆图**
func _t5_clear_last_clears_dungeon() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	_kill_screen(lv, 0)
	await _pframes(CLEAR_DELAY + 4)
	_kill_screen(lv, 1)
	await _pframes(CLEAR_DELAY + 4)
	_kill_screen(lv, 2)
	await _pframes(CLEAR_DELAY + 10)
	var done: bool = lv.call("is_dungeon_cleared")
	var marked := SaveManager.is_cleared(&"lichang")
	# 通关横幅演完才弹舆图
	await _pframes(BANNER_FRAMES)
	var atlas := _atlas_of(lv)
	var atlas_open := atlas != null and bool(atlas.call("is_open"))
	if atlas_open:
		atlas.call("close")
	lv.queue_free()
	await _pframes(3)
	_check("5", "三屏全清 → 副本记为通关 → **这时才弹舆图**（且存档里也记上了）",
		done and marked and atlas_open,
		"副本通关=%s　存档已记=%s　舆图弹出=%s" % [str(done), str(marked), str(atlas_open)])


## 通关记录进存档，读档之后还在
func _t6_progress_survives_save() -> void:
	SaveManager.write_progress("res://scenes/stages/lichang.tscn",
		{"player": {"hp": 60, "shards": 7, "upgrade": 2}, "enemies": []})
	SaveManager.load_game(1)
	SaveManager.drop_pending_restore()     # 本用例只验进度，不恢复世界
	var cleared := SaveManager.is_cleared(&"lichang")
	var other := SaveManager.is_cleared(&"duancuiqu")
	# 第一个副本天生就开，不需要任何前提
	var first_open := GameProgress.is_dungeon_unlocked(&"lichang")
	_check("6", "副本通关记录写进了存档：读档之后还在；第一个副本天生就开",
		cleared and not other and first_open,
		"读档后砺场已通关=%s　断淬渠已通关=%s（它是空壳）　砺场开着=%s" % [
			str(cleared), str(other), str(first_open)])


## 舆图：一行一个副本，未开工的照实标「未开放」，文案不是翻译 key
func _t7_atlas_rows() -> void:
	var atlas := ATLAS.instantiate()
	add_child(atlas)
	await _pkframes(2)
	atlas.call("open")
	await _pkframes(2)
	var texts: Array[String] = atlas.call("row_texts")
	atlas.call("close")
	await _pkframes(2)
	atlas.queue_free()
	await _pkframes(2)

	var joined := "　".join(texts)
	# 漏翻 / 拼错 key 一律静默显示 key 字样，只能靠扫描抓
	var re := RegEx.new()
	re.compile("(UI|PANEL|HUD|ITEM|SLOT|STAT|DLG|NPC|MAP|DUNGEON)_[A-Z0-9_]+")
	var leaks := PackedStringArray()
	for m in re.search_all(joined):
		leaks.append(m.get_string())
	var shut := 0
	for t in texts:
		if t.contains(tr("UI_ATLAS_NOT_READY")):
			shut += 1
	var has_lichang := joined.contains(tr("DUNGEON_LICHANG"))
	var has_screens := joined.contains(I18n.t(&"UI_DUNGEON_SCREENS", [3]))
	var has_rec := joined.contains("Lv.1")
	var has_back := joined.contains(tr("UI_ATLAS_BACK"))
	# 3 个副本各一行 + 回安全区
	var right_rows := texts.size() == 4
	_check("7", "舆图一行一个副本：三个副本都在、没开工的标「未开放」、写着屏数与推荐实力、有回安全区",
		leaks.is_empty() and shut == 2 and has_lichang and has_screens and has_rec \
			and has_back and right_rows,
		"行数 %d（应为 4 = 3 副本 + 回安全区）　未开放 %d 行　砺场=%s　「3 屏」=%s　推荐=%s\n              回安全区=%s　文案泄漏: %s" % [
			texts.size(), shut, str(has_lichang), str(has_screens), str(has_rec),
			str(has_back), "无" if leaks.is_empty() else ", ".join(leaks)])


## 死在副本里 → 重开这个副本（不回城、也不原地满血）
func _t8_death_restarts_dungeon() -> void:
	_restart_called = false
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var player := lv.get_node("Player")
	# 挪到第 2 屏再打死 —— 重开副本的话玩家要从头再来，站在原地满血就不是这个行为
	player.global_position = Vector2(900.0, 288.0)
	await _pframes(3)
	(player.get_node("Health") as Health).take_damage(9999, Vector2.ZERO, true, 1)
	var revive_frames := int(ceil(float(player.get("revive_delay")) * 60.0)) + 30
	await _pframes(revive_frames)
	var called := _restart_called
	lv.queue_free()
	await _pframes(3)
	_check("8", "死在副本里 → 重开这个副本（不回城、也不原地满血）",
		called,
		"死亡 %d 帧后：副本被要求重开=%s" % [revive_frames, str(called)])


## 地形在跳跃预算内（抬升 ≤ 60px），副本宽度与三屏相符
func _t9_terrain_and_width() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var b: Rect2 = lv.get("bounds")
	var worst := _max_rise(lv)
	var screens: int = lv.call("screen_count")
	lv.queue_free()
	await _pframes(3)
	_check("9", "副本宽 = 屏数 × 一屏宽，且全副本最大抬升在跳跃高度之内",
		absf(b.size.x - SCREEN_W * float(screens)) <= 1.0 and worst <= 60.0,
		"副本宽 %.0f（%d 屏 × %.0f）　最大抬升 %.0fpx（跳跃上限约 73px）" % [
			b.size.x, screens, SCREEN_W, worst])


## 相邻平台之间最大的一次「抬升」（像素）。
## 抬升超预算的台子**看得见但上不去**，而且不报错，只会让人以为「这跳台是装饰」
func _max_rise(lv: Node) -> float:
	var rects: Array[Rect2] = []
	for c in lv.get_children():
		if not (c is StaticBody2D):
			continue
		var cs := c.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs == null or not (cs.shape is RectangleShape2D):
			continue
		var sh := cs.shape as RectangleShape2D
		# 只算「横着的台面」：地面、台阶、浮台都是宽 > 高的。
		# 闸门是**竖着的**（40×320），把它算进来会得出一个荒谬的抬升数字 ——
		# 那道墙不是给人踩的，它是用来挡人的
		if sh.size.x <= sh.size.y:
			continue
		var sz: Vector2 = sh.size
		rects.append(Rect2((c as Node2D).global_position - sz * 0.5, sz))
	rects.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	var worst := 0.0
	for i in range(1, rects.size()):
		var rise: float = rects[i - 1].position.y - rects[i].position.y
		if rise > worst:
			worst = rise
	return worst
