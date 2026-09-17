extends Node
## 《百炼》M4 自动验收：**第二章「剑冢」**（残剑林 3 屏 / 锈蚀甬道 4 屏 / 冢心 5 屏）。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m17.tscn
##
## 第二章落地时新做进去的三件事，各盯一条：
##
##   · **多地图**：GameProgress 从写死一张地图变成**扫目录**（加一章不改代码）。
##     这条同时是 ResDir 的守门人 —— 导出包里 `map_*.tres` 会变成 `map_*.tres.remap`，
##     直接按 `.tres` 匹配会在导出后一张地图都找不到（见 scripts/core/res_dir.gd）
##   · **跨地图解锁**：剑冢第一个副本的前一个是**淬火岭最后一个副本**。
##     不这么串的话每张地图的第一个副本都会「天生就开」，第二章一开局就能跳关
##   · **三个新 Boss**：复制场景忘改 data 是这类活儿最容易静默漏掉的
##     （场景长得对、数值还是原来那只）
##
## 副本内部形状（屏/批/四步法/锯齿/地形预算）沿用 m13 那套逻辑，对三个新副本各跑一遍 ——
## **新副本进不了场，上面三条都无从谈起**。

const NEW_DUNGEONS := [
	{"id": "canjianlin", "node": "Canjianlin", "path": "res://scenes/stages/canjianlin.tscn", "screens": 3},
	{"id": "xiushi", "node": "Xiushi", "path": "res://scenes/stages/xiushi.tscn", "screens": 4},
	{"id": "zhongxin", "node": "Zhongxin", "path": "res://scenes/stages/zhongxin.tscn", "screens": 5},
]
## 每关的 Boss，以及它该用的是哪个 EnemyData.id
const BOSS_OF := {"canjianlin": "boss_canjian", "xiushi": "boss_xiushi", "zhongxin": "boss_zhongxin"}
const SCREEN_W := 960.0
## 相邻台面的抬升上限（超了就是「看得见但上不去」，而且不报错）
const MAX_RISE := 60.0
## 怪可以超出所属屏的范围 —— Boss 体型大、巡逻会走两步
const SCREEN_SLACK := 80.0

var _pass := 0
var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》剑冢（第二章）自动验收 ═══")

	_t1_multi_map()
	_t2_global_sequence()
	await _t3_cross_map_unlock()
	_t4_boss_data_matches()

	for d in NEW_DUNGEONS:
		await _check_dungeon(d)

	print("")
	if _fail == 0:
		print("═══ %d 通过 ／ 0 失败 ═══" % _pass)
	else:
		print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().quit()


# ── 工具 ──────────────────────────────────────────────────────

func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-9s %s\n              %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-9s %s\n              %s" % [id, desc, detail])


func _pframes(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## 把怪停掉再量尺寸 —— 怪会追人，量地形时它们到处跑会让断言抖
func _quiet(lv: Node) -> void:
	for e in lv.find_children("*", "CharacterBody2D", true, false):
		if e.has_method("is_alive") and e.has_method("set_dormant"):
			e.set("ai_enabled", false)


func _screens(lv: Node) -> Array[Node]:
	var out: Array[Node] = []
	for s in lv.get_children():
		if s.is_in_group("screen"):
			out.append(s)
	return out


func _waves(screen: Node) -> Array[Node]:
	var out: Array[Node] = []
	for w in screen.get_children():
		if w.is_in_group("wave"):
			out.append(w)
	return out


func _mobs(wave: Node) -> Array[Node]:
	var out: Array[Node] = []
	for m in wave.get_children():
		if m.has_method("is_alive"):
			out.append(m)
	return out


func _mob_id(m: Node) -> String:
	var d = m.get("data")
	return "" if d == null else str(d.id)


## 相邻台面的最大抬升（只算横着的台面；竖着的挡墙不是给人踩的）
func _max_rise(lv: Node) -> float:
	var rects: Array[Rect2] = []
	for c in lv.get_children():
		if not (c is StaticBody2D):
			continue
		var cs := c.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs == null or not (cs.shape is RectangleShape2D):
			continue
		var sh := cs.shape as RectangleShape2D
		if sh.size.x <= sh.size.y:
			continue
		rects.append(Rect2((c as Node2D).global_position - sh.size * 0.5, sh.size))
	rects.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	var worst := 0.0
	for i in range(1, rects.size()):
		var rise: float = rects[i - 1].position.y - rects[i].position.y
		if rise > worst:
			worst = rise
	return worst


# ── 1. 多地图 ─────────────────────────────────────────────────

func _t1_multi_map() -> void:
	var ms := GameProgress.maps()
	var ids := PackedStringArray()
	for m in ms:
		ids.append(str(m.id))
	_check("1a", "扫目录扫出两张地图", ms.size() == 2,
		"maps() = [%s]（期望 quench_ridge + sword_tomb）" % ", ".join(ids))
	var sorted_ok := ms.size() == 2 and str(ms[0].id) == "quench_ridge" and str(ms[1].id) == "sword_tomb"
	_check("1b", "页签顺序稳定（按文件名排）", sorted_ok,
		"第一张 %s / 第二张 %s" % [str(ms[0].id) if ms.size() > 0 else "-",
			str(ms[1].id) if ms.size() > 1 else "-"])
	# 剑冢的三个副本都在数据里、且都指到真场景（scene_path 填错 = 点进去一片黑）
	var tomb: MapData = null
	for m in ms:
		if str(m.id) == "sword_tomb":
			tomb = m
	var ok := tomb != null and tomb.dungeons.size() == 3
	var missing := PackedStringArray()
	if tomb != null:
		for d in tomb.dungeons:
			if d != null and not ResourceLoader.exists(d.scene_path):
				missing.append(str(d.id))
	_check("1c", "剑冢三副本齐全且场景都存在", ok and missing.is_empty(),
		"副本 %d 个 / 场景缺失 %s" % [tomb.dungeons.size() if tomb else 0,
			"无" if missing.is_empty() else ", ".join(missing)])


# ── 2. 全局副本序列 ───────────────────────────────────────────

func _t2_global_sequence() -> void:
	var seq := GameProgress.sequence()
	var ids := PackedStringArray()
	for d in seq:
		ids.append(str(d.id))
	var want := ["lichang", "duancuiqu", "luhou", "canjianlin", "xiushi", "zhongxin"]
	var ok := seq.size() == want.size()
	if ok:
		for i in want.size():
			if str(seq[i].id) != want[i]:
				ok = false
	_check("2a", "全局副本序列 = 两章首尾相连", ok,
		"实测 [%s]（期望 %s）" % [", ".join(ids), " → ".join(want)])


# ── 3. 跨地图解锁 ─────────────────────────────────────────────

func _t3_cross_map_unlock() -> void:
	# 存一份真实存档，测完还回去（这是玩家正在玩的那份）
	var path := SaveManager.slot_path(SaveManager.current_slot)
	var had := FileAccess.file_exists(path)
	var before := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()

	GameProgress.reset_progress()
	_check("3a", "开局：残剑林锁着（炉喉没通）",
		not GameProgress.is_dungeon_unlocked(&"canjianlin"),
		"跨地图的第一个副本**不该**天生就开")

	GameProgress.on_dungeon_cleared(&"luhou")
	_check("3b", "通关炉喉 → 残剑林解锁",
		GameProgress.is_dungeon_unlocked(&"canjianlin"),
		"跨地图解锁走的就是全局序列里的「上一个」")

	_check("3c", "锈蚀甬道仍锁着（残剑林没通）",
		not GameProgress.is_dungeon_unlocked(&"xiushi"),
		"同一张地图内部逐关解锁照旧")

	# 整章打完：on_dungeon_cleared 返回的下一个应该是 null（没有下一关了）
	var last := GameProgress.on_dungeon_cleared(&"zhongxin")
	_check("3d", "打完冢心没有下一个副本", last == null,
		"返回 %s（期望 null）" % (str(last.id) if last != null else "null"))

	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(before)
			f.close()
	GameProgress.reset_progress()


# ── 4. 三个新 Boss 的 data ────────────────────────────────────

func _t4_boss_data_matches() -> void:
	for did in BOSS_OF:
		var bid: String = BOSS_OF[did]
		var boss: Node = load("res://scenes/enemies/%s.tscn" % bid).instantiate()
		var data = boss.get("data")
		var actual := "" if data == null else str(data.id)
		var hp := 0
		if data != null:
			hp = int(data.max_hp)
		boss.free()
		_check("4-" + bid, "%s 场景的 data 指向自己" % bid, actual == bid,
			"data.id = %s（期望 %s）/ HP %d" % [actual, bid, hp])


# ── 5~9. 逐副本：形状 / 地形 / 锯齿 / Boss / 坐标 / 旧机制 ─────

func _check_dungeon(d: Dictionary) -> void:
	var did: String = d["id"]
	var lv: Node = load(d["path"]).instantiate()
	add_child(lv)
	await _pframes(8)
	_quiet(lv)

	var scr := _screens(lv)
	var want_screens := int(d["screens"])
	var wave_counts := PackedStringArray()
	var waves_ok := true
	for s in scr:
		var ws := _waves(s)
		wave_counts.append(str(ws.size()))
		if ws.size() != 3:
			waves_ok = false
	_check("5-" + did, "%s 屏数与批数" % did, scr.size() == want_screens and waves_ok,
		"屏 %d（期望 %d）/ 每屏批数 [%s]（期望全 3）" % [scr.size(), want_screens, ", ".join(wave_counts)])

	var rise := _max_rise(lv)
	_check("6-" + did, "%s 地形抬升在预算内" % did, rise <= MAX_RISE,
		"最大抬升 %.0f（上限 %.0f）" % [rise, MAX_RISE])

	var breath := 0
	for s in scr:
		for w in _waves(s):
			if _mobs(w).size() <= 2:
				breath += 1
	_check("7-" + did, "%s 有喘息点（锯齿）" % did, breath >= 1,
		"≤2 只的批次 %d 处（至少 1 处）" % breath)

	var want_boss: String = BOSS_OF[did]
	var last_ids := PackedStringArray()
	var boss_ok := false
	if not scr.is_empty():
		var ws := _waves(scr[scr.size() - 1])
		if not ws.is_empty():
			for m in _mobs(ws[ws.size() - 1]):
				last_ids.append(_mob_id(m))
				if _mob_id(m) == want_boss:
					boss_ok = true
	_check("8-" + did, "%s Boss 在最后一屏最后一波" % did, boss_ok,
		"最后一波：[%s]（期望含 %s）" % [", ".join(last_ids), want_boss])

	var stray := 0
	for i in scr.size():
		var x0 := i * SCREEN_W
		for w in _waves(scr[i]):
			for m in _mobs(w):
				var gx: float = (m as Node2D).global_position.x
				if gx < x0 - SCREEN_SLACK or gx > x0 + SCREEN_W + SCREEN_SLACK:
					stray += 1
	_check("9-" + did, "%s 怪都在自己那一屏里" % did, stray == 0,
		"跑到别屏的怪 %d 只" % stray)

	var old_mech := PackedStringArray()
	for n in lv.find_children("*", "", true, false):
		var nm := String(n.name).to_lower()
		if nm.begins_with("portal") or nm.begins_with("checkpoint"):
			old_mech.append(String(n.name))
	_check("10-" + did, "%s 没有门封印 / 复活点" % did, old_mech.is_empty(),
		"找到：%s" % ("无" if old_mech.is_empty() else ", ".join(old_mech)))

	var respawn := 0
	for s in scr:
		for w in _waves(s):
			for m in _mobs(w):
				var md = m.get("data")
				if md != null and float(md.revive_delay) > 0.0:
					respawn += 1
	_check("11-" + did, "%s 小怪不重生" % did, respawn == 0,
		"revive_delay > 0 的怪 %d 只" % respawn)

	lv.queue_free()
	await _pframes(3)
