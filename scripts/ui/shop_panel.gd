extends CanvasLayer
## 商店：花元宝买装备。站在商店台前按 J 打开（首通砺场后才开张）。
##
## ── 为什么卖在背包、买在这里 ──────────────────────────────────
## 买：货架是商店自己的东西，进店才看得到 —— 界面跟着「谁的东西」走。
## 卖：卖的是**玩家背包里**的存货，背包界面本来就在逐件展示它们，
## 在那儿按 K 是最少操作的选择（造梦西游也是背包里按卖）。
##
## ── 与其它模态界面同一套约定 ──────────────────────────────────
## 挂在玩家节点下，`process_mode = ALWAYS` + `get_tree().paused = true`，
## 打开时先把 HUD 的面板让开，自己开着的时候别人不开（互查 is_open）。

## 一屏显示几行（库存比这个少就照实画）
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

## 可打造档（≥极品）的档次名 i18n key。下标 = ItemData.Tier 枚举值
const TIER_I18N := {3: "UI_TIER_3", 4: "UI_TIER_4", 5: "UI_TIER_5"}

var _cursor := 0
var _rows: Array[HBoxContainer] = []
## 上一次操作的结果。**不静默**：按了键什么也没发生，玩家分不清是「没反应」还是「钱不够」
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
	if not PlayerState.gold_changed.is_connected(_on_gold_changed):
		PlayerState.gold_changed.connect(_on_gold_changed)
	if not PlayerState.equipment_changed.is_connected(_on_gold_changed):
		PlayerState.equipment_changed.connect(_on_gold_changed)
	if not GameSettings.language_changed.is_connected(_on_language_changed):
		GameSettings.language_changed.connect(_on_language_changed)


## 买东西 / 卖东西（另一个面板里按 K）都会动元宝和背包 —— 全量重刷，不做增量
func _on_gold_changed(_new_gold: int = 0) -> void:
	if _root.visible:
		refresh()


## 参数必须留着：Godot 按参数个数严格匹配信号连接（少一个会在 emit 时静默报错）
func _on_language_changed(_locale: String = "") -> void:
	if _root.visible:
		refresh()


func is_open() -> bool:
	return _root.visible


# ── 入口 ───────────────────────────────────────────────────────

func open() -> void:
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


func close() -> void:
	_root.visible = false
	_msg = ""
	get_tree().paused = false


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
				_buy_at_cursor()
		get_viewport().set_input_as_handled()


func _move(dir: int) -> void:
	var n := _entries().size()
	if n <= 0:
		return
	_cursor = wrapi(_cursor + dir, 0, n)
	_msg = ""
	refresh()


## 货架条目：装备（资源路径字符串）在前，制书（["bp", tier] 数组）在后 ——
## 制书是「解锁」类商品，摆货架尾部；价格真相在 CraftingData（与铁匠铺买同价）
func _entries() -> Array:
	var out: Array = []
	var shop := PlayerState.shop()
	if shop != null:
		out.append_array(shop.stock)
		var bps: Dictionary = shop.blueprint_tiers
		for k in bps:
			out.append(["bp", int(k)])
	return out


## 买光标那件。PlayerState.buy_item 只回答成不成功，
## 「为什么没买成」由这里区分着说 —— 钱不够与别的原因，玩家的下一步完全不同
func _buy_at_cursor() -> void:
	var list := _entries()
	if _cursor < 0 or _cursor >= list.size():
		return
	var entry = list[_cursor]
	# ── 制书条目：买 = 解锁该档打造（永久），已解锁的拒绝重复付费 ──
	if entry is Array:
		var tier := int(entry[1])
		var price := int(PlayerState.crafting().blueprint_price.get(str(tier), 0))
		if PlayerState.tier_unlocked(tier):
			_msg = tr("UI_SHOP_BP_OWNED")
			_msg_color = DIM
			refresh()
			return
		if PlayerState.gold < price:
			_msg = I18n.t(&"UI_SHOP_POOR", [price - PlayerState.gold])
			_msg_color = WARN
			refresh()
			return
		if PlayerState.unlock_tier(tier):
			_msg = I18n.t(&"UI_SHOP_BP_OK", [PlayerState.gold])
			_msg_color = GOLD
		else:
			_msg = tr("UI_SHOP_UNAVAILABLE")
			_msg_color = WARN
		refresh()
		return
	# ── 装备条目（原样）──
	var path := str(entry)
	var it := load(path) as ItemData
	if it != null and PlayerState.gold < it.gold_price:
		_msg = I18n.t(&"UI_SHOP_POOR", [it.gold_price - PlayerState.gold])
		_msg_color = WARN
		refresh()
		return
	var uid := PlayerState.buy_item(path)
	if uid.is_empty():
		_msg = tr("UI_SHOP_UNAVAILABLE")
		_msg_color = WARN
		refresh()
		return
	_msg = I18n.t(&"UI_SHOP_BUY_OK", [PlayerState.gold])
	_msg_color = GOLD
	refresh()


func _stock() -> Array:
	var shop := PlayerState.shop()
	return [] if shop == null else shop.stock


# ── 绘制 ───────────────────────────────────────────────────────

## 行节点全部由代码建（与铁匠铺同一套做法）：手写 tscn 的嵌套 parent 路径
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
	_title.text = tr("UI_SHOP_TITLE")
	_status.text = "%s ×%d　%s" % [
		tr("HUD_GOLD"), PlayerState.gold,
		tr("UI_SHOP_STATUS") if _msg.is_empty() else _msg]
	if not _msg.is_empty():
		_status.modulate = _msg_color
	else:
		_status.modulate = Color(1, 1, 1, 1)
	_hint.text = tr("UI_SHOP_HINT")

	var list := _entries()
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
			# 空状态要可见：整个货架空着才写一句，否则留空行
			lbl.text = tr("UI_SHOP_EMPTY") if (list.is_empty() and r == 0) else ""
			lbl.modulate = DIM
			continue
		var entry = list[idx]
		# ── 制书行：没有装备图标，画个「书」字占位 —— 视觉上跟装备分得开 ──
		if entry is Array:
			var tier := int(entry[1])
			var price := int(PlayerState.crafting().blueprint_price.get(str(tier), 0))
			icon.visible = false
			var mark := CURSOR_MARK if idx == _cursor else INDENT
			var owned := PlayerState.tier_unlocked(tier)
			lbl.text = "%s📖 %s　%s ×%d" % [mark,
				I18n.t(&"UI_BP_TIER", [tr(TIER_I18N[tier])]), tr("HUD_GOLD"), price]
			lbl.modulate = DIM if owned else (GOLD if idx == _cursor else NORMAL)
			continue
		var it := load(str(entry)) as ItemData
		if it == null:
			icon.visible = false
			lbl.text = INDENT + "?"
			lbl.modulate = DIM
			continue
		icon.visible = true
		icon.empty_frame = true
		icon.set_item(it)
		var mark := CURSOR_MARK if idx == _cursor else INDENT
		var afford := PlayerState.gold >= it.gold_price
		lbl.text = "%s%s　%s　%d" % [mark, tr(it.name_key), tr("HUD_GOLD"), it.gold_price]
		if idx == _cursor:
			lbl.modulate = GOLD if afford else WARN
		else:
			lbl.modulate = NORMAL if afford else Color(0.62, 0.6, 0.55, 1)


func _scroll_top(total: int, rows: int) -> int:
	if total <= rows:
		return 0
	return clampi(_cursor - rows / 2, 0, total - rows)


func _hud() -> Node:
	var p := get_parent()
	if p == null:
		return null
	return p.get_node_or_null("HUD")
