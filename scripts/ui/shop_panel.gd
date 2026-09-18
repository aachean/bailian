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
## 右栏（制书）几行
const ROWS := 8
## 左栏几行。**比右栏多** —— 左栏除了 7 件装备货架，还要放还魂丹 + 3 种消耗品。
## 11×18 = 198px，容器高 204px（Panel 300 − 顶 68 − 底 28 = 204）—— 刚好塞得下。
##
## **左栏没有滚动窗口**，超出 GEAR_ROWS 的条目既渲染不出来、光标也移不到。
## 所以 `_ready` 里有一条自检：条目数一旦超过它，**当场报错**。
## 少这一条的话，加第 12 种消耗品的后果是「上架了但商店里看不到」，
## 而且没有任何地方会红 —— 那正是本项目最受不了的一种失败。
const GEAR_ROWS := 11
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
	_build_rows(_list, _rows, GEAR_ROWS)
	_build_rows(_bp_box, _bp_rows, ROWS)
	# 左栏是固定行数的**无滚动**列 —— 条目一多就会「上架了但看不见」。
	# 让它在启动时就炸，别等到玩家逛商店发现少了东西（本项目的「不能静默」）
	assert(_left_entries().size() <= GEAR_ROWS,
		"商店左栏条目 %d 条，超过 GEAR_ROWS=%d —— 请先给左栏加滚动窗口"
			% [_left_entries().size(), GEAR_ROWS])
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


## 左栏条目 = 本期随机货架（装备路径）+ 常驻的**还魂丹**与**三种消耗品**。
##
## 消耗品用的是**预载**形态（原则 5.6 第二条）：买的是「次数」，按 6 / 7 主动用 ——
## 元宝买的不是背包药水，所以不违反 5.6，两条并存。见 docs/adr/0022 §2.3。
## `item_hp` / `item_mp` 这两个名字与键位动作名同形，**键位顺序的唯一出处是
## `PlayerState.POTION_KINDS`**；补给包（血蓝各 5 次）是一个打包价，没有自己的格
func _left_entries() -> Array:
	var out: Array = PlayerState.shop_offers.duplicate()
	out.append("revive")
	for kind in PlayerState.POTION_KINDS:
		out.append("item_%s" % kind)
	out.append("supply")
	return out


## 从 `item_hp` / `item_mp` 反查消耗品种类。名字是拼出来的，就一定从同一处拆回来
func _entry_potion(entry: String) -> StringName:
	return StringName(entry.substr("item_".length()))


## 右栏 = 本期的随机制书（PlayerState.shop_bp_offers）。制书不再常驻 ——
## 每期 8 个书位独立 roll（极品 10% / 传说 5% / 至尊 1%），买走即撤下，
## 再想要等下次刷新（2026-09-18 神定）
func _bp_list() -> Array:
	return PlayerState.shop_bp_offers


## 买光标那件。两个栏一个键，「为什么没买成」按条目类型区分着说
func _buy_at_cursor() -> void:
	var left := _left_entries()
	if _cursor < left.size():
		var entry: String = str(left[_cursor])
		if entry == "revive":
			_buy_revive()
		elif entry == "supply":
			_buy_supply()
		elif entry.begins_with("item_"):
			_buy_potion(_entry_potion(entry))
		else:
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


## 买一份预载符（回血 / 回蓝）。不限购 —— 它是元宝的**可重复 sink**，
## 限购就修不好 ECONOMY.md 里那个「元宝过剩」的账
func _buy_potion(kind: StringName) -> void:
	var price := PlayerState.potion_price(kind)
	if PlayerState.gold < price:
		_msg = I18n.t(&"UI_SHOP_POOR", [price - PlayerState.gold])
		_msg_color = WARN
		refresh()
		return
	if PlayerState.buy_potion(kind):
		# 报**总剩余次数**而不是「+3」：玩家真正要知道的是「我还能喝几次」
		_msg = I18n.t(&"UI_SHOP_POTION_OK",
			[_potion_label(kind), PlayerState.potion_charges(kind)])
		_msg_color = GOLD
	else:
		_msg = tr("UI_SHOP_UNAVAILABLE")
		_msg_color = WARN
	refresh()


## 买补给包（血蓝各 5 次，一口价 160）
func _buy_supply() -> void:
	if PlayerState.gold < PlayerState.SUPPLY_PRICE:
		_msg = I18n.t(&"UI_SHOP_POOR", [PlayerState.SUPPLY_PRICE - PlayerState.gold])
		_msg_color = WARN
		refresh()
		return
	if PlayerState.buy_supply():
		_msg = I18n.t(&"UI_SHOP_SUPPLY_OK", [
			PlayerState.potion_charges(PlayerState.POTION_HP),
			PlayerState.potion_charges(PlayerState.POTION_MP)])
		_msg_color = GOLD
	else:
		_msg = tr("UI_SHOP_UNAVAILABLE")
		_msg_color = WARN
	refresh()


## 消耗品的显示名。**与技能栏的提示、飘字同一份 key** —— 别处再写一遍人话就会漂
func _potion_label(kind: StringName) -> String:
	return tr("ITEM_POTION_MP") if kind == PlayerState.POTION_MP else tr("ITEM_POTION_HP")


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
	PlayerState.save_shop_state()      # 买走即落盘 —— 时钟与货架属于现实世界
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
		PlayerState.shop_bp_offers.erase(bp_path)   # 本期限购 1：买走即撤，下期再随机
		PlayerState.save_shop_state()
		_msg = I18n.t(&"UI_SHOP_BP_OK", [tr(bp_it.name_key)])
		_msg_color = GOLD
	else:
		_msg = tr("UI_SHOP_UNAVAILABLE")
		_msg_color = WARN
	refresh()


# ── 绘制 ───────────────────────────────────────────────────────

## 行节点全部由代码建（与铁匠铺同一套做法）：手写 tscn 的嵌套 parent 路径
## 容易静默丢节点，能省的静态节点就省掉
func _build_rows(box: VBoxContainer, into: Array[HBoxContainer], n: int) -> void:
	for _i in n:
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
	# **分界线必须用 gear.size()**，不能用 shop_offers.size()：
	# 左栏除了货架还挂着还魂丹与消耗品，拿货架数当边界会让右栏窗口算错位置
	var cursor_in_bp := _cursor >= gear.size()
	if cursor_in_bp:
		_bp_top = clampi(_cursor - gear.size() - ROWS / 2, 0, maxi(bps.size() - ROWS, 0))
	else:
		_bp_top = clampi(_bp_top, 0, maxi(bps.size() - ROWS, 0))

	# ── 左栏：装备货架（尾部常驻还魂丹 + 三种消耗品）──
	for r in GEAR_ROWS:
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
			# **不能借回血符的瓶子**：这一行上面是货架、下面是回血符，
			# 三行挨着放两个红瓶子，读错行是迟早的事（2026-09-18 顺手拆开）
			icon.kind = &"revive"
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
		# 消耗品行：回血符 / 回蓝符 / 补给包。价格 + **剩余次数** ——
		# 买了多少、还能喝几次，是玩家在这三行上唯一要做的判断
		if gear[r] == "supply":
			var supply_can := PlayerState.gold >= PlayerState.SUPPLY_PRICE
			icon.visible = true
			icon.empty_frame = true
			icon.kind = &"supply"
			icon.queue_redraw()
			lbl.text = "%s%s　%d　%s" % [CURSOR_MARK if _cursor == r else INDENT,
				tr("UI_SHOP_SUPPLY"), PlayerState.SUPPLY_PRICE,
				I18n.t(&"UI_SHOP_SUPPLY_STOCK", [
					PlayerState.potion_charges(PlayerState.POTION_HP),
					PlayerState.potion_charges(PlayerState.POTION_MP)])]
			if _cursor == r:
				lbl.modulate = GOLD if supply_can else WARN
			else:
				lbl.modulate = NORMAL if supply_can else DIM
			continue
		if str(gear[r]).begins_with("item_"):
			var kind := _entry_potion(str(gear[r]))
			var price := PlayerState.potion_price(kind)
			var pot_can := PlayerState.gold >= price
			icon.visible = true
			icon.empty_frame = true
			icon.kind = &"potion_mp" if kind == PlayerState.POTION_MP else &"potion_hp"
			icon.queue_redraw()
			lbl.text = "%s%s　%d　%s %d" % [CURSOR_MARK if _cursor == r else INDENT,
				_potion_label(kind), price, tr("UI_SHOP_CHARGES"),
				PlayerState.potion_charges(kind)]
			if _cursor == r:
				lbl.modulate = GOLD if pot_can else WARN
			else:
				lbl.modulate = NORMAL if pot_can else DIM
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
		# 名字颜色 = 品质色（档色是唯一色源 tier_color）。选中提亮一档当高亮，
		# 买不起压暗 —— 颜色仍然在说「这是哪个档」
		var c: Color = it.tier_color()
		if _cursor == r:
			lbl.modulate = c.lightened(0.35) if afford else c.darkened(0.35)
		else:
			lbl.modulate = c if afford else c.darkened(0.4)

	# ── 右栏：制书（逐件，滚动窗口）──
	for r in ROWS:
		var row := _bp_rows[r]
		var icon := row.get_child(0) as ItemIcon
		var lbl := row.get_child(1) as Label
		var idx := _bp_top + r
		if idx >= bps.size():
			icon.visible = false
			lbl.text = tr("UI_SHOP_BP_NONE") if (bps.is_empty() and r == 0) else ""
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
		# 书名就是装备名（制书·寒月剑），颜色跟装备的档走；已有的置灰 ——
		# 钱再多也不卖第二本
		lbl.text = "%s📖 %s　%d" % [mark,
			I18n.t(&"UI_BP_TIER", [tr(bp_it.name_key)]), price]
		if owned:
			lbl.modulate = DIM
		else:
			var c: Color = bp_it.tier_color()
			lbl.modulate = c.lightened(0.35) if sel else c


## 右上角倒计时：「下次刷新 2:41」（时:分）。过期显示「即将」—— 打开那一刻会换货
func _update_refresh_label() -> void:
	var left := PlayerState.shop_refresh_in()
	if left <= 0.0:
		_refresh_label.text = tr("UI_SHOP_REFRESH_SOON")
		return
	# 4:00 会被读成四分钟 —— 摆全 时:分:秒（2026-09-18 神圈注）
	var total_sec := int(ceil(left))
	_refresh_label.text = "%s %d:%02d:%02d" % [
		tr("UI_SHOP_REFRESH_IN"), total_sec / 3600, (total_sec / 60) % 60, total_sec % 60]


func _scroll_top(total: int, rows: int) -> int:
	if total <= rows:
		return 0
	return clampi(_cursor - rows / 2, 0, total - rows)


func _hud() -> Node:
	var p := get_parent()
	if p == null:
		return null
	return p.get_node_or_null("HUD")
