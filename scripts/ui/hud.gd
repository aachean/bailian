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

## 背包格子网格：**2 行 × 6 列 = 12 格**（2026-09-18 神圈注定形：一栏文字行太挤，
## 改成格子）。超出 12 件靠光标滚动翻页。
const BAG_COLS := 6
const BAG_GRID_ROWS := 5
## 背包格子边长（图标 16 + 内边距）。2 行 × 34 = 68，正好放进面板的格子区
const BAG_CELL := 36.0
const CURSOR_MARK := "▶ "
const INDENT := "   "
## 装备槽行的高度（面板上半，8 行）
const ROW_HEIGHT := 17.0
const ICON_SIZE := 16.0
const CHAR_ROW_HEIGHT := 17.0    # 角色面板一行（与背包面板同高，两处行高必须一样）

var _bag_open := false
## 背包面板的提示消息（穿不上武器之类）—— 带过期时刻，2.4 秒后回常规提示
var _bag_msg := ""
var _bag_msg_until := 0
var _cursor := 0                 # 全面板共用一个光标：0..7 是装备槽，之后是背包
var _equip_rows: Array[HBoxContainer] = []
## 背包格子（2×6）：每格 = 底板（选中高亮）+ 图标。底板颜色就是选中态
var _bag_cells: Array[Panel] = []
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
## 角色属性块（B 面板左栏顶部）。**C 键面板已并入这里**（2026-09-18 神裁定：
## 不需要按 C，按 B 一键看全部）—— 一个面板一个键，信息不再拆两处
@onready var _stats_l: Label = $BagPanel/StatsL
@onready var _stats_r: Label = $BagPanel/StatsR
@onready var _skill_bar: HBoxContainer = $SkillBar
@onready var _bag_panel: Panel = $BagPanel
@onready var _bag_title: Label = $BagPanel/Title
@onready var _equip_box: VBoxContainer = $BagPanel/EquipRows
@onready var _bag_grid: GridContainer = $BagPanel/BagGrid
@onready var _bag_empty: Label = $BagPanel/BagEmpty
@onready var _detail_name: Label = $BagPanel/DetailName
@onready var _detail_text: Label = $BagPanel/DetailText
@onready var _mat_row: Label = $BagPanel/MatRow
@onready var _bag_hint: Label = $BagPanel/Hint
@onready var _skill_panel: Panel = $SkillPanel
@onready var _skill_title: Label = $SkillPanel/Title
@onready var _skill_box: VBoxContainer = $SkillPanel/Rows
@onready var _skill_status: Label = $SkillPanel/Status
@onready var _skill_hint: Label = $SkillPanel/Hint


func _ready() -> void:
	_has_player = _player != null and _player.is_in_group("player")
	_bag_panel.visible = false
	_skill_panel.visible = false
	_build_rows()
	_build_skill_bar()
	_build_skill_panel()
	_apply_portrait()
	# 面板行重建（重活）改由信号驱动，不再每帧轮询：装备/技能变了才重建对应面板。
	# 连续量（血蓝条 / 经验 / 冷却 / 材料数）仍走 _process 的 _refresh_status（见文件头轮询理由）
	PlayerState.equipment_changed.connect(_on_equipment_changed)
	PlayerState.skills_changed.connect(_on_skills_changed)
	refresh()


## 头像跟随角色：有立绘（sprite_dir 非空）画照片，否则维持程序化小人。
## 「左上角那个人必须和屏幕中央那个人长得一样」—— 色块时代靠同色，现在靠同图
func _apply_portrait() -> void:
	var def := PlayerState.character_def()
	if def != null and not def.sprite_dir.is_empty():
		var path := def.sprite_dir + "/portrait.png"
		if not ResourceLoader.exists(path):
			path = def.sprite_dir + "/idle_0.png"   # 没立绘就用站姿第一帧顶上
		if ResourceLoader.exists(path):
			_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_portrait.set_face_texture(load(path))


func _process(_delta: float) -> void:
	_refresh_status()      # 每帧只刷连续量；面板行重建走信号（见 _ready）


func _unhandled_input(event: InputEvent) -> void:
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
	# 鼠标：装备槽行与背包格都收左键点击（子节点仍 IGNORE，点击穿到行/格上）。
	# 穿/卸装备是廉价可逆的 → **单击即生效**（分级点击的「便宜」档，见 _click_* ）。
	# 连一次即可 —— 行/格是建好复用的
	for i in ItemData.SLOT_IDS.size():
		var row := _make_row(_equip_box)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(_on_equip_row_gui_input.bind(i))
		_equip_rows.append(row)
	for k in BAG_COLS * BAG_GRID_ROWS:
		var cell := _make_bag_cell()
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.gui_input.connect(_on_bag_cell_gui_input.bind(k))
		_bag_cells.append(cell)


## 造一个背包格子：底板（颜色 = 选中态）+ 居中图标。
## 格子里**不放文字** —— 名字与词条在格网下方的详情行（选中的那格才有）
func _make_bag_cell() -> Panel:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(BAG_CELL, BAG_CELL)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.name = "BG"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.14, 0.14, 0.17, 1)
	cell.add_child(bg)
	var icon := ItemIcon.new()
	# **手动居中，别用 anchors preset** —— GridContainer 的子 Panel 还没进树时
	# size 是 0，PRESET_CENTER 算出的 offset 是 0，图标就从中心点向右下歪出去
	# （2026-09-18 神截图圈注的「偏右下角」就是它）
	icon.position = Vector2((BAG_CELL - ICON_SIZE) * 0.5, (BAG_CELL - ICON_SIZE) * 0.5)  # = 10,10
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	_bag_grid.add_child(cell)
	return cell


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
## 压在左下角把地面和怪都盖住了（神实测反馈「挡视野」）。
## 2026-09-18 加了 2 个消耗品格（5+2 = 7 格）之后，**格子从 40 收到 32、间距 3 收到 2**：
## 7×32 + 6×2 = **236px**，仍然在「技能栏横向不超过屏幕 40%（240px @640）」这条线以内。
##
## **图标本身没有变小**：SkillIcon / ItemIcon 都是照 16×16 的设计盒画的，
## 缩放系数取 `min(宽,高)/16` —— 在 30×20 的框里 k = 1.25，画出来只占 18px 宽；
## 框收到 24×20 之后 k 仍是 1.25，画出来一模一样。**真正只有格子窄了。**
##
## 想加第 8 格的人先算这条账：236 + 34 = 270px，那就超线了。
const CELL_SIZE := Vector2(32.0, 30.0)
const CELL_GAP := 2
## 图标框。**高度必须留在 20** —— k 取 min(w,h)/16，高度一掉，
## 七个技能图标会跟着一起缩（那是要改观感的改动，不该顺手带上）
const ICON_BOX := Vector2(24.0, 20.0)
const ICON_POS := Vector2(4.0, 5.0)


func _build_skill_bar() -> void:
	# 间距也从这里定 —— 与 CELL_SIZE 是**同一道宽度预算的两个数**，
	# 一个住代码一个住 .tscn 的话，改了一处就会算出错的宽度（而宽度超了只能靠肉眼发现）
	_skill_bar.add_theme_constant_override("separation", CELL_GAP)
	var total: int = PlayerState.SKILL_SLOT_COUNT + PlayerState.POTION_KINDS.size()
	for i in total:
		var potion_index: int = i - PlayerState.SKILL_SLOT_COUNT
		var cell := Panel.new()
		cell.name = "Cell%d" % (i + 1)
		cell.custom_minimum_size = CELL_SIZE
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 代码建的 Panel 默认是主题那套浅灰底，和 HUD 其他面板格格不入 ——
		# 手上一块深底 + 暗金边，风格才连得上。底色比面板更透一点：
		# 它压在场景上，太实会挡住地面的地形
		# 技能格：与主面板同族的像素九宫格（原先是代码画的灰方块，和面板两套语言）
		cell.add_theme_stylebox_override("panel", load("res://assets/ui/slot_style.tres"))

		if potion_index >= 0:
			# 消耗品格（栏最后两格）：图标是「符」不是技能，而且它**没有冷却** ——
			# 格子里唯一会变的量是剩余**次数**，所以用计数代替冷却遮罩
			var pot := ItemIcon.new()
			pot.name = "Icon"
			pot.kind = _potion_icon_kind(potion_index)
			pot.empty_frame = true
			pot.position = ICON_POS
			pot.size = ICON_BOX
			pot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(pot)

			var count := Label.new()
			count.name = "Count"
			count.position = Vector2(2.0, 15.0)
			count.size = Vector2(16.0, 14.0)
			count.add_theme_font_size_override("font_size", 10)
			# **数字压在瓶子上**（32px 的格子里没有空角）→ 必须描边，
			# 否则红瓶子上写白数字那一下就糊成一片
			count.add_theme_constant_override("outline_size", 3)
			count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			count.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(count)
		else:
			var icon := SkillIcon.new()
			icon.name = "Icon"
			icon.position = ICON_POS
			icon.size = ICON_BOX
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(icon)

			# 冷却遮罩：顶边固定、底边上升（造梦西游式）。ColorRect 的 pivot 默认在左上，
			# 所以缩 scale.y 就是「从满格缩到无」
			var cd := ColorRect.new()
			cd.name = "Cooldown"
			cd.color = Color(0.05, 0.05, 0.08, 0.75)
			cd.position = ICON_POS
			cd.size = ICON_BOX
			cd.visible = false
			cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(cd)

		var key := Label.new()
		key.name = "Key"
		key.position = Vector2(19.0, 17.0)
		key.size = Vector2(12.0, 12.0)
		key.text = "%d" % (i + 1)
		key.add_theme_font_size_override("font_size", 9)
		key.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(key)

		_skill_bar.add_child(cell)
		_skill_cells.append(cell)


## 第 i 个消耗品格画哪种符。**「6 = 回血符、7 = 回蓝符」的唯一出处是
## `PlayerState.POTION_KINDS`** —— 这里和 `player._try_use_potion` 都从它取，
## 不各写一份顺序（两处顺序一旦不一致，就是「按 6 喝了蓝」那种没人会去查的错）
func _potion_icon_kind(i: int) -> StringName:
	return &"potion_hp" if PlayerState.POTION_KINDS[i] == PlayerState.POTION_HP else &"potion_mp"


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
			# 未解锁要把**条件**说出来（几级能开），不然玩家只能对着灰色瞎猜
			lbl.text = "%s%s  %s" % [
				CURSOR_MARK if sel else INDENT,
				I18n.t(&"UI_SKILL_LOCKED_AT", [sk.unlock_level]) if sk != null else tr("UI_SKILL_LOCKED"),
				name]
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
		# 格子是 6 列网格：←→ 在格子里横着走（装备槽区里没意义但无害 ——
		# 光标不会出界，clamp 兜着）
		KEY_LEFT, KEY_A:
			_cursor -= 1
			_clamp_cursor()
			refresh()
		KEY_RIGHT, KEY_D:
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
			var uid := str(PlayerState.bag[idx])
			var it := PlayerState.item_of(uid)
			# 武器类型不匹配（弓手拿铁剑）：穿上会被拒 —— **必须说出来**，
			# 按了没反应玩家分不清是 bug 还是规则
			if it != null and not PlayerState.can_equip(it):
				_bag_msg = tr("UI_BAG_WRONG_WEAPON") % [tr(it.name_key)]
				_bag_msg_until = Time.get_ticks_msec() + 2400
				refresh()
				return
			PlayerState.equip(uid)
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


## 鼠标点装备槽第 i 行 / 背包第 k 格。只认左键按下；子节点 IGNORE，点击穿到行/格上
func _on_equip_row_gui_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_click_equip_slot(i)


func _on_bag_cell_gui_input(event: InputEvent, k: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_click_bag_cell(k)


## 点装备槽 i → 光标移过去 → **单击即卸下**（等同 J；穿/卸廉价可逆，走「便宜」档）。
## **可被测试直接调**，不依赖真实鼠标。空槽 _use_cursor 自会兜住（unequip 空槽是 no-op）
func _click_equip_slot(i: int) -> void:
	if i < 0 or i >= ItemData.SLOT_IDS.size():
		return
	_cursor = i
	_use_cursor()


## 点背包第 k 格（屏上 0..格数-1）→ 按当前显示页算绝对背包索引 → 光标移过去 → **单击穿上**。
## 点到空格忽略。`_bag_page()` 用的是点击前的 _cursor（= 当前渲染的那一页），所以页号一致
func _click_bag_cell(k: int) -> void:
	var per_page := BAG_COLS * BAG_GRID_ROWS
	var idx := _bag_page() * per_page + k
	if idx < 0 or idx >= PlayerState.bag.size():
		return
	_cursor = ItemData.SLOT_IDS.size() + idx
	_use_cursor()


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
	# 角色属性块（原 C 面板的属性表）每次开背包都跟着刷 —— 一键看全部
	_refresh_stats_block(_player.get_node("Health") as Health)
	_bag_title.text = tr("UI_BAG_TITLE")
	# 提示行两级：出错消息（2.4s）> 常规键位+余额。消息必须说出来，不许静默
	if not _bag_msg.is_empty() and Time.get_ticks_msec() < _bag_msg_until:
		_bag_hint.text = _bag_msg
	else:
		_bag_msg = ""
		# 键位提示。**余额不再重复写在这行**（v2 八槽后面板变长了，这行摆不下）
		# —— 元宝与精铁本来就常驻在 HUD 右上角，卖完钱立刻能看见进账
		_bag_hint.text = "%s　·　%s" % [tr("UI_BAG_HINT"), tr("UI_BAG_SELL")]

	# 上半：四个装备槽 —— 每行 [图标][槽位名　装备名　词条]
	for i in ItemData.SLOT_IDS.size():
		var sel := _cursor == i
		_fill_equip_row(_equip_rows[i], i, PlayerState.equipped_uid(ItemData.SLOT_IDS[i]),
			CURSOR_MARK if sel else INDENT)
		if sel:
			_row_label(_equip_rows[i]).modulate = Color(1, 1, 1, 1)

	# 下半：背包格子（2×6 网格，一页 12 格，超出靠光标翻页）。
	# 格子里只放图标 —— 名字与词条在下方详情行（选中的那格才有），格子里塞文字就是截图里那种挤
	var bag := PlayerState.bag
	var page := _bag_page()
	for r in BAG_GRID_ROWS:
		for c in BAG_COLS:
			var cell := _bag_cells[r * BAG_COLS + c]
			var bg := cell.get_node("BG") as ColorRect
			var icon := cell.get_child(1) as ItemIcon
			var idx := page * (BAG_COLS * BAG_GRID_ROWS) + r * BAG_COLS + c
			var row_sel := (_cursor - ItemData.SLOT_IDS.size()) == idx
			# 选中格：底板提亮 —— 光标在这里一眼可见，不需要再画箭头
			bg.color = Color(0.34, 0.3, 0.18, 1) if row_sel else Color(0.14, 0.14, 0.17, 1)
			if idx >= bag.size():
				icon.visible = false
				continue
			var uid := str(bag[idx])
			var it := PlayerState.item_of(uid)
			icon.visible = true
			icon.set_item(it)
			# **格子上就标出「本角色用不了」**，不能等玩家按 J 才知道。
			# 掉落不按职业过滤（ADR-0025 §2），加满 4 职业后这件事是常态而非意外 ——
			# 一个剑客档里混着刀和杖，没有标记时「能不能穿」只能靠一件件试
			icon.locked = it != null and not PlayerState.can_equip(it)

	# 背包空着要写明「（空）」—— 格子全空 + 一句话都没有，
	# 玩家分不清「空」和「没画出来」。选中详情在中栏（_refresh_detail_panel）
	var detail_idx: int = _cursor - ItemData.SLOT_IDS.size()
	_bag_empty.text = tr("UI_BAG_EMPTY") if bag.is_empty() else ""

	_refresh_detail_panel(bag, detail_idx)

	# 材料行：五种材料常驻背包（含精铁 —— 它就是 shards，显示在这里，
	# 主界面右上角只留元宝）。**这里就是材料数量的唯一显示位**
	var cr := PlayerState.crafting()
	var parts: Array[String] = []
	for id in [PlayerState.MAT_REFINED_IRON, &"mat_black_iron", &"mat_sky_crystal", &"mat_dragon_soul", &"mat_taichu"]:
		parts.append("%s%d" % [tr(cr.mat_key(id)), PlayerState.material_count(id)])
	_mat_row.text = "　".join(parts)


## 左侧详情栏（2026-09-18 神圈注：选中装备要看得见「它是什么、拆了得什么」）。
## 光标在装备槽行或背包格上都算选中；空格 / 空槽写引导语
func _refresh_detail_panel(bag: Array, detail_idx: int) -> void:
	var uid := ""
	if detail_idx >= 0 and detail_idx < bag.size():
		uid = str(bag[detail_idx])
	else:
		# 光标在装备槽行上 = 详情显示那一槽穿的
		var slots: int = ItemData.SLOT_IDS.size()
		if _cursor < slots:
			uid = PlayerState.equipped_uid(ItemData.SLOT_IDS[_cursor])
	if uid.is_empty():
		_detail_name.text = tr("UI_BAG_DETAIL_NONE")
		_detail_name.modulate = Color(0.62, 0.6, 0.55, 1)
		_detail_text.text = tr("UI_BAG_DETAIL_HINT")
		return
	var it := PlayerState.item_of(uid)
	if it == null:
		_detail_name.text = "?"
		_detail_name.modulate = Color(0.62, 0.6, 0.55, 1)
		_detail_text.text = ""
		return
	# 名字 + 品质名，颜色 = 档色（与图标/掉落物同源）
	var tier_names := ["普通", "精良", "优秀", "极品", "传说", "至尊"]
	_detail_name.text = "%s\n%s" % [tr(it.name_key), tier_names[int(it.tier)]]
	_detail_name.modulate = it.tier_color()
	# 属性 = **强化后的实际值**（ADR-0029：护甲/饰品的 hp/def 被强化放大）。
	# 攻击栏对武器额外标出强化给的攻击%（武器强化=攻击杠杆），护甲不显示攻击。
	# **不再显示「强化 +X%」那一坨**（用户 2026-09-19：挤地方、且对护甲是错的）
	var lines: Array[String] = []
	var st := PlayerState.forged_stat_of(uid)
	var is_weapon: bool = it.slot == ItemData.Slot.WEAPON
	if int(st.get("atk", 0)) > 0 or is_weapon:
		var atk_line := "%s +%d" % [tr("STAT_ATK"), int(st.get("atk", 0))]
		# 武器：把强化攻击杠杆并进攻击行（+N% 而不是单列一行「强化%」）
		var wpct := int(round(PlayerState.forge_mult(uid) * 100.0))
		if is_weapon and wpct > 0:
			atk_line += " (+%d%%)" % wpct
		lines.append(atk_line)
	if int(st.get("hp", 0)) > 0:
		lines.append("%s +%d" % [tr("STAT_HP"), int(st.get("hp", 0))])
	if int(st.get("def", 0)) > 0:
		lines.append("%s +%d" % [tr("STAT_DEF"), int(st.get("def", 0))])
	var lv := PlayerState.forge_level(uid)
	if lv > 0:
		lines.append("%s +%d" % [tr("UI_FORGE_TAG"), lv])
	lines.append("%s %d" % [tr("HUD_GOLD"), int(it.gold_price)])
	# **「用不了」要说全**：格子上那道斜杠只是「有问题」，
	# 这里回答「为什么、能拿它干什么」—— 光有符号没有句子，玩家还是得自己猜
	if not PlayerState.can_equip(it):
		lines.insert(0, tr("UI_BAG_LOCKED_LINE"))
	# 分解产物：让玩家在拆之前就知道能得什么 —— 回收闭环看得见才有人走
	var yld: Dictionary = PlayerState.disassemble_table().yield_for(int(it.tier))
	if not yld.is_empty():
		var dparts: Array[String] = []
		var cr := PlayerState.crafting()
		for id in yld:
			dparts.append("%s×%d" % [tr(cr.mat_key(StringName(String(id)))), int(yld[id])])
		lines.append("")
		lines.append("%s：%s" % [tr("UI_BAG_DISMANTLE"), "、".join(dparts)])
	_detail_text.text = "\n".join(lines)

	# 材料行：五种材料常驻背包（含精铁 —— 它就是 shards，显示在这里，
	# 主界面右上角只留元宝）。**这里就是材料数量的唯一显示位**
	var cr := PlayerState.crafting()
	var parts: Array[String] = []
	for id in [PlayerState.MAT_REFINED_IRON, &"mat_black_iron", &"mat_sky_crystal", &"mat_dragon_soul", &"mat_taichu"]:
		parts.append("%s%d" % [tr(cr.mat_key(id)), PlayerState.material_count(id)])
	_mat_row.text = "　".join(parts)


## 背包格子当前页（每页 2×6=12 格）。光标越过页边界时自动翻页
func _bag_page() -> int:
	var bag: int = PlayerState.bag.size()
	var per_page := BAG_COLS * BAG_GRID_ROWS
	var pages := int(ceil(float(maxi(bag, 1)) / float(per_page)))
	var idx: int = _cursor - ItemData.SLOT_IDS.size()
	if idx < 0:
		return 0
	return clampi(idx / per_page, 0, pages - 1)


## 装备名（高档加星）—— 名字用文字体现品质，颜色留给列表状态。
## v2 六档：极品 ★ / 传说 ★★ / 至尊 ★★★（前三档不加，白绿蓝本来就是过渡件）
func _item_name(it: ItemData) -> String:
	if it == null:
		return "?"
	var n := tr(it.name_key)
	match it.tier:
		ItemData.Tier.LEGENDARY:
			return n + " ★★★"
		ItemData.Tier.EPIC:
			return n + " ★★"
		ItemData.Tier.RARE:
			return n + " ★"
		_:
			return n


## 一件装备的词条文本：「+2　攻+12　血+38　防+5」。
## **数值取【强化后的实际值】**（ADR-0029：护甲/饰品 hp/def 被强化放大）——
## 设计原则 4.1 要求面板显示 == 实际贡献。开头 `+N` 是强化等级；
## 武器额外在攻击后标 (+N%)（武器强化=攻击杠杆）。**不再单列「强化+X%」**（用户 2026-09-19）。
## 什么都没给时是「—」，不显示空白
func _stat_text(uid: String, it: ItemData) -> String:
	if it == null:
		return ""
	var parts: Array[String] = []
	var lv := PlayerState.forge_level(uid)
	var st := PlayerState.forged_stat_of(uid)
	if lv > 0:
		parts.append("+%d" % lv)
	if int(st.get("atk", 0)) > 0:
		var atk_part := "%s+%d" % [tr("STAT_ATK"), int(st.get("atk", 0))]
		var wpct := int(round(PlayerState.forge_mult(uid) * 100.0))
		if it.slot == ItemData.Slot.WEAPON and wpct > 0:
			atk_part += "(+%d%%)" % wpct
		parts.append(atk_part)
	if int(st.get("hp", 0)) > 0:
		parts.append("%s+%d" % [tr("STAT_HP"), int(st.get("hp", 0))])
	if int(st.get("def", 0)) > 0:
		parts.append("%s+%d" % [tr("STAT_DEF"), int(st.get("def", 0))])
	return "—" if parts.is_empty() else "　".join(parts)


# ─────────────────────────────────────────────────────────────

## 每帧刷新的**连续量**：血 / 蓝条、经验环、等级、元宝、技能栏（冷却遮罩 + 消耗品次数）、
## 屏号。这些每帧都可能变（战斗中掉血、放技能走冷却），轮询比给每个点接信号便宜又不漏
## （见文件头）。**面板行重建（重活）不在这里** —— 它走 refresh() + 信号驱动（见 _process）
func _refresh_status() -> void:
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
	# 主界面只显示元宝（2026-09-18 神圈注）。精铁搬进背包面板的材料行 ——
	# 强化时打开背包/铁匠铺都看得见，战斗中它不是要盯的数字
	_bag_label.text = "%s ×%d" % [tr("HUD_GOLD"), PlayerState.gold]

	refresh_skill_bar()
	refresh_stage_label()


## 全量刷新：连续量 + 打开着的面板。_ready 与各操作处理器（换装 / 装技能后）调它。
## 每帧的 _process 只调 _refresh_status（不重建面板行）；面板行重建改由信号驱动 ——
## equipment_changed → 背包面板，skills_changed → 技能面板（见 _ready 的连接）
func refresh() -> void:
	_refresh_status()
	if _bag_open:
		refresh_bag()
	if _skill_open:
		refresh_skill_panel()


## 装备/背包/强化变了 → 只在背包面板开着时重建它的行（关着时下次打开会刷）
func _on_equipment_changed() -> void:
	if _bag_open:
		refresh_bag()


## 携带技能变了 → 技能栏图标随连续量下一帧自然更新；技能面板开着才重建行
func _on_skills_changed() -> void:
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


## 角色属性块（B 面板左栏顶部，8 行紧凑）。数值全部来自「当前生效值」，
## 不是来自某一个来源 —— 玩家在这儿看到的攻击加成必须等于实际打到怪身上的倍率。
## 原 C 键面板的属性表（2026-09-18 并入背包，一键看全部）
func _refresh_stats_block(h: Health) -> void:
	var level := int(_player.get("level"))
	var exp_pts := int(_player.get("exp_pts"))
	var mp := int(_player.get("mp"))
	var max_mp := int(_player.get("max_mp"))
	var hp := 0 if h == null else h.hp
	var max_hp := 0 if h == null else h.max_hp
	var dmg: float = _player.get_node("Hitbox").damage_scale
	var flat: int = int(_player.get_node("Hitbox").attack_flat)
	var def: int = 0 if h == null else h.defense
	var red: float = 0.0 if h == null else h.effective_reduction()
	var lines: Array[String] = [
		"%s %d / %d" % [tr("PANEL_LEVEL"), level, PlayerState.level_cap],
		_exp_line(level, exp_pts),
		"%s %d / %d" % [tr("PANEL_HP"), hp, max_hp],
		"%s %d / %d" % [tr("PANEL_MP"), mp, max_mp],
		# 攻击在 v2 是两个数（4.1 要求两个都看得见）：平铺点数 + 乘区倍率。
		# 实际伤害 = (技能基础 + 平铺) × 倍率 × 目标护甲 —— 面板把前两项如实摆出来
		"%s +%d ×%.2f" % [tr("PANEL_ATK"), flat, dmg],
		# 防御同理：平铺点数 + 它换来的减伤比例（由 Health 的护甲曲线算，不重复实现）
		"%s %d（-%d%%）" % [tr("PANEL_DEF"), def, int(round(red * 100.0))],
		_weapon_forge_line(),
	]
	# 左右两栏（生存 / 战力）—— 单栏 7 行在这个字体的行高下塞不下，
	# 两栏各 4 行是 CharPanel 时代验证过不叠字的摆法
	_stats_l.text = "\n".join(lines.slice(0, 4))
	_stats_r.text = "\n".join(lines.slice(4, 7))


## 技能栏：5 格技能 + 2 格消耗品。
##
## 技能格显冷却遮罩从满格缩到无（造梦西游式），蓝不够或空槽时图标变暗；
## 消耗品格显剩余**次数**，次数归零画暗格 + 灰 0。
## 两者都是「现在按下去有没有用」的答案，**不弹提示 —— 暗就是提示**。
##
## 消耗品**满血 / 满蓝时不变暗**：那时按下去会飘字说明原因（见 player.use_potion），
## 但「次数还在」这件事必须一直看得见，不然玩家会以为符已经用完了。
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
	_refresh_potion_cells()


## 两个消耗品格：剩余次数 + 用完变暗。
## 次数当场从 PlayerState 读（与元宝/精铁同一条态度：真相同一份，不缓存）
func _refresh_potion_cells() -> void:
	for i in PlayerState.POTION_KINDS.size():
		var idx: int = PlayerState.SKILL_SLOT_COUNT + i
		if idx >= _skill_cells.size():
			return                       # 栏还没建起来（_ready 之前也可能被 refresh 叫到）
		var cell: Panel = _skill_cells[idx]
		var icon := cell.get_node_or_null("Icon") as ItemIcon
		var count := cell.get_node_or_null("Count") as Label
		if icon == null or count == null:
			continue
		var left := PlayerState.potion_charges(PlayerState.POTION_KINDS[i])
		count.text = "%d" % left
		# 0 次 = 这张符此刻是废的。整个图标压暗 + 灰数字，与技能格「放不出来」
		# 同一套语言（ItemIcon 没有 dim 属性，modulate 对它是等价的整体压暗，
		# 不必为这一处去改八种形状的画法）
		icon.modulate = Color(0.45, 0.45, 0.45, 1.0) if left <= 0 else Color(1, 1, 1, 1)
		count.add_theme_color_override("font_color",
			Color(0.52, 0.5, 0.48, 1) if left <= 0 else Color(1, 1, 1, 0.95))


## 精铁数量。**只认 PlayerState 那一份** —— 玩家节点上没有第二份
## （曾经有，代价是「强化扣了钱、HUD 还显示旧数」，截图抓到的）
func shards_of() -> int:
	return PlayerState.shards
