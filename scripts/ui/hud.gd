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
## 技能栏的 5 个格子（代码建的 Panel，里面是图标 / 冷却遮罩 / 键位角标）
var _skill_cells: Array = []

var _skill_open := false
var _skill_cursor := 0
## 技能面板的行（每个技能一行：图标 + 名字 + 装在哪个槽）
var _skill_rows: Array = []
## 父节点是不是玩家。HUD 只在玩家身上工作 —— 被单独实例化（场景完整性检查器
## 就是这么干的）时不能崩，否则每一次校验都带一堆假报错
var _has_player := false

@onready var _player: Node = get_parent()
@onready var _hp_fill: ColorRect = $Status/HPBar/Fill
@onready var _mp_fill: ColorRect = $Status/MPBar/Fill
## 血条蓝条上的数值。**条本身说不清"还剩多少够不够挨这一下"** ——
## 玩家要的是数字，条只是"一眼看出比例"。两者缺一不可
@onready var _hp_text: Label = $Status/HPText
@onready var _mp_text: Label = $Status/MPText
## 经验条从「屏幕最底边的全屏细条」改成「角色头像外圈的环」——
## 底部那条永远在视野边缘，战斗中没人会去读它
@onready var _portrait: PortraitRing = $Portrait
@onready var _lv_label: Label = $Status/Level
@onready var _bag_label: Label = $Bag/Count
## 「砺场 · 第 2 段 / 共 3 段」。一屏一屏推进时玩家要随时知道自己推进到哪了 ——
## 这是三层结构带来的新信息，HUD 上不写就只能靠舆图反复确认
@onready var _stage_label: Label = $Stage
@onready var _panel: Panel = $CharPanel
@onready var _panel_text: Label = $CharPanel/Text
@onready var _char_equip_box: VBoxContainer = $CharPanel/EquipRows
@onready var _skill_bar: HBoxContainer = $SkillBar
@onready var _bag_panel: Panel = $BagPanel
@onready var _bag_title: Label = $BagPanel/Title
@onready var _equip_box: VBoxContainer = $BagPanel/EquipRows
@onready var _rows_box: VBoxContainer = $BagPanel/Rows
@onready var _bag_hint: Label = $BagPanel/Hint
@onready var _skill_panel: Panel = $SkillPanel
@onready var _skill_title: Label = $SkillPanel/Title
@onready var _skill_box: VBoxContainer = $SkillPanel/Rows
@onready var _skill_status: Label = $SkillPanel/Status
@onready var _skill_hint: Label = $SkillPanel/Hint


func _ready() -> void:
	_has_player = _player != null and _player.is_in_group("player")
	_panel.visible = false
	_bag_panel.visible = false
	_skill_panel.visible = false
	_build_rows()
	_build_skill_bar()
	_build_skill_panel()
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
	if event.is_action_pressed("skill_panel"):
		toggle_skill_panel()
		return
	# 面板打开时才接管方向键 / J —— 平时它们该归战斗
	if _bag_open:
		if event is InputEventKey and event.pressed and not event.echo:
			_bag_key((event as InputEventKey).keycode)
		return
	if _skill_open:
		if event is InputEventKey and event.pressed and not event.echo:
			_skill_key((event as InputEventKey).keycode)


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


## 造一行：图标 + 文字。图标按部位画形状、按品质上色，与地上掉落物同一套。
## as_skill = true 时用技能图标（技能面板的行）
func _make_row(parent: Node, row_height: float = ROW_HEIGHT, as_skill: bool = false) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(0.0, row_height)
	box.add_theme_constant_override("separation", 3)

	var icon: Control = SkillIcon.new() if as_skill else ItemIcon.new()
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
## 参数是**实例 uid**（不是 ItemData）—— 强化等级挂在 uid 上，
## 只拿 ItemData 就说不清「这一件练到几级了」
func _fill_equip_row(row: HBoxContainer, i: int, uid: String, mark: String) -> void:
	var icon := _row_icon(row)
	var lbl := _row_label(row)
	var it := PlayerState.item_of(uid)
	icon.empty_frame = true          # 空槽画一个空框，不留白（空状态也要可见）
	icon.set_item(it)
	var slot_name: String = tr(String(ItemData.SLOT_KEYS[i]))
	if it == null:
		lbl.text = "%s%s　%s" % [mark, slot_name, tr("UI_BAG_EMPTY")]
		lbl.modulate = Color(0.62, 0.6, 0.55, 1)
	else:
		lbl.text = "%s%s　%s　%s" % [mark, slot_name, _item_name(it), _stat_text(uid, it)]
		lbl.modulate = Color(0.9, 0.88, 0.84, 1)


## 技能栏：5 个格子，同样由代码建。每格 = 图标 + 冷却遮罩 + 键位角标。
## 格子的名字（Cell1..Cell5）被断言用着，改名字要连着改 tests/test_m4
##
## ── 尺寸为什么这么小 ──────────────────────────────────────
## 一版是 54×40，五个格子连起来横跨 286px（640 宽屏幕的 45%），
## 压在左下角把地面和怪都盖住了。收到 40×30 之后横向只占 212px（33%），
## 高度也矮了一截 —— 底部本来就该是场景，不是面板。
func _build_skill_bar() -> void:
	for i in PlayerState.SKILL_SLOT_COUNT:
		var cell := Panel.new()
		cell.name = "Cell%d" % (i + 1)
		cell.custom_minimum_size = Vector2(40.0, 30.0)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 代码建的 Panel 默认是主题那套浅灰底，和 HUD 其他面板格格不入 ——
		# 手上一块深底 + 暗金边，风格才连得上。底色比面板更透一点：
		# 它压在场景上，太实会挡住地面的地形
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.11, 0.11, 0.14, 0.86)
		sb.border_color = Color(0.4, 0.35, 0.26, 1.0)
		sb.set_border_width_all(1)
		cell.add_theme_stylebox_override("panel", sb)

		var icon := SkillIcon.new()
		icon.name = "Icon"
		icon.position = Vector2(5.0, 3.0)
		icon.size = Vector2(30.0, 20.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)

		# 冷却遮罩：顶边固定、底边上升（造梦西游式）。ColorRect 的 pivot 默认在左上，
		# 所以缩 scale.y 就是「从满格缩到无」
		var cd := ColorRect.new()
		cd.name = "Cooldown"
		cd.color = Color(0.05, 0.05, 0.08, 0.75)
		cd.position = Vector2(5.0, 3.0)
		cd.size = Vector2(30.0, 20.0)
		cd.visible = false
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(cd)

		var key := Label.new()
		key.name = "Key"
		key.position = Vector2(24.0, 16.0)
		key.size = Vector2(14.0, 12.0)
		key.text = "%d" % (i + 1)
		key.add_theme_font_size_override("font_size", 9)
		key.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(key)

		_skill_bar.add_child(cell)
		_skill_cells.append(cell)


func _row_icon(row: HBoxContainer) -> ItemIcon:
	return row.get_child(0) as ItemIcon


func _row_label(row: HBoxContainer) -> Label:
	return row.get_child(1) as Label


func _row_skill_icon(row: HBoxContainer) -> SkillIcon:
	return row.get_child(0) as SkillIcon


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
	# 暂停菜单 / 对话框 / 舆图 / 死亡界面开着时不叠背包：几个界面都要抢 Esc / B / J，
	# 叠起来只会互相打架
	if not _bag_open \
			and (_pause_menu_open() or _dialogue_open() or _atlas_open() or _death_open()):
		return
	if not _bag_open and _skill_open:
		toggle_skill_panel()            # 背包和技能面板同类，开的那个让位
	_bag_open = not _bag_open
	_bag_panel.visible = _bag_open
	get_tree().paused = _bag_open
	if _bag_open:
		_clamp_cursor()
	refresh()


func is_skill_panel_open() -> bool:
	return _skill_open


## 技能面板（V）：列技能池，把想带的装进 5 个槽。
## 与背包面板同一套机制：打开即暂停、操作类界面、共用一个光标
func toggle_skill_panel() -> void:
	if not _skill_open \
			and (_pause_menu_open() or _dialogue_open() or _atlas_open() or _death_open()):
		return
	if not _skill_open and _bag_open:
		toggle_bag()
	_skill_open = not _skill_open
	_skill_panel.visible = _skill_open
	get_tree().paused = _skill_open
	if _skill_open:
		_skill_cursor = clampi(_skill_cursor, 0, maxi(_pool().size() - 1, 0))
	refresh()


func _pool() -> Array:
	if not _has_player or _player == null or not is_instance_valid(_player):
		return []
	return _player.call("skill_pool_paths")


func _skill_key(code: int) -> void:
	var n := _pool().size()
	match code:
		KEY_UP, KEY_W:
			_skill_cursor = clampi(_skill_cursor - 1, 0, maxi(n - 1, 0))
			refresh()
		KEY_DOWN, KEY_S:
			_skill_cursor = clampi(_skill_cursor + 1, 0, maxi(n - 1, 0))
			refresh()
		KEY_J, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_toggle_skill_at_cursor()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_assign_skill_to_slot(code - KEY_1)
		KEY_0:
			_unequip_skill_at_cursor()


## J：没带就装进第一个空槽；已经带着就摘下来。
## **未解锁的技能不许装** —— 与数字键装槽同一扇门（黑盒验收抓到的漏网之鱼：
## 数字键有检查、J 没有，于是面板里灰色的「未解锁」其实装得上）
func _toggle_skill_at_cursor() -> void:
	var pool := _pool()
	if _skill_cursor < 0 or _skill_cursor >= pool.size():
		return
	var path := str(pool[_skill_cursor])
	if PlayerState.carries(path):
		PlayerState.clear_skill_slot_by_path(path)
		refresh()
		return
	if not _player.call("is_skill_unlocked", path):
		return                          # 未解锁：不装、不报错，灰色就是它的状态
	var free := PlayerState.skill_slots.find("")
	if free < 0:
		return                      # 5 格满了：先按 0 摘一个，否则不给装
	PlayerState.set_skill_slot(free, path)
	refresh()


## 数字键：把光标那一个装到指定的槽（覆盖原来那格的内容）
func _assign_skill_to_slot(slot: int) -> void:
	var pool := _pool()
	if _skill_cursor < 0 or _skill_cursor >= pool.size():
		return
	var path := str(pool[_skill_cursor])
	if not _player.call("is_skill_unlocked", path):
		return                          # 没解锁的技能不许带
	PlayerState.set_skill_slot(slot, path)
	refresh()


func _unequip_skill_at_cursor() -> void:
	var pool := _pool()
	if _skill_cursor < 0 or _skill_cursor >= pool.size():
		return
	PlayerState.clear_skill_slot_by_path(str(pool[_skill_cursor]))
	refresh()


## 技能面板：一行一个技能 —— [图标][名字][装在几号槽]
func refresh_skill_panel() -> void:
	if not _skill_open:
		return
	_skill_title.text = tr("UI_SKILL_TITLE")
	_skill_hint.text = tr("UI_SKILL_HINT")
	var pool := _pool()
	var carrying := 0
	for i in PlayerState.skill_slots.size():
		if str(PlayerState.skill_slots[i]) != "":
			carrying += 1
	_skill_status.text = "%s %d/%d" % [tr("UI_SKILL_CARRY"), carrying, PlayerState.SKILL_SLOT_COUNT]

	for i in _skill_rows.size():
		var row: HBoxContainer = _skill_rows[i]
		var icon := _row_skill_icon(row)
		var lbl := _row_label(row)
		if i >= pool.size():
			icon.visible = false
			lbl.text = ""
			continue
		var path := str(pool[i])
		var sk := load(path) as SkillData
		var unlocked: bool = bool(_player.call("is_skill_unlocked", path))
		var slot := PlayerState.skill_slots.find(path)
		var sel := i == _skill_cursor
		icon.visible = true
		icon.set_skill(sk)
		icon.dim = not unlocked
		var slot_txt := ("[%d]" % (slot + 1)) if slot >= 0 else ""
		var name := tr(sk.name_key) if sk != null else "?"
		if not unlocked:
			lbl.text = "%s%s  %s" % [
				CURSOR_MARK if sel else INDENT, tr("UI_SKILL_LOCKED"), name]
			lbl.modulate = Color(0.5, 0.48, 0.45, 1)
		else:
			lbl.text = "%s%s  %s" % [CURSOR_MARK if sel else INDENT, name, slot_txt]
			lbl.modulate = Color(1, 1, 1, 1) if sel else Color(0.88, 0.86, 0.82, 1)


## 技能面板的行由代码建（技能池有几个就建几行）
func _build_skill_panel() -> void:
	var n: int = _pool().size()
	for _i in n:
		_skill_rows.append(_make_row(_skill_box, CHAR_ROW_HEIGHT, true))


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
		KEY_K:
			_sell_cursor()


## J：光标在装备槽上 = 卸下；在背包行上 = 穿上（同部位自动替换，换下来的回背包）
## K：光标在背包行上 = 出售换元宝。**只收背包件** ——
## 穿在身上的先卸下再来，「一个按键卖掉正在穿的甲」不该是可能发生的事故
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


## 出售光标那件背包装备（K）。卖价 = 定价 × 折价率，算法住在 PlayerState.sell_item
## （它经手元宝与背包两张表）。卖成了响一声；卖不了（光标在装备槽上 / 背包空）不说废话
## —— 光标位置本身就是原因，装备槽行上根本没有「卖」这个动作
func _sell_cursor() -> void:
	var idx := _cursor - ItemData.SLOT_IDS.size()
	if idx < 0 or idx >= PlayerState.bag.size():
		return
	var uid := str(PlayerState.bag[idx])
	if PlayerState.sell_item(uid) > 0:
		Audio.play(&"pickup")
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


## 舆图开着时也一样让路。它挂在玩家身上（和本节点平级），所以直接从父节点找
func _atlas_open() -> bool:
	if _player == null:
		return false
	var at := _player.get_node_or_null("Atlas")
	return at != null and at.has_method("is_open") and bool(at.call("is_open"))


## 死亡界面开着时也让路。死亡界面自己会先调 close_all_panels() 把本节点的面板收掉，
## 这一条是**兜底**：任何路径下都不该出现"人已经躺下了，背包还摊在脸上"
func _death_open() -> bool:
	if _player == null:
		return false
	var dm := _player.get_node_or_null("DeathMenu")
	return dm != null and dm.has_method("is_open") and bool(dm.call("is_open"))


## 把本节点上开着的面板全收掉（别的模态界面开之前调它让路）。
##
## **这里刻意不碰 `paused`。** 早先的版本顺手写了一句 `get_tree().paused = false`，
## 理由是「面板的可见性与 paused 是一起管的」。那是个陷阱：调用方是「我要开一个新界面」，
## 它自然会在自己那边设 `paused = true` —— 于是成败取决于两行的先后顺序。
## 死亡界面侥幸写对了（先让路、后设暂停），铁匠铺（2026-09-14 加）写反了顺序，
## 结果面板开着、游戏还在跑，只有拿帧号打点才看得出来。
## 现在职责划清：本方法只管可见性，暂停归调用方
func close_all_panels() -> void:
	if _bag_open:
		_bag_open = false
		_bag_panel.visible = false
	if _skill_open:
		_skill_open = false
		_skill_panel.visible = false


func refresh_bag() -> void:
	if not _bag_open:
		return
	_bag_title.text = tr("UI_BAG_TITLE")
	# 键位提示 + 余额：卖东西要看钱进了没有，两笔钱都摆在这行里
	_bag_hint.text = "%s　·　%s　·　%s ×%d　%s ×%d" % [
		tr("UI_BAG_HINT"), tr("UI_BAG_SELL"),
		tr("HUD_GOLD"), PlayerState.gold, tr("HUD_SHARD"), PlayerState.shards]
	var dim := Color(0.62, 0.6, 0.55, 1)
	var normal := Color(0.9, 0.88, 0.84, 1)

	# 上半：四个装备槽 —— 每行 [图标][槽位名　装备名　词条]
	for i in ItemData.SLOT_IDS.size():
		var sel := _cursor == i
		_fill_equip_row(_equip_rows[i], i, PlayerState.equipped_uid(ItemData.SLOT_IDS[i]),
			CURSOR_MARK if sel else INDENT)
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
		var uid := str(bag[idx])
		var it := PlayerState.item_of(uid)
		var row_sel := (_cursor - ItemData.SLOT_IDS.size()) == idx
		icon.visible = true
		icon.set_item(it)
		lbl.text = "%s%s　%s" % [
			CURSOR_MARK if row_sel else INDENT,
			_item_name(it) if it != null else "?",
			_stat_text(uid, it) if it != null else "",
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


## 一件装备的词条文本：「+2　攻+38%　血+20」。
## **攻击那一项算的是「基础词条 + 强化」的合计** —— 设计原则 4.1 要求面板上的
## 加成必须等于实际打出的倍率；强化既然在打怪时生效，就必须在面板上出现，
## 开头的 `+N` 是它的来源标注。什么都没给时是「—」，不显示空白
func _stat_text(uid: String, it: ItemData) -> String:
	if it == null:
		return ""
	var parts: Array[String] = []
	var lv := PlayerState.forge_level(uid)
	var atk := it.atk_bonus + PlayerState.forge_atk(uid)
	if lv > 0:
		parts.append("+%d" % lv)
	if not is_zero_approx(atk):
		parts.append("%s+%d%%" % [tr("STAT_ATK"), int(round(atk * 100.0))])
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
		_hp_text.text = "%d / %d" % [h.hp, h.max_hp]
	_mp_fill.scale.x = 0.0 if max_mp <= 0 else clampf(float(mp) / float(max_mp), 0.0, 1.0)
	_mp_text.text = "%d / %d" % [mp, max_mp]
	# 满级时 needed = 0 —— 环填满，不是除零。除零会得到 NaN，环整个会消失
	_portrait.set_exp(1.0 if needed <= 0 else float(exp_pts) / float(needed))
	# 等级带上限：等级是「解锁内容的钥匙」，玩家得看得见离顶还有多远
	_lv_label.text = "Lv.%d/%d" % [level, PlayerState.level_cap]
	# 两笔钱都常驻：元宝（商店）/ 精铁（强化）。经济两条管道，玩家随时都得看得见余额
	_bag_label.text = "%s ×%d　%s ×%d" % [
		tr("HUD_GOLD"), PlayerState.gold, tr("HUD_SHARD"), PlayerState.shards]

	refresh_skill_bar()
	refresh_stage_label()

	if _panel.visible:
		refresh_char_panel(h)
	if _bag_open:
		refresh_bag()
	if _skill_open:
		refresh_skill_panel()


## 屏号（「砺场 · 第 2 屏 / 共 3 屏」）。
##
## 来源是**玩家所在的那个关卡节点**（它是副本场景的根）——
## 不从这个副本数据直接取，因为「第几屏」是**动态**的：玩家走到哪一屏，
## 这个数字就跟着变。关卡根节点是唯一知道这件事的人。
##
## 没有副本数据的场景（测试房间、还没重切的 `level_2/3`）这一行是空的，
## 而不是显示一个假的屏号。文本没变就不写回：这是每帧都在跑的刷新
func refresh_stage_label() -> void:
	var host: Node = _player.get_parent() if _player != null else null
	var txt := ""
	if host != null and host.has_method("current_screen") and host.has_method("screen_count"):
		var total: int = host.call("screen_count")
		var d: DungeonData = host.get("dungeon_data") as DungeonData
		if total > 0 and d != null:
			txt = "%s · %s / %s" % [
				tr(d.name_key),
				I18n.t(&"UI_SCREEN_LABEL", [host.call("current_screen")]),
				I18n.t(&"UI_SCREEN_TOTAL", [total])]
	if _stage_label.text != txt:
		_stage_label.text = txt


## 角色面板的「武器强化」那一行。
## 逐件强化之后，强化不再是玩家身上的一个数字，而是**当前那把武器**的数字 ——
## 没拿武器就写「—」，不要拿一个 0 假装有
func _weapon_forge_line() -> String:
	var uid := PlayerState.equipped_uid(&"weapon")
	if uid.is_empty():
		return "%s —" % tr("PANEL_WEAPON")
	return "%s +%d/%d" % [
		tr("PANEL_WEAPON"), PlayerState.forge_level(uid), PlayerState.forge_max(uid)]


## 经验那一行。满级时写「已满」而不是「0 / 0」——
## 后者会被读成「经验全丢了」，而实际上是「不需要了」
func _exp_line(level: int, exp_pts: int) -> String:
	if PlayerState.progression.is_max(level):
		return "%s %s" % [tr("PANEL_EXP"), tr("UI_EXP_MAX")]
	return "%s %d / %d" % [tr("PANEL_EXP"), exp_pts, PlayerState.exp_needed(level)]


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
		"%s %d / %d" % [tr("PANEL_LEVEL"), level, PlayerState.level_cap],
		_exp_line(level, exp_pts),
		"%s %d / %d" % [tr("PANEL_HP"), hp, max_hp],
		"%s %d / %d" % [tr("PANEL_MP"), mp, max_mp],
		"%s +%d%%" % [tr("PANEL_ATK"), int(round((dmg - 1.0) * 100.0))],
		"%s -%d%%" % [tr("PANEL_DEF"), int(round(red * 100.0))],
		# 这里曾经写成 tr("PANEL_SHARD") —— csv 里没有这个 key，于是界面上
		# 直接显示 "PANEL_SHARD" 四个字，而且**不报任何错**。
		# 漏翻 / 拼错 key 一律静默，只能靠截图或断言抓（截图抓到了）
		"%s ×%d" % [tr("HUD_SHARD"), shards_of()],
		_weapon_forge_line(),
	]
	_panel_text.text = "\n".join(lines)
	# 装备四行带图标 —— 与背包面板同一个填法、同一套图标、同一个品质色
	for i in ItemData.SLOT_IDS.size():
		_fill_equip_row(_char_equip_rows[i], i, PlayerState.equipped_uid(ItemData.SLOT_IDS[i]), "")


## 技能栏：5 格各显各的技能。冷却遮罩从满格缩到无（造梦西游式），
## 蓝不够或空槽时图标变暗 —— 「现在放不出来」要一眼看得出，不弹提示
func refresh_skill_bar() -> void:
	var slots: int = PlayerState.SKILL_SLOT_COUNT
	var mp := int(_player.get("mp"))
	var lefts: Array = _player.get("skill_cooldowns")
	for i in slots:
		if i >= _skill_cells.size():
			break
		var cell: Panel = _skill_cells[i]
		var icon := cell.get_node_or_null("Icon") as SkillIcon
		var cd := cell.get_node_or_null("Cooldown") as ColorRect
		if icon == null or cd == null:
			continue
		var sk := _player.call("skill_in_slot", i) as SkillData
		icon.set_skill(sk)
		var usable := sk != null and mp >= sk.mp_cost
		icon.dim = not usable
		var left := int(lefts[i]) if i < lefts.size() else 0
		if left > 0 and sk != null:
			cd.visible = true
			var total: int = sk.total_frames() + sk.cooldown_frames
			cd.scale.y = clampf(float(left) / float(maxi(total, 1)), 0.05, 1.0)
		else:
			cd.visible = false


## 精铁数量。**只认 PlayerState 那一份** —— 玩家节点上没有第二份
## （曾经有，代价是「强化扣了钱、HUD 还显示旧数」，截图抓到的）
func shards_of() -> int:
	return PlayerState.shards
