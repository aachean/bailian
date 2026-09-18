extends CanvasLayer
## 商店：**两栏** —— 左栏装备（随机货架，每 4 现实小时刷新）、右栏制书（常驻 66 本）。
## 站在商店台前按 J 打开（首通砺场后才开张）。
##
## ── 为什么两栏 ────────────────────────────────────────────────
## 单栏把装备和制书混在一起，右半屏全是空的（2026-09-18 神的截图圈注）。
## 分开后左栏是「这一批的货」（8 件，随刷新换），右栏是「打造许可」（逐件制书，
## 永远全在）—— 两类商品的生命周期本来就不同。
##
## ── 刷新 ─────────────────────────────────────────────────────
## 装备货架每 `ShopData.refresh_hours`（=4）**现实小时**换一批：从已建档的
## 掉落档次随机抽 8 件。**进面板时查一次**（ensure_shop_fresh），不靠时钟轮询；
## 上次刷新时刻进存档，关游戏时间也在走。右上角常驻倒计时。
##
## ── 与其它模态界面同一套约定 ──────────────────────────────────
## 挂在玩家节点下，`process_mode = ALWAYS` + `get_tree().paused = true`，
## 打开时先把 HUD 的面板让开，自己开着的时候别人不开（互查 is_open）。

## 每栏显示几行
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
var _rows: Array[HBoxContainer] = []        # 左栏（装备货架）
var _bp_rows: Array[HBoxContainer] = []     # 右栏（制书）
## 制书区的滚动窗口顶（只滚右栏 —— 左栏货 ≤ 8 件本来就放得下）
var _bp_top := 0
## 上一次操作的结果。**不静默**：按了键什么也没发生，玩家分不清是「没反应」还是「钱不够」
var _msg := ""
var _msg_color := DIM
## 倒计时一秒才变一次，没必要每帧刷
var _clock_accum := 0.0

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Panel/Title
@onready var _status: Label = $Root/Panel/Status
@onready var _refresh_label: Label = $Root/Panel/RefreshLabel
@onready var _gear_header: Label = $Root/Panel/GearHeader
@onready var _bp_header: Label = $Root/Panel/BPHeader
@onready var _list: VBoxContainer = $Root/Panel/Rows
@onready var _bp_box: VBoxContainer = $Root/Panel/BPRows
@onready var _hint: Label = $Root/Panel/Hint


func _ready() -> void:
	_root.visible = false
	_build_rows(_list, _rows)
	_build_rows(_bp_box, _bp_rows)
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


## 倒计时是分钟级的，一秒刷一次文字足够（其它内容只在交互时重刷）
func _process(delta: float) -> void:
	if not _root.visible:
		return
	_clock_accum += delta
	if _clock_accum >= 1.0:
		_clock_accum = 0.0
		_update_refresh_label()


func is_open() -> bool:
	return _root.visible


# ── 入口 ───────────────────────────────────────────────────────

func open() -> void:
	_cursor = 0
	_bp_top = 0
	_msg = ""
	# 货架过期检查在这里（打开看一眼），不在 _process 里轮询
	PlayerState.ensure_shop_fresh()
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
	var n := _left_entries().size() + _bp_list().size()
	if n <= 0:
		return
	_cursor = wrapi(_cursor + dir, 0, n)
	_msg = ""
	refresh()


## 左栏条目 = 本期随机货架（装备路径）+ 尾部一条**还魂丹**（常驻消耗）。
## 还魂丹每图限购 5（200 元宝，账记到最近进的图）
func _left_entries() -> Array:
	var out: Array = PlayerState.shop_offers.duplicate()
	out.append("revive")
	return out


## 右栏 = 逐件制书（66 本，装备路径）。书就是装备本身，索引用 drop_pool 现拼
func _bp_list() -> Array:
	var out: Array = []
	for t in [ItemData.Tier.RARE, ItemData.Tier.EPIC, ItemData.Tier.LEGENDARY]:
		out.append_array(GameProgress.drop_pool(t))
	return out


## 买光标那件。两个栏一个键，「为什么没买成」按条目类型区分着说
func _buy_at_cursor() -> void:
	var left := _left_entries()
	var gear_n: int = PlayerState.shop_offers.size()
	if _cursor < left.size():
		var entry = left[_cursor]
		if entry is String and entry == "revive":
			_buy_revive()
		elif entry is String:
			_buy_gear(entry)
		return
	_buy_blueprint(str(_bp_list()[_cursor - left.size()]))


## 买还魂丹：限购按图（玩家最近进的图，人在城镇买账记到要打的图上）
func _buy_revive() -> void:
	var map_id := _current_or_latest_map()
	if PlayerState.gold < PlayerState.REVIVE_PRICE:
		_msg = I18n.t(&"UI_SHOP_POOR", [PlayerState.REVIVE_PRICE - PlayerState.gold])
		_msg_color = WARN
		refresh()
		return
	if PlayerState.buy_revive_token(map_id):
		_msg = I18n.t(&"UI_SHOP_REVIVE_OK", [PlayerState.revive_tokens])
		_msg_color = GOLD
	else:
		_msg = I18n.t(&"UI_SHOP_REVIVE_LIMIT")
		_msg_color = WARN
	refresh()


## 商店开在城镇 —— 城镇不设 current_map_id，账记到「已解锁的最新图」上：
## 玩家攒丹是为了往后打，限购按他要打的图算
func _current_or_latest_map() -> StringName:
	if not GameProgress.current_map_id.is_empty():
		return GameProgress.current_map_id
	var seq := GameProgress.sequence()
	return seq[seq.size() - 1].id if not seq.is_empty() else &""


## 买装备（左栏）。买完从货架上撤下 —— 摆着的东西买走了还摆着，那不是商店是仓库
func _buy_gear(path: String) -> void:
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
	PlayerState.shop_offers.erase(path)
	_msg = I18n.t(&"UI_SHOP_BUY_OK", [PlayerState.gold])
	_msg_color = GOLD
	refresh()


## 买制书（右栏）：拿到**这一件**的打造许可（永久）；已有这本书拒绝重复付费
func _buy_blueprint(bp_path: String) -> void:
	var bp_it := load(bp_path) as ItemData
	if bp_it == null:
		_msg = tr("UI_SHOP_UNAVAILABLE")
		_msg_color = WARN
		refresh()
		return
	if PlayerState.has_blueprint(bp_path):
		_msg = tr("UI_SHOP_BP_OWNED")
		_msg_color = DIM
		refresh()
		return
	var price := int(PlayerState.crafting().blueprint_price.get(str(int(bp_it.tier)), 0))
	if PlayerState.gold < price:
		_msg = I18n.t(&"UI_SHOP_POOR", [price - PlayerState.gold])
		_msg_color = WARN
		refresh()
		return
	if PlayerState.unlock_blueprint(bp_path):
		_msg = I18n.t(&"UI_SHOP_BP_OK", [tr(bp_it.name_key)])
		_msg_color = GOLD
	else:
		_msg = tr("UI_SHOP_UNAVAILABLE")
		_msg_color = WARN
	refresh()


# ── 绘制 ───────────────────────────────────────────────────────

## 行节点全部由代码建（与铁匠铺同一套做法）：手写 tscn 的嵌套 parent 路径
## 容易静默丢节点，能省的静态节点就省掉
func _build_rows(box: VBoxContainer, into: Array[HBoxContainer]) -> void:
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

		box.add_child(row)
		into.append(row)


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
	_gear_header.text = tr("UI_SHOP_GEAR")
	_bp_header.text = tr("UI_SHOP_BP")
	_update_refresh_label()

	var gear := _left_entries()
	var bps := _bp_list()
	var total := gear.size() + bps.size()
	if _cursor >= total:
		_cursor = maxi(total - 1, 0)
	var cursor_in_bp := _cursor >= PlayerState.shop_offers.size()
	if cursor_in_bp:
		_bp_top = clampi(_cursor - PlayerState.shop_offers.size() - ROWS / 2, 0, maxi(bps.size() - ROWS, 0))
	else:
		_bp_top = clampi(_bp_top, 0, maxi(bps.size() - ROWS, 0))

	# ── 左栏：装备货架（尾部一条常驻还魂丹）──
	for r in ROWS:
		var row := _rows[r]
		var icon := row.get_child(0) as ItemIcon
		var lbl := row.get_child(1) as Label
		if r >= gear.size():
			icon.visible = false
			# 货架空要看得见（刷新批没抽出来 / 全买光了是两种状态的开头）
			lbl.text = tr("UI_SHOP_EMPTY") if (PlayerState.shop_offers.is_empty() and r == 0) else ""
			lbl.modulate = DIM
			continue
		# 还魂丹行：常驻消耗，显示持有数与限购余量
		if gear[r] == "revive":
			icon.visible = true
			icon.empty_frame = true
			icon.kind = &"potion_hp"
			icon.queue_redraw()
			var bought := PlayerState.revive_bought_in(_current_or_latest_map())
			var mark := CURSOR_MARK if _cursor == r else INDENT
			var limit_left := 5 - bought
			lbl.text = "%s%s　%d　%s %d" % [mark, tr("UI_SHOP_REVIVE"),
				PlayerState.REVIVE_PRICE, tr("UI_SHOP_LIMIT"), limit_left]
			var can := limit_left > 0 and PlayerState.gold >= PlayerState.REVIVE_PRICE
			if _cursor == r:
				lbl.modulate = GOLD if can else WARN
			else:
				lbl.modulate = NORMAL if can else DIM
			continue
		var it := load(str(gear[r])) as ItemData
		if it == null:
			icon.visible = false
			lbl.text = INDENT + "?"
			lbl.modulate = DIM
			continue
		icon.visible = true
		icon.empty_frame = true
		icon.kind = &""
		icon.set_item(it)
		var mark := CURSOR_MARK if _cursor == r else INDENT
		var afford := PlayerState.gold >= it.gold_price
		lbl.text = "%s%s　%d" % [mark, tr(it.name_key), it.gold_price]
		if _cursor == r:
			lbl.modulate = GOLD if afford else WARN
		else:
			lbl.modulate = NORMAL if afford else Color(0.62, 0.6, 0.55, 1)

	# ── 右栏：制书（逐件，滚动窗口）──
	for r in ROWS:
		var row := _bp_rows[r]
		var icon := row.get_child(0) as ItemIcon
		var lbl := row.get_child(1) as Label
		var idx := _bp_top + r
		if idx >= bps.size():
			icon.visible = false
			lbl.text = ""
			lbl.modulate = DIM
			continue
		var bp_it := load(str(bps[idx])) as ItemData
		if bp_it == null:
			icon.visible = false
			lbl.text = INDENT + "?"
			lbl.modulate = DIM
			continue
		icon.visible = true
		icon.empty_frame = true
		icon.set_item(bp_it)
		var sel := _cursor == gear.size() + idx
		var mark := CURSOR_MARK if sel else INDENT
		var price := int(PlayerState.crafting().blueprint_price.get(str(int(bp_it.tier)), 0))
		var owned := PlayerState.has_blueprint(str(bps[idx]))
		# 书名就是装备名（制书·寒月剑）；已有的置灰 —— 钱再多也不卖第二本
		lbl.text = "%s📖 %s　%d" % [mark,
			I18n.t(&"UI_BP_TIER", [tr(bp_it.name_key)]), price]
		lbl.modulate = DIM if owned else (GOLD if sel else NORMAL)


## 右上角倒计时：「下次刷新 2:41」（时:分）。过期显示「即将」—— 打开那一刻会换货
func _update_refresh_label() -> void:
	var left := PlayerState.shop_refresh_in()
	if left <= 0.0:
		_refresh_label.text = tr("UI_SHOP_REFRESH_SOON")
		return
	var total_min := int(ceil(left / 60.0))
	_refresh_label.text = "%s %d:%02d" % [tr("UI_SHOP_REFRESH_IN"), total_min / 60, total_min % 60]


func _scroll_top(total: int, rows: int) -> int:
	if total <= rows:
		return 0
	return clampi(_cursor - rows / 2, 0, total - rows)


func _hud() -> Node:
	var p := get_parent()
	if p == null:
		return null
	return p.get_node_or_null("HUD")
