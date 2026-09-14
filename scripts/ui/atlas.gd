extends CanvasLayer
## 舆图：三层结构（地图 → 副本 → 关卡）的选关界面。**玩家进入副本的唯一入口。**
##
## ── 两个入口，同一个界面 ──────────────────────────────────────
##   1. 安全区的**舆图台**：走近出提示 → 按 `P` 打开（术语见 docs/CONTEXT.md「舆图台」）
##   2. **清空一关之后自动打开** —— 关卡里没有舆图台，但那时玩家总得有个去处
##
## 第 2 个入口是本界面的关键设计点：过关之后玩家站在一个空关卡里，
## 按 P 没反应（不在舆图台旁）、Esc 只能回主菜单 —— 那是死路。
## 所以过关后自动把它弹出来，并且**必须选一个去处**（J 进下一段 / Esc 回安全区）。
##
## ── 打开即真暂停 ──────────────────────────────────────────────
## 操作类界面（要上下选、要决定去哪），与 B 装备背包同类：
## `process_mode = ALWAYS` + `get_tree().paused = true`，
## 并且与暂停菜单 / 背包 / 技能面板 / 对话框互相查 `is_open()` 让路。
##
## ── 布局（docs/design-conventions.md「舆图与关卡推进」）────────────
## 左边地图页签，右边该地图的副本 + 展开的关卡，一次看全，**选关即进**。
## 未解锁的关卡**不隐藏**：锁 + 灰字 —— 玩家要看得见「前面还有几关」。
## 实力可能不够的写推荐等级 / 武器强化并标红，**但不禁止进入**。

const TOWN_PATH := "res://scenes/stages/town.tscn"

const CURSOR_MARK := "▶ "
const INDENT := "   "
const ROW_HEIGHT := 18.0
const FONT_SIZE := 11

const DIM := Color(0.55, 0.53, 0.5, 1)
const NORMAL := Color(0.9, 0.88, 0.84, 1)
const BRIGHT := Color(1, 1, 1, 1)
const HEAD := Color(0.93, 0.84, 0.6, 1)
const WARN := Color(0.95, 0.52, 0.45, 1)

## 每一行是什么。kind 取值：
##   head   副本标题（不可选）
##   stage  已解锁的关卡（可选，J 进入）
##   locked 未解锁的关卡（不可选，灰 + 锁）
##   back   回安全区（可选）
var _rows: Array[Dictionary] = []
var _cursor := 0
## 这一关刚打完弹出来的？true = 必须选一个去处，Esc 变成「回安全区」
var _must_choose := false

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Panel/Title
@onready var _tabs: VBoxContainer = $Root/Panel/Tabs
@onready var _list: VBoxContainer = $Root/Panel/Rows
@onready var _hint: Label = $Root/Panel/Hint


func _ready() -> void:
	_root.visible = false
	if not GameSettings.language_changed.is_connected(_on_language_changed):
		GameSettings.language_changed.connect(_on_language_changed)


## 参数必须留着：Godot 按参数个数严格匹配信号连接，少一个会「连上了但一调用就报错」，
## 界面静默不刷新（M1 的语言切换用例抓到过这个家族）
func _on_language_changed(_locale: String = "") -> void:
	if _root.visible:
		refresh()


func is_open() -> bool:
	return _root.visible


# ── 入口 ───────────────────────────────────────────────────────

## 舆图台调用：正常打开，Esc = 关闭
func open() -> void:
	_must_choose = false
	_show({})


## 清空一关之后自动打开：光标落在**新解锁的那一段**上，Esc = 回安全区。
## nxt 为空（整张地图打完）时落在第一行
func open_after_clear(nxt: Dictionary) -> void:
	_must_choose = true
	_show(nxt)


func _show(nxt: Dictionary) -> void:
	_build()
	_cursor = _row_of(nxt)
	_root.visible = true
	get_tree().paused = true
	refresh()


func close() -> void:
	_root.visible = false
	_must_choose = false
	get_tree().paused = false


# ── 输入 ───────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		# 「打完这一关」弹出来的舆图不给关掉 —— 关掉就是站在一个空关卡里发呆。
		# 这时 Esc 是「回安全区」，另一条去处。**不静默**：底部提示写着这一条
		if _must_choose:
			_go_home()
		else:
			close()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				_move(-1)
			KEY_DOWN, KEY_S:
				_move(1)
			KEY_J, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate()


## 光标只在可选行之间走 —— 未解锁的关卡与副本标题只是「看得见的路标」，
## 落在上面会让玩家以为选了它就能进
func _move(dir: int) -> void:
	var n := _rows.size()
	if n == 0:
		return
	var i := _cursor
	for _step in n:
		i = wrapi(i + dir, 0, n)
		if bool(_rows[i].get("sel", false)):
			_cursor = i
			refresh()
			return


func _activate() -> void:
	if _cursor < 0 or _cursor >= _rows.size():
		return
	var r := _rows[_cursor]
	match str(r.get("kind", "")):
		"stage":
			_enter_stage(r["dungeon"], int(r["index"]))
		"back":
			_go_home()


func _enter_stage(dungeon_id: StringName, index: int) -> void:
	var m := GameProgress.map()
	var st := m.find_stage(dungeon_id, index) if m != null else null
	if st == null or st.scene_path.is_empty():
		push_error("舆图：第 %d 段没有场景路径" % (index + 1))
		return
	if not ResourceLoader.exists(st.scene_path):
		push_error("舆图：关卡场景不存在 %s" % st.scene_path)
		return
	_leave_to(st.scene_path)


func _go_home() -> void:
	_leave_to(TOWN_PATH)


## 离开舆图去别的场景。**先解暂停再切场景** —— `paused` 是挂在场景树上的，
## 不解开的话新场景一进来就是暂停的，看起来像卡死
func _leave_to(path: String) -> void:
	get_tree().paused = false
	_root.visible = false
	_must_choose = false
	SaveManager.write_progress(path, {})   # 换场景 = 世界重置，快照不能跨场景复用
	get_tree().change_scene_to_file(path)


# ── 构建与刷新 ─────────────────────────────────────────────────

## 按三层结构数据建行。内容不会在界面开着的时候变（关卡表是静态数据），
## 所以只在打开时建一次，之后刷新只改文字
func _build() -> void:
	for c in _list.get_children():
		c.queue_free()
	for c in _tabs.get_children():
		c.queue_free()
	_rows.clear()

	var m := GameProgress.map()
	if m == null:
		return
	_tabs.add_child(_make_label(tr(m.name_key), HEAD, true))
	for d in m.dungeons:
		if d == null:
			continue
		_rows.append({"kind": "head", "dungeon": d.id})
		for i in d.stages.size():
			var unlocked := GameProgress.is_stage_unlocked(d.id, i)
			_rows.append({
				"kind": "stage" if unlocked else "locked",
				"dungeon": d.id,
				"index": i,
				"sel": unlocked,
			})
	_rows.append({"kind": "back", "sel": true})
	for r in _rows:
		_list.add_child(_make_label("", NORMAL, bool(r.get("sel", false))))


## 一行 = 一个 Label。**代码建而不是写进 tscn**：行数由数据决定，
## 手写 tscn 的嵌套 parent 路径写错过三次，能省的静态节点就省掉
func _make_label(text: String, color: Color, selectable: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	lbl.add_theme_color_override("font_color", color)
	lbl.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 可选行给一点亮度差：不看光标标记也能看出「这几行能选」
	lbl.modulate = NORMAL if selectable else Color(1, 1, 1, 0.75)
	return lbl


func refresh() -> void:
	_title.text = tr("UI_ATLAS_TITLE")
	_hint.text = tr("UI_ATLAS_HINT_CLEAR") if _must_choose else tr("UI_ATLAS_HINT")
	var m := GameProgress.map()
	if m == null:
		return
	var kids := _list.get_children()
	for i in mini(_rows.size(), kids.size()):
		var r := _rows[i]
		var lbl := kids[i] as Label
		if lbl == null:
			continue
		var sel := i == _cursor
		lbl.text = _row_text(r, sel)
		lbl.modulate = _row_color(r, sel)


func _row_text(r: Dictionary, sel: bool) -> String:
	var mark := CURSOR_MARK if sel else INDENT
	match str(r.get("kind", "")):
		"head":
			var m := GameProgress.map()
			var d := m.find_dungeon(r["dungeon"]) if m != null else null
			if d == null:
				return "?"
			return "%s　%s" % [tr(d.name_key), _dungeon_state(d)]
		"stage":
			var m2 := GameProgress.map()
			var st := m2.find_stage(r["dungeon"], int(r["index"])) if m2 != null else null
			var rec := ""
			if st != null:
				rec = tr("UI_ATLAS_REC") % [st.rec_level, st.rec_weapon]
			return "%s%s%s　%s" % [mark, INDENT, tr("UI_STAGE_LABEL") % (int(r["index"]) + 1), rec]
		"locked":
			return "%s%s%s　%s" % [INDENT, INDENT,
				tr("UI_STAGE_LABEL") % (int(r["index"]) + 1), tr("UI_ATLAS_LOCKED")]
		"back":
			return "%s%s" % [mark, tr("UI_ATLAS_BACK")]
	return ""


## 副本的状态后缀。**不能静默**：没开工的副本必须写出来，
## 否则玩家看到「断淬渠」下面空空如也，分不清是没做还是没开
func _dungeon_state(d: DungeonData) -> String:
	if d.stages.is_empty():
		return tr("UI_ATLAS_NOT_READY")
	if SaveManager.is_cleared(d.id):
		return tr("UI_ATLAS_CLEARED")
	return ""


func _row_color(r: Dictionary, sel: bool) -> Color:
	if sel:
		return BRIGHT
	match str(r.get("kind", "")):
		"head":
			return HEAD
		"locked":
			return DIM
		"stage":
			# 推荐实力不够 → 标红，但**照样能进**（软压力，不是门票）
			var m := GameProgress.map()
			var st := m.find_stage(r["dungeon"], int(r["index"])) if m != null else null
			if st != null and _too_weak(st):
				return WARN
			return NORMAL
	return NORMAL


## 玩家现在的等级 / 武器强化够不够这一关的推荐值。**只用来上色**，
## 任何地方都不拿它拦人 —— 硬门槛会把「刷」变成义务（docs/adr/0009 §5）
func _too_weak(st: StageData) -> bool:
	if PlayerState.level < st.rec_level:
		return true
	return PlayerState.upgrade_level < st.rec_weapon


## 某个关卡坐标在行表里的下标。给不到就退回第一行可选行
func _row_of(nxt: Dictionary) -> int:
	if not nxt.is_empty():
		for i in _rows.size():
			var r := _rows[i]
			if str(r.get("kind", "")) == "stage" \
					and String(r.get("dungeon", "")) == String(nxt.get("dungeon", "")) \
					and int(r.get("index", -1)) == int(nxt.get("index", -2)):
				return i
	for i in _rows.size():
		if bool(_rows[i].get("sel", false)):
			return i
	return 0


## 供断言用：界面上的全部行文本
func row_texts() -> Array[String]:
	var out: Array[String] = []
	for r in _rows:
		out.append(_row_text(r, false))
	return out
