extends Node
## 《百炼》副本粒度自动验收：**一个副本 = 一条更长的三屏路 + 分批出怪 + 死亡二选一**。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m9.tscn
##
## 前情：m1..m8 全绿。
##
## 这一组盯的是**神的第二轮反馈**（2026-09-14，他玩过「一屏一关」那一版之后）：
##   · 「每一屏幕长度不够长」            → 屏宽 640 → 960，相机跟着滚
##   · 「不需要闸门去隔离，一屏的怪没清理完走到最右侧也走不过去」
##        → 闸门**删了**，改成看不见的挡墙；这条断言同时盯"挡得住"和"看不见"
##   · 「一屏 3 只不够，要分批出：打死一批接着来第二批」
##        → 波次：开场只有第 1 波醒着，打完才出下一波
##   · 「死亡后有两个选项：重新开始 / 返回城镇」
##        → 死亡界面；断言盯"弹了没 / 两个选项都在 / 第一个真的能重开"
##
## 上一轮（被推翻的那些）的断言留在 test_m3 / test_m8 里改过，不在这里重复。

const SaveGuard := preload("res://tests/save_guard.gd")

const LICHANG := preload("res://scenes/stages/lichang.tscn")
const ATLAS := preload("res://scenes/ui/atlas.tscn")
const TOWN_PATH := "res://scenes/stages/town.tscn"

## 关卡根节点判「这一波清了」要等的帧数（stage.gd 的常量）
const CLEAR_DELAY := 24
## 两波之间的间隔帧数（stage.gd 的常量）
const WAVE_GAP := 45
## 通关横幅停留时间对应的帧数（BANNER_SEC 1.4 秒 × 60）+ 余量
const BANNER_FRAMES := 110
## 一屏多宽（stage.gd 的 SCREEN_WIDTH）
const SCREEN_W := 960.0

var _pass := 0
var _fail := 0
var _bak: Dictionary = {}
var _slot_before := 1
## 本测试根节点冒充「关卡根节点」：死亡界面的「重新开始」会找 current_scene 上的
## restart()。测试里 current_scene 就是本节点 —— 于是能观测到「有没有被叫」
var _restart_called := false


## 冒充关卡根节点的重启入口。**刻意只记一笔、不真的重载** ——
## 真重载会把测试场景整个换掉，后面的用例全挂
func restart() -> void:
	_restart_called = true


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》副本粒度自动验收：更长屏 / 分批出怪 / 死亡二选一 ═══")
	_bak = SaveGuard.backup()
	_slot_before = SaveManager.current_slot
	SaveManager.current_slot = 1
	SaveManager.start_new_game(1, TOWN_PATH)
	GameProgress.reset_progress()
	await _t1_structure()
	await _t2_barrier_blocks_and_is_invisible()
	await _t3_waves_come_in_batches()
	await _t4_clear_screen_opens_way_no_atlas()
	await _t5_advance_and_clear_second()
	await _t6_clear_last_clears_dungeon()
	await _t7_progress_survives_save()
	await _t8_atlas_rows()
	await _t9_death_menu()
	await _t10_terrain_and_width()
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


## 关掉整关的怪 AI —— **连还没出场的一起关**。
##
## 遍历的是整棵树而不是 `enemy` 组：休眠中的怪已经退组了，
## 只用组去找的话，等它们出场时 AI 是开着的，会当场围上来把玩家的血打空，
## 后面的断言就开始随机红
func _quiet(lv: Node) -> void:
	for e in lv.find_children("*", "CharacterBody2D", true, false):
		if e.has_method("is_alive") and e.has_method("set_dormant"):
			e.set("ai_enabled", false)


func _screen_node(lv: Node, i: int) -> Node2D:
	return lv.get_node_or_null("Screen%d" % (i + 1)) as Node2D


func _wave_node(lv: Node, i: int, w: int) -> Node2D:
	return lv.get_node_or_null("Screen%d/Wave%d" % [i + 1, w + 1]) as Node2D


## 某个容器下**醒着**的怪有几只。休眠中的怪已经退出 `enemy` 组，所以数不到
func _awake_under(node: Node) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and node != null and node.is_ancestor_of(e):
			n += 1
	return n


## 打死某一屏场上活着的全部怪（= 当前这一波）。
## 走 Health.take_damage 的真实链路，不是直接改 is_dead —— 那样测不出"打死了会不会推进"。
## **跳过已经躺下的**：尸体还留在 `enemy` 组里，不跳的话第二波会连尸体一起数进去
func _kill_screen(lv: Node, i: int) -> int:
	var s := _screen_node(lv, i)
	if s == null:
		return 0
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not s.is_ancestor_of(e):
			continue
		var h := e.get_node("Health") as Health
		if h.is_dead:
			continue
		h.take_damage(9999, Vector2.ZERO, true, 1)
		n += 1
	return n


## 走到第 i 屏（0 起）并把这一屏的几波全打完。返回打死的总数。
##
## **必须真的把人挪过去**：没走到过的屏，怪还没出场（`_started` 为假），
## 隔着两屏去杀怪是杀不到东西的 —— 第一版就是这么写的，#6 因此判"没通关"，
## 而它其实是"测试根本没打到那一屏"
func _clear_screen(lv: Node, i: int) -> int:
	var player := lv.get_node_or_null("Player") as Node2D
	if player != null:
		player.global_position = Vector2(float(i) * SCREEN_W + 60.0, 288.0)
		player.velocity = Vector2.ZERO
		await _pframes(8)
	var waves: int = lv.call("screen_wave_count", i)
	var killed := 0
	for _w in waves:
		killed += _kill_screen(lv, i)
		await _pframes(CLEAR_DELAY + WAVE_GAP + 10)
	return killed


func _atlas_of(lv: Node) -> Node:
	return lv.get_node_or_null("Player/Atlas")


## 挡墙还实心吗（碰撞体没被关掉）
func _barrier_solid(lv: Node, i: int) -> bool:
	var b: Node2D = lv.call("barrier_node", i)
	if b == null:
		return false
	var cs := b.get_node_or_null("CollisionShape2D") as CollisionShape2D
	return cs != null and not cs.disabled


## 挡墙有没有**画出来的东西**。
## 注意 `CollisionShape2D` 本身也是 CanvasItem —— 拿 "是不是 CanvasItem" 去筛，
## 任何挡墙都会"有外观"（第一版就这么误判了）。要筛的是会画东西的那几种
func _barrier_has_visual(lv: Node, i: int) -> bool:
	var b: Node2D = lv.call("barrier_node", i)
	if b == null:
		return false
	for c in b.get_children():
		if c is ColorRect or c is Sprite2D or c is Polygon2D or c is Line2D:
			return true
	return false


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

## 副本数据与场景对得上：三屏、每屏三波、Boss 在最后一屏的最后一波
func _t1_structure() -> void:
	var d := GameProgress.dungeon(&"lichang")
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(4)
	_quiet(lv)
	var screens: int = lv.call("screen_count")
	var wave_counts: Array[int] = []
	var boss_at := Vector2i(-1, -1)
	var total := 0
	for i in screens:
		wave_counts.append(lv.call("screen_wave_count", i))
		for w in int(lv.call("screen_wave_count", i)):
			var wn := _wave_node(lv, i, w)
			if wn == null:
				continue
			total += wn.get_child_count()
			for e in wn.get_children():
				if str(e.get("data").id) == "boss":
					boss_at = Vector2i(i, w)
	var declared: int = d.screen_count if d != null else -1
	lv.queue_free()
	await _pframes(3)
	var every_screen_multi: bool = wave_counts.size() == 3 \
		and wave_counts[0] >= 2 and wave_counts[1] >= 2 and wave_counts[2] >= 2
	_check("1", "砺场：三屏、每屏都分好几批、Boss 在最后一屏的最后一批，且屏数与数据一致",
		d != null and d.is_ready() and screens == 3 and declared == screens \
			and every_screen_multi and boss_at == Vector2i(screens - 1, wave_counts[screens - 1] - 1) \
			and total >= 24,
		"屏数 %d（数据声明 %d）　各屏批数 %s　小怪+Boss 共 %d 只　Boss 在第 %d 屏第 %d 批" % [
			screens, declared, str(wave_counts), total, boss_at.x + 1, boss_at.y + 1])


## **挡得住 + 看不见** —— 神否决了闸门，"一屏没清完走到最右侧也走不过去"。
## 这两条缺一条都不成立：挡不住 = 分段推进是空话；看得见 = 退回了被否的版本
func _t2_barrier_blocks_and_is_invisible() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(4)
	_quiet(lv)
	# 跑道上要**只剩挡墙**：第 1 批的怪挪到起点身后去。
	# 怪的车身（collision_layer = enemy）是会挡人的 —— 上一版把玩家放在 450，
	# 正好撞上 x=470 的那只怪，被物理推着只动了 3px，而断言当时只检查
	# 「x 有没有超过 620」→ **居然算通过**。所以下面两头都卡
	var w1 := _wave_node(lv, 0, 0)
	if w1 != null:
		for k in w1.get_child_count():
			(w1.get_child(k) as Node2D).global_position = Vector2(100.0 + 40.0 * float(k), 288.0)
	var player := lv.get_node("Player")
	# 起点在台阶右边（台阶占 x 260~420），前面到挡墙是一条直路
	player.global_position = Vector2(440.0, 288.0)
	player.velocity = Vector2.ZERO
	await _pframes(10)
	# 真的按右跑过去（不是瞬移）—— 挡不挡人只有走一遍才知道
	_press("move_right")
	await _pframes(200)
	_release("move_right")
	await _pframes(4)
	var stopped_x: float = player.global_position.x
	var solid := _barrier_solid(lv, 0)
	var has_visual := _barrier_has_visual(lv, 0)
	var bnode: Node2D = lv.call("barrier_node", 0)
	var bx := bnode.global_position.x if bnode != null else 0.0
	lv.queue_free()
	await _pframes(3)
	_check("2", "屏 1 没清完 → 走到最右侧被挡住（挡路的**看不见**）",
		stopped_x > SCREEN_W - 90.0 and stopped_x < SCREEN_W - 10.0 and solid and not has_visual,
		"按右跑了 200 帧，停在 x=%.0f（挡墙中心 %.0f；实心=%s，有可见外观=%s）" % [
			stopped_x, bx, str(solid), str(has_visual)])


## **分批出怪** —— 神要的那一条。开场只有第 1 批醒着；打完才出第 2 批
func _t3_waves_come_in_batches() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(6)
	_quiet(lv)
	var awake_1 := _awake_under(_wave_node(lv, 0, 0))
	var awake_2 := _awake_under(_wave_node(lv, 0, 1))
	var awake_3 := _awake_under(_wave_node(lv, 0, 2))
	var act0: int = lv.call("active_wave", 0)
	var wc: int = lv.call("screen_wave_count", 0)
	var batch1 := "%d/%d/%d" % [awake_1, awake_2, awake_3]

	# 打死第 1 批 → 等过间隔 → 第 2 批出场
	_kill_screen(lv, 0)
	await _pframes(CLEAR_DELAY + 4)
	var done_after := int(lv.call("waves_done", 0))
	await _pframes(WAVE_GAP + 12)
	var awake_2b := _awake_under(_wave_node(lv, 0, 1))
	var act1: int = lv.call("active_wave", 0)
	var still_asleep := _awake_under(_wave_node(lv, 0, 2))
	lv.queue_free()
	await _pframes(3)
	_check("3", "分批出怪：开场只有第 1 批醒着，打完第 1 批才出第 2 批（第 3 批还在等）",
		awake_1 >= 2 and awake_2 == 0 and awake_3 == 0 and act0 == 0 and wc >= 3 \
			and done_after == 1 and act1 == 1 and awake_2b >= 2 and still_asleep == 0,
		"开场 批次1/2/3 醒着的只数 = %s（场上批次号 %d，共 %d 批）\n              打完第 1 批 → 已完成 %d 批 → 第 2 批醒 %d 只（批次号 %d），第 3 批仍睡 %d 只" % [
			batch1, act0, wc, done_after, awake_2b, act1, still_asleep])


## 清空一屏：**只放行，不回舆图**（神明确要的那一条）
func _t4_clear_screen_opens_way_no_atlas() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(4)
	_quiet(lv)
	var killed: int = await _clear_screen(lv, 0)
	var opened: bool = lv.call("is_screen_cleared", 0)
	var passable := not _barrier_solid(lv, 0)
	var atlas := _atlas_of(lv)
	var atlas_open := atlas != null and bool(atlas.call("is_open"))
	var dungeon_done: bool = lv.call("is_dungeon_cleared")
	lv.queue_free()
	await _pframes(3)
	_check("4", "打完一整屏的几批怪 → 挡墙拆掉放行，但**不回舆图**、副本也不算通关",
		killed >= 6 and opened and passable and not atlas_open and not dungeon_done,
		"三批共打死 %d 只　放行=%s（挡墙已实心=%s）　舆图弹出=%s　副本通关=%s" % [
			killed, str(opened), str(not passable), str(atlas_open), str(dungeon_done)])


## 推进到屏 2：屏号跟着玩家走；打完屏 2 拆第二道挡墙（仍不回舆图）
func _t5_advance_and_clear_second() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(4)
	_quiet(lv)
	await _clear_screen(lv, 0)
	var player := lv.get_node("Player")
	# 清完屏 1 之后往右走：这次应该能过去，而且屏号变成 2
	player.global_position = Vector2(900.0, 288.0)
	player.velocity = Vector2.ZERO
	await _pframes(6)
	_press("move_right")
	await _pframes(90)
	_release("move_right")
	await _pframes(4)
	var passed_x: float = player.global_position.x
	var screen_now: int = lv.call("current_screen")
	var killed2: int = await _clear_screen(lv, 1)
	var opened2: bool = lv.call("is_screen_cleared", 1)
	var atlas := _atlas_of(lv)
	var atlas_open := atlas != null and bool(atlas.call("is_open"))
	lv.queue_free()
	await _pframes(3)
	_check("5", "挡墙拆了就能走过界；屏号跟着玩家走；打完第 2 屏拆第二道墙（仍不回舆图）",
		passed_x > SCREEN_W + 20.0 and screen_now == 2 and killed2 >= 6 \
			and opened2 and not atlas_open,
		"跑过界到 x=%.0f（界在 %.0f）　屏号=%d　第 2 屏打死 %d 只　放行=%s　舆图弹出=%s" % [
			passed_x, SCREEN_W, screen_now, killed2, str(opened2), str(atlas_open)])


## 打完最后一屏（含 Boss）→ 副本通关 → **这时才弹舆图**
func _t6_clear_last_clears_dungeon() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(4)
	_quiet(lv)
	await _clear_screen(lv, 0)
	await _clear_screen(lv, 1)
	await _clear_screen(lv, 2)
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
	_check("6", "三屏全打完 → 副本记为通关 → **这时才弹舆图**（且存档里也记上了）",
		done and marked and atlas_open,
		"副本通关=%s　存档已记=%s　舆图弹出=%s" % [str(done), str(marked), str(atlas_open)])


## 通关记录进存档，读档之后还在
func _t7_progress_survives_save() -> void:
	SaveManager.write_progress("res://scenes/stages/lichang.tscn",
		{"player": {"hp": 60, "shards": 7, "upgrade": 2}, "enemies": []})
	SaveManager.load_game(1)
	SaveManager.drop_pending_restore()     # 本用例只验进度，不恢复世界
	var cleared := SaveManager.is_cleared(&"lichang")
	var other := SaveManager.is_cleared(&"duancuiqu")
	# 第一个副本天生就开，不需要任何前提
	var first_open := GameProgress.is_dungeon_unlocked(&"lichang")
	_check("7", "副本通关记录写进了存档：读档之后还在；第一个副本天生就开",
		cleared and not other and first_open,
		"读档后砺场已通关=%s　断淬渠已通关=%s（它是空壳）　砺场开着=%s" % [
			str(cleared), str(other), str(first_open)])


## 舆图：一行一个副本，未开工的照实标「未开放」，文案不是翻译 key
func _t8_atlas_rows() -> void:
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
	# 3 个副本各一行 + 回安全区。**副本不再展开屏** —— 屏是副本内部的事
	var right_rows := texts.size() == 4
	_check("8", "舆图一行一个副本：三个副本都在、没开工的标「未开放」、写着屏数与推荐实力、有回安全区",
		leaks.is_empty() and shut == 2 and has_lichang and has_screens and has_rec \
			and has_back and right_rows,
		"行数 %d（应为 4 = 3 副本 + 回安全区）　未开放 %d 行　砺场=%s　「3 屏」=%s　推荐=%s\n              回安全区=%s　文案泄漏: %s" % [
			texts.size(), shut, str(has_lichang), str(has_screens), str(has_rec),
			str(has_back), "无" if leaks.is_empty() else ", ".join(leaks)])


## 死亡 → **弹二选一**（重开 / 回城），第一个选项真的能重开
func _t9_death_menu() -> void:
	_restart_called = false
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(4)
	_quiet(lv)
	var player := lv.get_node("Player")
	var dm := lv.get_node_or_null("Player/DeathMenu")
	var before := dm != null and bool(dm.call("is_open"))
	(player.get_node("Health") as Health).take_damage(9999, Vector2.ZERO, true, 1)
	var revive_frames := int(ceil(float(player.get("revive_delay")) * 60.0)) + 30
	await _pframes(revive_frames)
	var opened := dm != null and bool(dm.call("is_open"))
	var texts: Array[String] = []
	if opened:
		texts = dm.call("row_texts")
	var joined := "　".join(texts)
	var re := RegEx.new()
	re.compile("(UI|PANEL|HUD|ITEM|SLOT|STAT|DLG|NPC|MAP|DUNGEON)_[A-Z0-9_]+")
	var leaks := PackedStringArray()
	for m in re.search_all(joined):
		leaks.append(m.get_string())
	var two := texts.size() == 2
	var wired: bool = bool(dm.call("is_row_wired", 0)) and bool(dm.call("is_row_wired", 1))
	var town_ok := ResourceLoader.exists(TOWN_PATH)
	# 光标往下走一格 → 停在第二项
	dm.call("_move", 1)
	var cursor_moved: int = dm.call("cursor")
	dm.call("_move", -1)
	# 选第一项（重新开始）→ 由「冒充关卡根节点」的 restart() 记一笔
	dm.call("_activate")
	await _pframes(3)
	var called := _restart_called
	if dm != null and bool(dm.call("is_open")):
		dm.call("close")
	get_tree().paused = false
	lv.queue_free()
	await _pframes(3)
	_check("9", "倒下 → 弹二选一（重新开始 / 返回城镇）；两个选项都接了动作；选「重新开始」真的重开",
		two and opened and not before and leaks.is_empty() and wired and cursor_moved == 1 \
			and called and town_ok,
		"倒下前开着=%s → %d 帧后开着=%s　选项 %s（两项都接了动作=%s，↓ 后光标=%d）\n              选「重新开始」→ 副本被要求重开=%s　回城场景存在=%s　文案泄漏: %s" % [
			str(before), revive_frames, str(opened), str(texts), str(wired),
			cursor_moved, str(called), str(town_ok),
			"无" if leaks.is_empty() else ", ".join(leaks)])


## 地形在跳跃预算内（抬升 ≤ 60px），副本宽度与三屏相符
func _t10_terrain_and_width() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _pframes(4)
	_quiet(lv)
	var b: Rect2 = lv.get("bounds")
	var worst := _max_rise(lv)
	var screens: int = lv.call("screen_count")
	lv.queue_free()
	await _pframes(3)
	_check("10", "副本宽 = 屏数 × 一屏宽（一屏比视口宽，所以走得动），且全副本最大抬升在跳跃高度之内",
		absf(b.size.x - SCREEN_W * float(screens)) <= 1.0 and worst <= 60.0,
		"副本宽 %.0f（%d 屏 × %.0f，视口只有 640）　最大抬升 %.0fpx（跳跃上限约 73px）" % [
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
		# 挡墙是**竖着的**（8×480），把它算进来会得出一个荒谬的抬升数字 ——
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
