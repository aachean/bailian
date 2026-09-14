extends Node
## 《百炼》三层结构（地图 → 副本 → 关卡）自动验收：砺场竖向切片。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m9.tscn
##
## 前情：m1..m8 全绿。
##
## 本组盯的是「结构从线性三关换成三层」之后才会出现的问题：
##   · 砺场的三段是不是真的各自独立、各自摆得出来（而不是名字换了的三张图）
##   · 「清空过关」这条判据到底会不会触发 —— 不触发的话后面全都不解锁
##   · 逐段解锁只认「打过的那一段」，不能多开也不能少开
##   · 跨副本解锁（清完一个副本 → 下一个副本开锁）现在就得是对的，
##     哪怕下一个副本还没内容 —— 不能等填内容时才发现它从来没工作过
##   · 存档里记的解锁进度，读档之后还在不在
##   · 舆图上「未解锁」是不是看得见（静默的空行 = bug）
##   · 死在本关是不是重开本关（而不是原地满血、也不是回城）
##   · 一屏关卡的地形有没有超出跳跃预算（看得见却跳不上去的台子）

const SaveGuard := preload("res://tests/save_guard.gd")

const LICHANG_1 := preload("res://scenes/stages/lichang_1.tscn")
const LICHANG_2 := preload("res://scenes/stages/lichang_2.tscn")
const LICHANG_3 := preload("res://scenes/stages/lichang_3.tscn")
const ATLAS := preload("res://scenes/ui/atlas.tscn")

## 关卡最后一只怪倒下到判过关之间，关卡根节点要等的帧数（stage.gd 的常量）
const CLEAR_DELAY := 24
## 过关横幅停留时间对应的帧数（BANNER_SEC 1.3 秒 × 60）+ 余量
const BANNER_FRAMES := 100

var _pass := 0
var _fail := 0
var _bak: Dictionary = {}
var _slot_before := 1
## 本测试根节点冒充「关卡根节点」：玩家死亡时 player 会找 current_scene 上的
## restart()。测试里 current_scene 就是本节点 —— 于是能观测到「有没有被叫」
var _restart_called := false


## 冒充关卡根节点的重启入口。**刻意只记一笔、不真的重载** ——
## 真重载会把测试场景整个换掉，后面的用例全挂
func restart() -> void:
	_restart_called = true


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》三层结构自动验收：砺场竖向切片 ═══")
	_bak = SaveGuard.backup()
	_slot_before = SaveManager.current_slot
	SaveManager.current_slot = 1
	SaveManager.start_new_game(1, "res://scenes/stages/town.tscn")
	GameProgress.reset_progress()
	await _t1_structure()
	await _t2_new_game_unlocks_first_only()
	await _t3_clear_unlocks_next()
	await _t4_clear_last_marks_dungeon()
	await _t5_cross_dungeon_rule()
	await _t6_progress_survives_save()
	await _t7_atlas_rows()
	await _t8_death_restarts_stage()
	await _t9_one_screen_within_jump_budget()
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


## 物理帧。关卡推进（打怪 / 判过关 / 死亡计时）都在物理帧里走
func _pframes(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## 进程帧。舆图是 UI（CanvasLayer），它的开关与输入走 process 帧
func _pkframes(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## 关掉整关的怪 AI。本组只关心结构与推进 ——
## 让一群怪围上来打玩家只会让断言随机会红
func _quiet(lv: Node) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and lv.is_ancestor_of(e):
			e.set("ai_enabled", false)


## 把本关卡里的怪全部打死（走 Health.take_damage 的真实链路，
## 不是直接改 is_dead —— 那样测不出「打死了会不会过关」）
func _kill_all(lv: Node) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not lv.is_ancestor_of(e):
			continue
		(e.get_node("Health") as Health).take_damage(9999, Vector2.ZERO, true, 1)
		n += 1
	return n


func _enemy_count(lv: Node) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and lv.is_ancestor_of(e):
			n += 1
	return n


## 关卡过关后会弹舆图（真暂停）。观测完要收干净，否则后面的用例全在暂停里跑
func _dismiss_atlas(lv: Node) -> bool:
	await _pframes(BANNER_FRAMES)
	var atlas := lv.get_node_or_null("Player/Atlas")
	var opened := atlas != null and bool(atlas.call("is_open"))
	if opened:
		atlas.call("close")
	return opened


# ── 用例 ───────────────────────────────────────────────────────

## 砺场三段：数据在、场景在、各段都有怪、最后一段才有 Boss
func _t1_structure() -> void:
	var m := GameProgress.map()
	var d := m.find_dungeon(&"lichang") if m != null else null
	var n_stages := 0 if d == null else d.stages.size()
	var missing := PackedStringArray()
	var boss_at := -1
	var counts: Array[int] = []
	if d != null:
		for i in d.stages.size():
			var st := d.stages[i]
			if st == null or not ResourceLoader.exists(st.scene_path):
				missing.append(str(st.id) if st != null else "null")
				continue
			var lv := (load(st.scene_path) as PackedScene).instantiate()
			add_child(lv)
			await _pframes(3)
			_quiet(lv)
			counts.append(_enemy_count(lv))
			for e in get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(e) and lv.is_ancestor_of(e) \
						and str(e.get("data").id) == "boss":
					boss_at = i
			lv.queue_free()
			await _pframes(2)
	_check("1", "砺场是三段独立关卡：数据齐、场景都在、每段有怪、Boss 只在最后一段",
		n_stages == 3 and missing.is_empty() and counts.size() == 3 \
			and counts[0] >= 2 and counts[1] >= 2 and counts[2] >= 2 and boss_at == 2,
		"三段=%d　缺场景=%s　各段怪数=%s　Boss 在第 %d 段" % [
			n_stages, "无" if missing.is_empty() else ", ".join(missing),
			str(counts), boss_at + 1])


## 新游戏：只有第一段能进，后面两段锁着
func _t2_new_game_unlocks_first_only() -> void:
	GameProgress.reset_progress()
	var m := GameProgress.map()
	var d := m.find_dungeon(&"lichang")
	var open: Array[bool] = []
	if d != null:
		for i in d.stages.size():
			open.append(GameProgress.is_stage_unlocked(d.id, i))
	var other := GameProgress.is_dungeon_unlocked(&"duancuiqu")
	_check("2", "新游戏开局只开砺场第 1 段：后面两段锁着、别的副本整片锁着",
		open.size() == 3 and open[0] and not open[1] and not open[2] and not other,
		"砺场三段可进=%s　断淬渠已开=%s" % [str(open), str(other)])


## 清空第 1 段的**完整链路**：打光怪 → 判过关 → 解锁第 2 段 → 弹出舆图
func _t3_clear_unlocks_next() -> void:
	GameProgress.reset_progress()
	var lv := LICHANG_1.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var killed := _kill_all(lv)
	var before := GameProgress.is_stage_unlocked(&"lichang", 1)
	await _pframes(CLEAR_DELAY + 8)
	var after := GameProgress.is_stage_unlocked(&"lichang", 1)
	var opened := await _dismiss_atlas(lv)
	lv.queue_free()
	await _pframes(3)
	_check("3", "打光第 1 段的怪 → 判过关 → 解锁第 2 段 → 自动弹出舆图",
		killed >= 2 and not before and after and opened,
		"打死 %d 只　过关前第 2 段可进=%s　过关后=%s　舆图弹出=%s" % [
			killed, str(before), str(after), str(opened)])


## 清空砺场最后一段：砺场记为已通关
##
## **不会**顺手解锁断淬渠 —— 它还没开工（stages 是空的），「下一关」不存在。
## 这不是漏了，是内容还没到（步 2 才切它）。跨副本解锁的规则本身由下一条
## 用构造数据单独盯住，所以这里「没解锁」是被证明过的行为，不是没测到
func _t4_clear_last_marks_dungeon() -> void:
	# 先把砺场开到第三段（正常玩法里是打出来的，这里直接摆好来测这一条）
	SaveManager.unlock_stage(&"lichang", 2)
	var lv := LICHANG_3.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	_kill_all(lv)
	await _pframes(CLEAR_DELAY + 8)
	var cleared := SaveManager.is_cleared(&"lichang")
	var empty_next := not GameProgress.is_dungeon_unlocked(&"duancuiqu")
	await _dismiss_atlas(lv)
	lv.queue_free()
	await _pframes(3)
	_check("4", "打光砺场第 3 段 → 砺场记为已通关；断淬渠还没开工，不会被解锁",
		cleared and empty_next,
		"砺场已通关=%s　断淬渠仍锁着=%s（它 stages 为空 = 未开工，见数据）" % [
			str(cleared), str(empty_next)])


## 跨副本解锁的规则本身：清完一个副本的最后一段 → 下一个副本的第 1 段
##
## 用**构造的两副本地图**测，不碰真实数据 —— 真实数据里断淬渠还是空的，
## 这条规则在那边看不见。但规则必须现在就硬：等步 2 填内容时才发现它
## 从来没工作过，代价就大了
func _t5_cross_dungeon_rule() -> void:
	var s_a1 := StageData.new()
	s_a1.id = &"t_a1"
	var s_a2 := StageData.new()
	s_a2.id = &"t_a2"
	var s_b1 := StageData.new()
	s_b1.id = &"t_b1"
	var a := DungeonData.new()
	a.id = &"t_a"
	var a_stages: Array[StageData] = [s_a1, s_a2]
	a.stages = a_stages
	var b := DungeonData.new()
	b.id = &"t_b"
	var b_stages: Array[StageData] = [s_b1]
	b.stages = b_stages
	var m := MapData.new()
	m.id = &"t_map"
	var ds: Array[DungeonData] = [a, b]
	m.dungeons = ds

	var mid := m.next_stage(&"t_a", 0)        # 副本内下一段
	var cross := m.next_stage(&"t_a", 1)      # 跨副本
	var tail := m.next_stage(&"t_b", 0)       # 最后一个副本的最后一段
	_check("5", "跨副本规则：清完一个副本的最后一段 → 下一个副本的第 1 段；最后一个副本之后没有下一段",
		String(mid.get("dungeon", "")) == "t_a" and int(mid.get("index", -1)) == 1 \
			and String(cross.get("dungeon", "")) == "t_b" and int(cross.get("index", -1)) == 0 \
			and tail.is_empty(),
		"副本内：%s→第 %d 段　跨副本：%s→第 %d 段　地图末尾：%s" % [
			str(mid.get("dungeon", "?")), int(mid.get("index", 0)) + 1,
			str(cross.get("dungeon", "?")), int(cross.get("index", 0)) + 1,
			"没有下一段" if tail.is_empty() else str(tail)])


## 解锁进度进存档，读档之后还在（不能只活在内存里）
func _t6_progress_survives_save() -> void:
	SaveManager.unlock_stage(&"lichang", 2)
	SaveManager.mark_cleared(&"lichang")
	# 写一份带快照的进度档（模拟暂停菜单里「保存游戏」）
	SaveManager.write_progress("res://scenes/stages/lichang_2.tscn",
		{"player": {"hp": 70, "shards": 4, "upgrade": 1}, "enemies": []})
	# 清空内存里的痕迹：重新读档
	SaveManager.load_game(1)
	SaveManager.drop_pending_restore()     # 本用例只验进度，不恢复世界
	var stages := SaveManager.unlocked_stages(&"lichang")
	var cleared := SaveManager.is_cleared(&"lichang")
	SaveManager.unlock_stage(&"lichang", 0)
	var first := GameProgress.is_stage_unlocked(&"lichang", 0)
	var second := GameProgress.is_stage_unlocked(&"lichang", 1)
	_check("6", "逐段解锁的进度真的写进了存档：读档之后段数与「已通关」都还在",
		stages == 3 and cleared and first and second,
		"读档后砺场已解锁 %d 段　已通关=%s　第 1 段可进=%s　第 2 段可进=%s" % [
			stages, str(cleared), str(first), str(second)])


## 舆图界面：未解锁的段落**看得见**（锁 + 灰字），文案不是翻译 key
func _t7_atlas_rows() -> void:
	# 故意回到「只开第 1 段」的状态 —— 三段的进度都开了之后，
	# 「未解锁」这行就看不见了，也就测不到它
	GameProgress.reset_progress()
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
	var locked_rows := 0
	for t in texts:
		if t.contains(tr("UI_ATLAS_LOCKED")):
			locked_rows += 1
	var has_first_stage := joined.contains(I18n.t(&"UI_STAGE_LABEL", [1]))
	var has_dungeons := joined.contains(tr("DUNGEON_LICHANG")) \
		and joined.contains(tr("DUNGEON_DUANCUIQU")) and joined.contains(tr("DUNGEON_LUHOU"))
	var has_not_ready := joined.contains(tr("UI_ATLAS_NOT_READY"))
	var has_back := joined.contains(tr("UI_ATLAS_BACK"))
	# 行数应当正好是：3 个副本标题 + 砺场 3 段 + 1 行回安全区。
	# 断言总数是因为「少一行」正是这个界面最典型的静默失败（漏了哪个副本就少一行）
	var right_rows := texts.size() == 7
	_check("7", "舆图四件事都不静默：锁着的段照实标锁、未开工的副本标未开放、三个副本都在、底部有回安全区",
		leaks.is_empty() and locked_rows == 2 and has_first_stage \
			and has_dungeons and has_not_ready and has_back and right_rows,
		"行数 %d（应为 7 = 3 副本标题 + 3 段 + 回安全区）　锁定行 %d（应为 2）\n              「第 1 段」写出=%s　三副本齐=%s　未开放=%s　回安全区=%s　文案泄漏: %s" % [
			texts.size(), locked_rows, str(has_first_stage), str(has_dungeons),
			str(has_not_ready), str(has_back),
			"无" if leaks.is_empty() else ", ".join(leaks)])


## 死在本关 → 重开本关（不是原地满血、也不是回城）
func _t8_death_restarts_stage() -> void:
	_restart_called = false
	var lv := LICHANG_1.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var player := lv.get_node("Player")
	# 挪到一个明显不是出生点的位置再打死 —— 原地满血的话人会被搬回出生点
	player.global_position = Vector2(520.0, 288.0)
	await _pframes(3)
	(player.get_node("Health") as Health).take_damage(9999, Vector2.ZERO, true, 1)
	var revive_frames := int(ceil(float(player.get("revive_delay")) * 60.0)) + 30
	await _pframes(revive_frames)
	var called := _restart_called
	lv.queue_free()
	await _pframes(3)
	_check("8", "死在本关 → 重开本关（不回城、也不原地满血）",
		called,
		"死亡 %d 帧后：关卡被要求重开=%s" % [revive_frames, str(called)])


## 一屏 + 地形在跳跃预算内：抬升 ≤ 60px（跳跃高度约 73px）
##
## 这条是继承来的纪律（docs/adr/0009 §9）：抬升超预算的台子**看得见但上不去**，
## 而且上不去不会报错，只会让人以为「这个跳台是装饰」
func _t9_one_screen_within_jump_budget() -> void:
	var scenes: Array[PackedScene] = [LICHANG_1, LICHANG_2, LICHANG_3]
	var widths := PackedFloat32Array()
	var worst := 0.0
	for sc in scenes:
		var lv := sc.instantiate()
		add_child(lv)
		await _pframes(3)
		_quiet(lv)
		var b: Rect2 = lv.get("bounds")
		widths.append(b.size.x)
		var w := _max_rise(lv)
		if w > worst:
			worst = w
		lv.queue_free()
		await _pframes(2)
	var one_screen := true
	for w in widths:
		if absf(w - 640.0) > 0.5:
			one_screen = false
	_check("9", "三段都是一屏（640 宽、相机不动），且全段最大抬升在跳跃高度之内",
		one_screen and worst <= 60.0,
		"三段宽 %s　最大抬升 %.0fpx（跳跃上限约 73px）" % [str(widths), worst])


## 相邻平台之间最大的一次「抬升」（像素）
func _max_rise(lv: Node) -> float:
	var rects: Array[Rect2] = []
	for c in lv.get_children():
		if not (c is StaticBody2D):
			continue
		var cs := c.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs == null or not (cs.shape is RectangleShape2D):
			continue
		var sz: Vector2 = (cs.shape as RectangleShape2D).size
		rects.append(Rect2((c as Node2D).global_position - sz * 0.5, sz))
	rects.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	var worst := 0.0
	for i in range(1, rects.size()):
		var rise: float = rects[i - 1].position.y - rects[i].position.y
		if rise > worst:
			worst = rise
	return worst
