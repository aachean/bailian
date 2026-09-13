extends CanvasLayer
## 玩家 HUD：左上角色状态（血 / 蓝 / 经验 / 等级），右上背包（精铁）。
## C 键开角色面板（属性总览），B 键开装备背包（四个槽 + 背包列表）。
##
## 挂在玩家场景里 —— CanvasLayer 不吃相机变换，永远钉在屏幕角上。
## 数据直接读父节点（玩家），每帧轮询刷新：血 / 蓝 / 碎片 / 经验都可能变，
## 与其给每个变化点接信号，不如一帧一次的轮询便宜又不会漏。
##
## ── 为什么装备面板要暂停游戏 ──────────────────────────────────
## 查看类面板（C 角色属性）不暂停 —— 边打边看没问题。
## 但装备面板是【操作类】：要上下选、要比数值、要决定换哪件，
## 这几十秒里怪还在打你，换装就变成了挨打。所以打开即真暂停（与暂停菜单同机制，
## process_mode = ALWAYS 才能在暂停里收键）。这条偏离了 design-conventions 里
## 「面板不暂停游戏」的旧约定，已改文档并写进 docs/adr/0005。

const BAG_ROWS := 6              # 背包列表一屏几行，超出靠光标滚动
const CURSOR_MARK := "▶ "
const INDENT := "   "
const ROW_HEIGHT := 20.0         # 背包面板一行的高度：图标 16 + 上下各留 2
const ICON_SIZE := 16.0
const CHAR_ROW_HEIGHT := 18.0    # 角色面板一行（更挤：上面还有八行属性）

var _bag_open := false
var _cursor := 0                 # 全面板共用一个光标：0..3 是装备槽，之后是背包
var _equip_rows: Array[HBoxContainer] = []
var _bag_rows: Array[HBoxContainer] = []
var _char_equip_rows: Array[HBoxContainer] = []
## 父节点是不是玩家。HUD 只在玩家身上工作 —— 被单独实例化（场景完整性检查器
## 就是这么干的）时不能崩，否则每一次校验都带一堆假报错
var _has_player := false

@onready var _player: Node = get_parent()
@onready var _hp_fill: ColorRect = $Status/HPBar/Fill
@onready var _mp_fill: ColorRect = $Status/MPBar/Fill
@onready var _exp_fill: ColorRect = $ExpBar/Fill
@onready var _lv_label: Label = $Status/Level
@onready var _bag_label: Label = $Bag/Count
@onready var _panel: Panel = $CharPanel
@onready var _panel_text: Label = $CharPanel/Text
@onready var _char_equip_box: VBoxContainer = $CharPanel/EquipRows
@onready var _skill_cd: ColorRect = $SkillBar/Cooldown
@onready var _skill_icon: ColorRect = $SkillBar/Icon
@onready var _skill_core: ColorRect = $SkillBar/IconCore
@onready var _bag_panel: Panel = $BagPanel
@onready var _bag_title: Label = $BagPanel/Title
@onready var _equip_box: VBoxContainer = $BagPanel/EquipRows
@onready var _rows_box: VBoxContainer = $BagPanel/Rows
@onready var _bag_hint: Label = $BagPanel/Hint


func _ready() -> void:
	_has_player = _player != null and _player.is_in_group("player")
	_panel.visible = false
	_bag_panel.visible = false
	_build_rows()
	refresh()


func _process(_delta: float) -> void:
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("panel"):
		_panel.visible = not _panel.visible
		refresh()
		return
	if event.is_action_pressed("bag"):
		toggle_bag()
		return
	# 背包打开时才接管方向键 / J —— 平时它们该归战斗
	if not _bag_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_bag_key((event as InputEventKey).keycode)


# ─────────────────────────────────────────────────────────────
# 装备 / 背包面板
# ─────────────────────────────────────────────────────────────

## 面板的行节点全部由代码建。手写 tscn 的嵌套 parent 路径写错过三次，
## 能省的静态节点就省掉 —— 少一个节点就少一次静默丢节点的机会。
## 每行 = [装备图标][文字]，图标走 ItemIcon（程序化矢量图，不引贴图）
func _build_rows() -> void:
	for _i in ItemData.SLOT_IDS.size():
		_equip_rows.append(_make_row(_equip_box))
	for _i in BAG_ROWS:
		_bag_rows.append(_make_row(_rows_box))
	for _i in ItemData.SLOT_IDS.size():
		_char_equip_rows.append(_make_row(_char_equip_box, CHAR_ROW_HEIGHT))


## 造一行：图标 + 文字。图标按部位画形状、按品质上色，与地上掉落物同一套
func _make_row(parent: Node, row_height: float = ROW_HEIGHT) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(0.0, row_height)
	box.add_theme_constant_override("separation", 3)

	var icon := ItemIcon.new()
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)

	parent.add_child(box)
	return box


## 填一行装备：图标 + 「槽位名　装备名　词条」。背包面板与角色面板共用 ——
## 两处必须长得一样，否则「同一件装备在哪儿都是同一个样」这条就断了
func _fill_equip_row(row: HBoxContainer, i: int, it: ItemData, mark: String) -> void:
	var icon := _row_icon(row)
	var lbl := _row_label(row)
	icon.empty_frame = true          # 空槽画一个空框，不留白（空状态也要可见）
	icon.set_item(it)
	var slot_name: String = tr(String(ItemData.SLOT_KEYS[i]))
	if it == null:
		lbl.text = "%s%s　%s" % [mark, slot_name, tr("UI_BAG_EMPTY")]
		lbl.modulate = Color(0.62, 0.6, 0.55, 1)
	else:
		lbl.text = "%s%s　%s　%s" % [mark, slot_name, _item_name(it), _stat_text(it)]
		lbl.modulate = Color(0.9, 0.88, 0.84, 1)


func _row_icon(row: HBoxContainer) -> ItemIcon:
	return row.get_child(0) as ItemIcon


func _row_label(row: HBoxContainer) -> Label:
	return row.get_child(1) as Label


## 面板上全部文字（给断言用：漏翻的 key 会在这些文本里露出来）
func panel_texts() -> Array[String]:
	var out: Array[String] = []
	_collect_labels(self, out)
	return out


func _collect_labels(node: Node, out: Array[String]) -> void:
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		_collect_labels(c, out)


func is_bag_open() -> bool:
	return _bag_open


func toggle_bag() -> void:
	# 暂停菜单或对话框开着时不叠背包：几个界面都要抢 Esc / B / J，叠起来只会互相打架
	if not _bag_open and (_pause_menu_open() or _dialogue_open()):
		return
	_bag_open = not _bag_open
	_bag_panel.visible = _bag_open
	get_tree().paused = _bag_open
	if _bag_open:
		_clamp_cursor()
	refresh()


func _bag_key(code: int) -> void:
	match code:
		KEY_UP, KEY_W:
			_cursor -= 1
			_clamp_cursor()
			refresh()
		KEY_DOWN, KEY_S:
			_cursor += 1
			_clamp_cursor()
			refresh()
		KEY_J, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_use_cursor()


## J：光标在装备槽上 = 卸下；在背包行上 = 穿上（同部位自动替换，换下来的回背包）
func _use_cursor() -> void:
	var slots: int = ItemData.SLOT_IDS.size()
	if _cursor < slots:
		PlayerState.unequip(ItemData.SLOT_IDS[_cursor])
	else:
		var idx := _cursor - slots
		if idx < PlayerState.bag.size():
			PlayerState.equip(str(PlayerState.bag[idx]))
	_clamp_cursor()
	refresh()


## 光标范围 = 四个槽 + 整个背包。背包空时也允许落在槽上（不然没法卸装备）
func _clamp_cursor() -> void:
	var total: int = ItemData.SLOT_IDS.size() + PlayerState.bag.size()
	_cursor = clampi(_cursor, 0, maxi(total - 1, 0))


func _pause_menu_open() -> bool:
	var pm := _player.get_node_or_null("PauseMenu")
	return pm != null and pm.has_method("is_open") and bool(pm.call("is_open"))


func _dialogue_open() -> bool:
	var box := get_tree().get_first_node_in_group("dialogue_box")
	return box != null and bool(box.call("is_open"))


func refresh_bag() -> void:
	if not _bag_open:
		return
	_bag_title.text = tr("UI_BAG_TITLE")
	_bag_hint.text = tr("UI_BAG_HINT")
	var dim := Color(0.62, 0.6, 0.55, 1)
	var normal := Color(0.9, 0.88, 0.84, 1)

	# 上半：四个装备槽 —— 每行 [图标][槽位名　装备名　词条]
	var eq := PlayerState.equipped_list()
	for i in ItemData.SLOT_IDS.size():
		var sel := _cursor == i
		_fill_equip_row(_equip_rows[i], i, eq[i] as ItemData, CURSOR_MARK if sel else INDENT)
		if sel:
			_row_label(_equip_rows[i]).modulate = Color(1, 1, 1, 1)

	# 下半：背包列表（一屏 BAG_ROWS 行，随光标滚动）
	var bag := PlayerState.bag
	var top := _scroll_top(bag.size())
	for r in BAG_ROWS:
		var row := _bag_rows[r]
		var icon := _row_icon(row)
		var lbl := _row_label(row)
		var idx := top + r
		if idx >= bag.size():
			# 空状态要可见：整个背包空着才写「（空）」，否则留空行
			icon.visible = false
			lbl.text = tr("UI_BAG_EMPTY") if (bag.is_empty() and r == 0) else ""
			lbl.modulate = dim
			continue
		var it := load(str(bag[idx])) as ItemData
		var row_sel := (_cursor - ItemData.SLOT_IDS.size()) == idx
		icon.visible = true
		icon.set_item(it)
		lbl.text = "%s%s　%s" % [
			CURSOR_MARK if row_sel else INDENT,
			_item_name(it) if it != null else "?",
			_stat_text(it) if it != null else "",
		]
		lbl.modulate = Color(1, 1, 1, 1) if row_sel else normal


## 让光标始终落在可见的 6 行里
func _scroll_top(count: int) -> int:
	if count <= BAG_ROWS:
		return 0
	var idx: int = _cursor - ItemData.SLOT_IDS.size()
	if idx < 0:
		return 0
	if idx < BAG_ROWS:
		return 0
	var top := idx - BAG_ROWS + 1
	return clampi(top, 0, maxi(count - BAG_ROWS, 0))


## 装备名（稀有件加星）—— 名字用文字体现品质，颜色留给列表状态
func _item_name(it: ItemData) -> String:
	if it == null:
		return "?"
	var n := tr(it.name_key)
	return n + " ★" if it.tier == ItemData.Tier.RARE else n


## 一件装备的词条文本：「攻+15%　血+20」。三条都为 0 时给「—」，不显示空白
func _stat_text(it: ItemData) -> String:
	if it == null:
		return ""
	var parts: Array[String] = []
	if not is_zero_approx(it.atk_bonus):
		parts.append("%s+%d%%" % [tr("STAT_ATK"), int(round(it.atk_bonus * 100.0))])
	if it.hp_bonus != 0:
		parts.append("%s+%d" % [tr("STAT_HP"), it.hp_bonus])
	if not is_zero_approx(it.def_bonus):
		parts.append("%s+%d%%" % [tr("STAT_DEF"), int(round(it.def_bonus * 100.0))])
	return "—" if parts.is_empty() else "　".join(parts)


# ─────────────────────────────────────────────────────────────

func refresh() -> void:
	if not _has_player or _player == null or not is_instance_valid(_player):
		return
	var h := _player.get_node("Health") as Health
	var level := int(_player.get("level"))
	var exp_pts := int(_player.get("exp_pts"))
	var mp := int(_player.get("mp"))
	var max_mp := int(_player.get("max_mp"))
	var needed: int = PlayerState.exp_needed(level)

	if h != null:
		_hp_fill.scale.x = clampf(h.ratio(), 0.0, 1.0)
	_mp_fill.scale.x = 0.0 if max_mp <= 0 else clampf(float(mp) / float(max_mp), 0.0, 1.0)
	_exp_fill.scale.x = clampf(float(exp_pts) / float(needed), 0.0, 1.0)
	_lv_label.text = "Lv.%d" % level
	_bag_label.text = "%s ×%d" % [tr("HUD_SHARD"), int(_player.get("shards"))]

	refresh_skill_bar()

	if _panel.visible:
		refresh_char_panel(h)
	if _bag_open:
		refresh_bag()


## 角色面板：造梦西游式属性表，一行一项。数值全部来自「当前生效值」，
## 不是来自某一个来源 —— 玩家在这儿看到的攻击加成必须等于实际打到怪身上的倍率
func refresh_char_panel(h: Health) -> void:
	var level := int(_player.get("level"))
	var exp_pts := int(_player.get("exp_pts"))
	var mp := int(_player.get("mp"))
	var max_mp := int(_player.get("max_mp"))
	var hp := 0 if h == null else h.hp
	var max_hp := 0 if h == null else h.max_hp
	var dmg: float = _player.get_node("Hitbox").damage_scale
	var red: float = 0.0 if h == null else h.damage_reduction
	var lines: Array[String] = [
		"%s %d" % [tr("PANEL_LEVEL"), level],
		"%s %d / %d" % [tr("PANEL_EXP"), exp_pts, PlayerState.exp_needed(level)],
		"%s %d / %d" % [tr("PANEL_HP"), hp, max_hp],
		"%s %d / %d" % [tr("PANEL_MP"), mp, max_mp],
		"%s +%d%%" % [tr("PANEL_ATK"), int(round((dmg - 1.0) * 100.0))],
		"%s -%d%%" % [tr("PANEL_DEF"), int(round(red * 100.0))],
		# 这里曾经写成 tr("PANEL_SHARD") —— csv 里没有这个 key，于是界面上
		# 直接显示 "PANEL_SHARD" 四个字，而且**不报任何错**。
		# 漏翻 / 拼错 key 一律静默，只能靠截图或断言抓（截图抓到了）
		"%s ×%d" % [tr("HUD_SHARD"), shards_of()],
		"%s Lv.%d" % [tr("PANEL_WEAPON"), int(_player.get("upgrade_level"))],
	]
	_panel_text.text = "\n".join(lines)
	# 装备四行带图标 —— 与背包面板同一个填法、同一套图标、同一个品质色
	for i in ItemData.SLOT_IDS.size():
		_fill_equip_row(_char_equip_rows[i], i, PlayerState.item_at(ItemData.SLOT_IDS[i]), "")


## 技能栏：冷却遮罩从满格缩到无（造梦西游式），蓝不足时图标变暗
func refresh_skill_bar() -> void:
	var skill = _player.get("skill")
	if skill == null:
		_skill_cd.visible = false
		return
	var cd := int(_player.get("skill_cooldown"))
	var total: int = skill.total_frames() + skill.cooldown_frames
	var mp := int(_player.get("mp"))
	var need: int = skill.mp_cost
	var no_mp: bool = mp < need
	if cd > 0:
		_skill_cd.visible = true
		_skill_cd.scale.y = clampf(float(cd) / float(total), 0.05, 1.0)
	else:
		_skill_cd.visible = false
	var dim := 0.45 if no_mp else 1.0
	_skill_icon.modulate = Color(dim, dim, dim, 1.0)
	_skill_core.modulate = Color(dim, dim, dim, 1.0)


func shards_of() -> int:
	return int(_player.get("shards")) if _player != null and is_instance_valid(_player) else 0
