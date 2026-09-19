extends CanvasLayer
## 舆图：三层结构（地图 → 副本 → 关卡）的选关界面。**玩家进入副本的唯一入口。**
##
## ── 两个入口，同一个界面 ──────────────────────────────────────
##   1. 安全区的**舆图台**：走近出提示 → 按 `P` 打开（术语见 docs/CONTEXT.md「舆图台」）
##   2. **通关一个副本之后自动打开** —— 副本里没有舆图台，但那时玩家总得有个去处
##
## ── 粒度（2026-09-14 重定后**只有副本这一层是可选的**）──────────
## 第一版把副本展开成一串「一屏关卡」让玩家挑，神玩完的反馈是「点进点出频繁」。
## 现在**副本就是一条 3~4 屏的路，进一次从头打到尾**（推进由关卡根节点负责），
## 所以舆图上**一行一个副本**，不再展开屏 —— 屏是副本内部的事，不是玩家的选择题。
##
## ── 打开即真暂停 ──────────────────────────────────────────────
## 操作类界面（要上下选、要决定去哪），与 B 装备背包同类：
## `process_mode = ALWAYS` + `get_tree().paused = true`，
## 并且与暂停菜单 / 背包 / 技能面板 / 对话框互相查 `is_open()` 让路。
##
## ── 布局（docs/design-conventions.md「舆图与关卡推进」）────────────
## 左边地图页签，右边该地图的副本列表，一次看全，**选副本即进**。
## 没开的副本**不隐藏**：锁 + 灰字 —— 玩家要看得见「前面还有什么」。
## 实力可能不够的写推荐等级 / 武器强化并标红，**但不禁止进入**。

const TOWN_PATH := "res://scenes/stages/town.tscn"

const CURSOR_MARK := "▶ "
const INDENT := "   "
## 行高与字号。**尺寸预算的产物**：3 个副本 + 一行回安全区 = 4 行，
## 将来副本变多（每张地图 5~6 个）也还装得下 640×360
const ROW_HEIGHT := 17.0
const FONT_SIZE := 10
## 面板高度按行数自适应（见 _fit_panel）
const HEAD_H := 32.0
const FOOT_H := 30.0
const PANEL_W := 560.0
const PANEL_MIN_H := 110.0
## 屏幕 360 高，上下各留 12 的边距
const PANEL_MAX_H := 336.0

const DIM := Color(0.55, 0.53, 0.5, 1)
const NORMAL := Color(0.9, 0.88, 0.84, 1)
const BRIGHT := Color(1, 1, 1, 1)
const GOLD := Color(0.93, 0.84, 0.6, 1)
const WARN := Color(0.95, 0.52, 0.45, 1)

## 每一行是什么。kind 取值：
##   dungeon 开了的副本（可选，J 进入）
##   locked  还没开（前一个副本没通关）
##   shut    还没开工（没有场景）
##   back    回安全区（可选）
var _rows: Array[Dictionary] = []
var _cursor := 0
## 当前看的是第几张地图。**←→ 切换**（页签左右并排，切地图只换右列内容）
var _map_idx := 0
## 这一份是通关之后弹出来的？true = 必须选一个去处，Esc 变成「回安全区」
var _must_choose := false

@onready var _root: Control = $Root
@onready var _panel: Panel = $Root/Panel
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
	_show(null)


## 通关一个副本之后自动打开：光标落在**因此解锁的下一个副本**上，Esc = 回安全区。
## next_d 为 null（整张地图打完了）时落在第一行
func open_after_clear(next_d: DungeonData) -> void:
	_must_choose = true
	_show(next_d)


func _show(next_d: DungeonData) -> void:
	_build()
	_fit_panel()
	_cursor = _row_of(next_d)
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
		# 「通关了」弹出来的舆图不给关掉 —— 关掉就是站在一个打空了的副本里发呆。
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
			KEY_LEFT, KEY_A:
				_switch_map(-1)
			KEY_RIGHT, KEY_D:
				_switch_map(1)
			KEY_J, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate()


## 光标只在可选行之间走 —— 没开 / 没开工的副本只是「看得见的路标」，
## 落在上面会让玩家以为选了它就能进
## 换一张地图看：重建右列，光标落在新地图第一行可选项。
## 只有一张地图时什么都不做（不给玩家一个没有第二项的切换）
func _switch_map(delta: int) -> void:
	var ms := GameProgress.maps()
	if ms.size() < 2:
		return
	_map_idx = wrapi(_map_idx + delta, 0, ms.size())
	_build()
	_fit_panel()
	_cursor = _row_of(null)
	refresh()


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
		"dungeon":
			_enter_dungeon(r["dungeon"])
		"back":
			_go_home()


## 鼠标点第 i 个地图页签 / 第 i 行副本。只认左键按下；Label 自己收点击
##（_make_label 默认 IGNORE，建行时改成 STOP 了），点击不会漏到下面
func _on_tab_gui_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_click_tab(i)
		get_viewport().set_input_as_handled()


func _on_atlas_row_gui_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_click_atlas_row(i)
		get_viewport().set_input_as_handled()


## 点页签 i → 换到那张地图（**单击即生效**：换地图只是换个看法，不带走任何东西）。
## `_switch_map` 收的是**增量**不是目标下标，所以要减掉当前值 ——
##「同一张地图」直接忽略：按了等于没按的操作不该有反馈
func _click_tab(i: int) -> void:
	var ms := GameProgress.maps()
	if i < 0 or i >= ms.size() or i == _map_idx:
		return
	_switch_map(i - _map_idx)


## 点副本行 i → 光标移过去 → **单击即进**（进副本是导航，不是消费，走「便宜」档）。
## **不可选的行（没开 / 没开工）整行忽略** —— 键盘光标本来就到不了那里，
## 让它点得进去就等于用鼠标开了一道后门
func _click_atlas_row(i: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	if not bool(_rows[i].get("sel", false)):
		return
	_cursor = i
	_activate()


func _enter_dungeon(id: StringName) -> void:
	var d := GameProgress.dungeon(id)
	if d == null or not d.is_ready():
		push_error("舆图：副本 %s 没有可进的场景" % str(id))
		return
	if not ResourceLoader.exists(d.scene_path):
		push_error("舆图：副本场景不存在 %s" % d.scene_path)
		return
	_leave_to(d.scene_path)


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

## 按地图数据建行。内容不会在界面开着的时候变，所以只在打开时建一次，
## 之后刷新只改文字
func _build() -> void:
	# **必须 remove_child 之后再 queue_free**：queue_free 是延迟的，
		
	# 只标记不摘除 —— 紧接着 add_child 的新节点会排在旧节点后面，
	# 于是 refresh() 里 get_children()[i] 命中的是「正要被释放的旧 Label」，
	# 文字全填到旧节点上，界面一片空白（切地图时才暴露，因为那时会第二次 _build）
	for host in [_list, _tabs]:
		for c in host.get_children():
			host.remove_child(c)
			c.queue_free()
	_rows.clear()

	var ms := GameProgress.maps()
	if ms.is_empty():
		return
	_map_idx = clampi(_map_idx, 0, ms.size() - 1)
	# 页签列出**全部**地图，当前那张金字、其余压暗 —— 玩家要看得见「后面还有一章」。
	# 鼠标信号**必须在这里连**：页签和下面的副本行都是本函数重建出来的
	#（remove_child + queue_free 再来一遍），只在 _ready 连一次的话第二次就没了
	for i in ms.size():
		var cur := i == _map_idx
		var tab := _make_label(tr(ms[i].name_key), GOLD if cur else DIM, cur)
		tab.mouse_filter = Control.MOUSE_FILTER_STOP
		tab.gui_input.connect(_on_tab_gui_input.bind(i))
		_tabs.add_child(tab)
	var m := ms[_map_idx]
	if m == null:
		return
	for d in m.dungeons:
		if d == null:
			continue
		var kind := "shut"
		var selectable := false
		if d.is_ready():
			if GameProgress.is_dungeon_unlocked(d.id):
				kind = "dungeon"
				selectable = true
			else:
				kind = "locked"
		_rows.append({"kind": kind, "dungeon": d.id, "sel": selectable})
	_rows.append({"kind": "back", "sel": true})
	for i in _rows.size():
		var lbl := _make_label("", NORMAL, bool(_rows[i].get("sel", false)))
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		lbl.gui_input.connect(_on_atlas_row_gui_input.bind(i))
		_list.add_child(lbl)


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


## 面板高度按行数自适应：砺场切片时只有 4 行（矮一点更好看），
## 副本多了会长高，但仍然要一屏装得下 —— 规范里写的是「一次看全」，
## 所以宁可面板贴着屏幕上下边，也不给列表加滚动
func _fit_panel() -> void:
	var rows_h := float(maxi(_rows.size(), 1)) * ROW_HEIGHT
	var h := clampf(HEAD_H + rows_h + FOOT_H, PANEL_MIN_H, PANEL_MAX_H)
	_panel.offset_left = -PANEL_W * 0.5
	_panel.offset_right = PANEL_W * 0.5
	_panel.offset_top = -h * 0.5
	_panel.offset_bottom = h * 0.5


func refresh() -> void:
	_title.text = tr("UI_ATLAS_TITLE")
	_hint.text = tr("UI_ATLAS_HINT_CLEAR") if _must_choose else tr("UI_ATLAS_HINT")
	if GameProgress.maps().is_empty():
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
	# 「回安全区」那一行没有副本 id —— 先判它，别去取不存在的键
	if str(r.get("kind", "")) == "back":
		return "%s%s" % [mark, tr("UI_ATLAS_BACK")]
	var d := GameProgress.dungeon(r["dungeon"])
	if d == null:
		return "?"
	match str(r.get("kind", "")):
		"dungeon":
			var parts := PackedStringArray()
			parts.append(tr(d.name_key))
			parts.append(I18n.t(&"UI_DUNGEON_SCREENS", [d.screen_count]))
			if SaveManager.is_cleared(d.id):
				parts.append(tr("UI_ATLAS_CLEARED"))
			parts.append(I18n.t(&"UI_ATLAS_REC", [d.rec_level, d.rec_weapon]))
			return "%s%s" % [mark, "　".join(parts)]
		"locked":
			return "%s%s　%s" % [INDENT, tr(d.name_key), tr("UI_ATLAS_LOCKED")]
		"shut":
			return "%s%s　%s" % [INDENT, tr(d.name_key), tr("UI_ATLAS_NOT_READY")]
	return ""


func _row_color(r: Dictionary, sel: bool) -> Color:
	if sel:
		return BRIGHT
	if str(r.get("kind", "")) == "back":
		return NORMAL
	var d := GameProgress.dungeon(r["dungeon"])
	match str(r.get("kind", "")):
		"dungeon":
			# 已通关 → 金字；推荐实力不够 → 标红，但**照样能进**（软压力，不是门票）
			if d != null and SaveManager.is_cleared(d.id):
				return GOLD
			if d != null and _too_weak(d):
				return WARN
			return NORMAL
		"locked", "shut":
			return DIM
	return NORMAL


## 玩家现在的等级 / 武器强化够不够这个副本的推荐值。**只用来上色**，
## 任何地方都不拿它拦人 —— 硬门槛会把「刷」变成义务（docs/adr/0009 §5）
##
## 强化改成逐件之后（2026-09-14），这里比的是**手里那把武器**练到几级。
## 没拿武器时算 0 级 —— 空手进副本本来就该标红
func _too_weak(d: DungeonData) -> bool:
	if PlayerState.level < d.rec_level:
		return true
	var w := PlayerState.equipped_uid(&"weapon")
	return PlayerState.forge_level(w) < d.rec_weapon


## 某个副本在行表里的下标。给不到就退回第一行可选行
func _row_of(next_d: DungeonData) -> int:
	if next_d != null:
		for i in _rows.size():
			if String(_rows[i].get("dungeon", "")) == String(next_d.id):
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
