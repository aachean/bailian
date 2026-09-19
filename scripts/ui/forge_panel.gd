extends CanvasLayer
## 铁匠铺：**逐件**强化。站在铁砧上按 J 打开。
##
## ── 为什么不是「按 J 强化手里的武器」────────────────────────────
## 强化上限绑品质（设计原则 5.2）之后，「练哪一件」变成了玩家的决定：
## 过渡装练到白装的上限就该停手，把精铁留给后面那件好装备。
## 界面不给选择权的话，这条原则就只是个后台数字，玩家根本参与不进来。
##
## ── 列表里放什么 ──────────────────────────────────────────────
## 已装备的 4 件在前（最常见的强化对象），背包里的在后。
## 顺序由 PlayerState.forgeable_uids() 定，**稳定** —— 强化成功会让属性变化、
## 界面重刷，光标要是跟着列表重排，玩家按一次 J 光标就跳到别处去了。
##
## ── 与其它模态界面同一套约定 ──────────────────────────────────
## 挂在玩家节点下，`process_mode = ALWAYS` + `get_tree().paused = true`，
## 打开时先把 HUD 的面板让开，自己开着的时候别人不开（互查 is_open）。

## 一次显示几行（多出来的靠光标滚动）
const ROWS := 8
const CURSOR_MARK := "▶ "
const INDENT := "   "
const ROW_HEIGHT := 18.0
const ICON_SIZE := 16.0
const FONT_SIZE := 11

const DIM := Color(0.55, 0.53, 0.5, 1)
const NORMAL := Color(0.9, 0.88, 0.84, 1)
const GOLD := Color(0.93, 0.84, 0.6, 1)
const WARN := Color(0.95, 0.52, 0.45, 1)

var _cursor := 0
var _rows: Array[HBoxContainer] = []
## 页签：0 = 强化 / 1 = 打造。回收闭环（批 6）的两半都从铁匠铺进 ——
## 一个面板两个动作，比两个面板少一次「走近一个台子只为一件事」
var _page := 0
## 上一次操作的结果（强化成功 / 精铁不够 / 已到顶）。**不静默**：
## 按了键什么也没发生，玩家分不清是「没反应」还是「条件不满足」
var _msg := ""
var _msg_color := DIM

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Panel/Title
@onready var _status: Label = $Root/Panel/Status
@onready var _list: VBoxContainer = $Root/Panel/Rows
@onready var _hint: Label = $Root/Panel/Hint


func _ready() -> void:
	_root.visible = false
	_build_rows()
	if not PlayerState.equipment_changed.is_connected(_on_equipment_changed):
		PlayerState.equipment_changed.connect(_on_equipment_changed)
	if not GameSettings.language_changed.is_connected(_on_language_changed):
		GameSettings.language_changed.connect(_on_language_changed)


func _on_equipment_changed() -> void:
	if _root.visible:
		refresh()


## 参数必须留着：Godot 按参数个数严格匹配信号连接（少一个会在 emit 时静默报错）
func _on_language_changed(_locale: String = "") -> void:
	if _root.visible:
		refresh()


func is_open() -> bool:
	return _root.visible


# ── 入口 ───────────────────────────────────────────────────────

## 铁砧入口：**只强化页**（ADR-0030：铁砧≠锻造台，一座台子一个功能，不再 Tab 跨越）
func open() -> void:
	_page = 0
	_cursor = 0
	_msg = ""
	# 顺序照 death_menu：**先让路、再暂停**。反过来的话，让路过程中任何一句
	# 解除暂停的代码都会把刚设的暂停抹掉（死过一次的坑，见 hud.close_all_panels）
	var hud := _hud()
	if hud != null and hud.has_method("close_all_panels"):
		hud.call("close_all_panels")
	_root.visible = true
	get_tree().paused = true
	refresh()


## 锻造台入口：**只打造页**（ADR-0030）。两个入口共用同一个面板场景，
## 但各自锁死自己那一页 —— Tab 跨越已删，铁砧练不了、锻造台打造不了对方的活
func open_craft() -> void:
	open()          # 复用开面板的通用流程（让路 + 暂停）
	_page = 1       # 再锁到打造页（open() 里锁的是 0）
	_cursor = 0
	refresh()


func close() -> void:
	_root.visible = false
	_msg = ""
	get_tree().paused = false


## 当前光标选中的装备 uid（列表为空时是空串）
func selected_uid() -> String:
	var list := PlayerState.forgeable_uids()
	if _cursor < 0 or _cursor >= list.size():
		return ""
	return str(list[_cursor])


# ── 输入 ───────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				_move(-1)
			KEY_DOWN, KEY_S:
				_move(1)
			KEY_J, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if _page == 0:
					_forge_at_cursor()
				else:
					_craft_at_cursor()
			KEY_K:
				if _page == 0:
					_disassemble_at_cursor()
		get_viewport().set_input_as_handled()


func _move(dir: int) -> void:
	var n := _list_len()
	if n <= 0:
		return
	_cursor = wrapi(_cursor + dir, 0, n)
	_msg = ""
	refresh()


func _list_len() -> int:
	return PlayerState.forgeable_uids().size() if _page == 0 else _craft_paths().size()


## 强化光标那件。三种结果都要说出来（成功 / 到顶 / 精铁不够）
func _forge_at_cursor() -> void:
	var uid := selected_uid()
	if uid.is_empty():
		return
	if PlayerState.forge_is_maxed(uid):
		_msg = tr("UI_FORGE_MAXED")
		_msg_color = DIM
		refresh()
		return
	var cost := PlayerState.forge_cost(uid)
	if PlayerState.shards < cost:
		_msg = I18n.t(&"UI_FORGE_POOR", [cost])
		_msg_color = WARN
		refresh()
		return
	PlayerState.forge_once(uid)
	_msg = I18n.t(&"UI_FORGE_OK", [PlayerState.forge_level(uid)])
	_msg_color = GOLD
	refresh()


## 分解光标那件（K）。回收闭环的「拆」半边 —— 与强化同一个列表、同一套光标。
## **穿在身上的不收**（与出售同规矩）：先卸下再来，说出来而不是静默失败
func _disassemble_at_cursor() -> void:
	var uid := selected_uid()
	if uid.is_empty():
		return
	if not PlayerState.bag.has(uid):
		_msg = tr("UI_FORGE_DISMANTLE_WORN")
		_msg_color = WARN
		refresh()
		return
	var yld := PlayerState.disassemble(uid)
	if yld.is_empty():
		_msg = tr("UI_FORGE_DISMANTLE_NONE")
		_msg_color = DIM
		refresh()
		return
	var parts: Array[String] = []
	for id in yld:
		var mid := StringName(String(id))
		parts.append("%s×%d" % [tr(PlayerState.crafting().mat_key(mid)), int(yld[id])])
	_msg = I18n.t(&"UI_FORGE_DISMANTLE_OK", ["、".join(parts)])
	_msg_color = GOLD
	refresh()


## 打造光标那件（打造页 J）。**这一件**的制书没有时 J 是买书 ——
## 解锁与打造在一个键里闭环，不用再回商店跑一趟（商店也上架，同价）
func _craft_at_cursor() -> void:
	var path := selected_craft_path()
	if path.is_empty():
		return
	var it := load(path) as ItemData
	if it == null:
		return
	var tier := int(it.tier)
	if not PlayerState.has_blueprint(path):
		var price := int(PlayerState.crafting().blueprint_price.get(str(tier), 0))
		if PlayerState.unlock_blueprint(path):
			_msg = I18n.t(&"UI_CRAFT_BP_BOUGHT", [tr(it.name_key), price])
			_msg_color = GOLD
		else:
			_msg = I18n.t(&"UI_CRAFT_BP_POOR", [price])
			_msg_color = WARN
		refresh()
		return
	if not PlayerState.pay_materials_dry_run(PlayerState.crafting().cost_for(tier)):
		_msg = I18n.t(&"UI_CRAFT_POOR", [_missing_text(PlayerState.crafting().cost_for(tier))])
		_msg_color = WARN
		refresh()
		return
	var uid := PlayerState.craft(path)
	_msg = I18n.t(&"UI_CRAFT_OK", [tr(it.name_key)])
	_msg_color = GOLD
	refresh()
	if uid.is_empty():
		_msg = tr("UI_FORGE_DISMANTLE_NONE")   # 理论到不了（上面已 dry-run 过）；
		_msg_color = WARN                       # 兜一句，别让「没反应」出现
		refresh()


## 「缺什么、还缺多少」拼一句话 —— 只列不够的料
func _missing_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in cost:
		var mid := StringName(String(id))
		var have := PlayerState.material_count(mid)
		if have < int(cost[id]):
			parts.append("%s %d/%d" % [tr(PlayerState.crafting().mat_key(mid)), have, int(cost[id])])
	return "、".join(parts) if not parts.is_empty() else "—"


## 打造页的列表：全部可打造档（≥极品）的装备型号，按档升序、目录序稳定 ——
## 光标不会因为数据刷新而跳。**用 drop_pool 的索引**（它就是「档次 → 装备」
## 的唯一索引，加装备自动跟上），不用在这里再扫一遍目录
func _craft_paths() -> Array[String]:
	var out: Array[String] = []
	for t in [ItemData.Tier.RARE, ItemData.Tier.EPIC, ItemData.Tier.LEGENDARY]:
		out.append_array(GameProgress.drop_pool(t))
	return out


func selected_craft_path() -> String:
	var list := _craft_paths()
	if _cursor < 0 or _cursor >= list.size():
		return ""
	return list[_cursor]


# ── 绘制 ───────────────────────────────────────────────────────

## 行节点全部由代码建（与 HUD 面板同一套做法）：手写 tscn 的嵌套 parent 路径
## 容易静默丢节点，能省的静态节点就省掉
func _build_rows() -> void:
	for _i in ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon := ItemIcon.new()
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)

		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", FONT_SIZE)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl)

		_list.add_child(row)
		_rows.append(row)


func refresh() -> void:
	if _page == 0:
		_refresh_forge()
	else:
		_refresh_craft()


## 强化页（原样，标题与提示换成带 Tab/分解的版本）
func _refresh_forge() -> void:
	_title.text = tr("UI_FORGE_TITLE")
	_status.text = "%s ×%d　%s" % [
		tr("HUD_SHARD"), PlayerState.shards,
		tr("UI_FORGE_STATUS") if _msg.is_empty() else _msg]
	if not _msg.is_empty():
		_status.modulate = _msg_color
	else:
		_status.modulate = Color(1, 1, 1, 1)
	_hint.text = tr("UI_FORGE_HINT")

	var list := PlayerState.forgeable_uids()
	if _cursor >= list.size():
		_cursor = maxi(list.size() - 1, 0)
	var top := _scroll_top(list.size(), ROWS)
	for r in ROWS:
		var idx := top + r
		var row := _rows[r]
		var icon := row.get_child(0) as ItemIcon
		var lbl := row.get_child(1) as Label
		if idx >= list.size():
			icon.visible = false
			# 空状态要可见：整个列表空着才写一句，否则留空行
			lbl.text = tr("UI_FORGE_EMPTY") if (list.is_empty() and r == 0) else ""
			lbl.modulate = DIM
			continue
		icon.visible = true
		icon.empty_frame = true
		var uid := str(list[idx])
		var it := PlayerState.item_of(uid)
		icon.set_item(it)
		if it == null:
			lbl.text = INDENT + uid
			lbl.modulate = DIM
			continue
		var lv := PlayerState.forge_level(uid)
		var cap := PlayerState.forge_max(uid)
		var mark := CURSOR_MARK if idx == _cursor else INDENT
		var cost_text := tr("UI_FORGE_MAXED") if lv >= cap \
			else I18n.t(&"UI_FORGE_COST", [PlayerState.forge_cost(uid)])
		lbl.text = "%s%s　+%d/%d　%s　%s" % [
			mark, tr(it.name_key), lv, cap, _slot_of(uid, it), cost_text]
		if idx == _cursor:
			lbl.modulate = GOLD
		else:
			lbl.modulate = NORMAL


## 打造页：可打造档（极品+）的型号列表。**没解锁的档照常列出来、写成锁的样子** ——
## 玩家得看见「后面还有东西」，锁着的门比消失的墙更想让人打开
func _refresh_craft() -> void:
	_title.text = tr("UI_CRAFT_TITLE")
	# 状态行带元宝与精铁：打造的两条通用料。其余材料缺什么，J 的时候会说
	_status.text = "%s ×%d　%s ×%d　%s" % [
		tr("HUD_GOLD"), PlayerState.gold, tr("HUD_SHARD"), PlayerState.shards,
		tr("UI_CRAFT_STATUS") if _msg.is_empty() else _msg]
	if not _msg.is_empty():
		_status.modulate = _msg_color
	else:
		_status.modulate = Color(1, 1, 1, 1)
	_hint.text = tr("UI_CRAFT_HINT")

	var list := _craft_paths()
	if _cursor >= list.size():
		_cursor = maxi(list.size() - 1, 0)
	var top := _scroll_top(list.size(), ROWS)
	for r in ROWS:
		var idx := top + r
		var row := _rows[r]
		var icon := row.get_child(0) as ItemIcon
		var lbl := row.get_child(1) as Label
		if idx >= list.size():
			icon.visible = false
			lbl.text = ""
			lbl.modulate = DIM
			continue
		icon.visible = true
		icon.empty_frame = true
		var path := str(list[idx])
		var it := load(path) as ItemData
		icon.set_item(it)
		if it == null:
			lbl.text = INDENT + path
			lbl.modulate = DIM
			continue
		var mark := CURSOR_MARK if idx == _cursor else INDENT
		if not PlayerState.has_blueprint(path):
			var bp := int(PlayerState.crafting().blueprint_price.get(str(int(it.tier)), 0))
			lbl.text = "%s%s　🔒 %s" % [mark, tr(it.name_key),
				I18n.t(&"UI_CRAFT_BP_LOCKED", [bp])]
			lbl.modulate = DIM
			continue
		var cost := PlayerState.crafting().cost_for(int(it.tier))
		var parts: Array[String] = []
		for id in cost:
			var mid := StringName(String(id))
			parts.append("%s×%d" % [tr(PlayerState.crafting().mat_key(mid)), int(cost[id])])
		lbl.text = "%s%s　%s" % [mark, tr(it.name_key), "　".join(parts)]
		# 够料才亮 —— 一眼分得出「现在就能造」和「还差料」
		lbl.modulate = GOLD if idx == _cursor \
			else (NORMAL if PlayerState.pay_materials_dry_run(cost) else DIM)


## 这件装备现在装在哪（「武器」/「背包」）—— 列表里两类混排，得看得出来
func _slot_of(uid: String, it: ItemData) -> String:
	var slot_key := it.slot_id()
	if PlayerState.equipped_uid(slot_key) == uid:
		return tr(String(it.slot_key()))
	return tr("UI_FORGE_IN_BAG")


func _scroll_top(total: int, rows: int) -> int:
	if total <= rows:
		return 0
	return clampi(_cursor - rows / 2, 0, total - rows)


func _hud() -> Node:
	var p := get_parent()
	if p == null:
		return null
	return p.get_node_or_null("HUD")
