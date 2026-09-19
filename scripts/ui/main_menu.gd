extends Control
## 主菜单：新的开始 / 继续 / 读取存档 / **设置** / 退出 + 存档槽位面板。
##
## 存档模型（2026-09-15 黑盒反馈修订）：**15 个槽位，每页 5 个翻 3 页**。
## 「新的开始」先选槽 —— **选中已有存档的槽要弹确认**，玩家手滑点错位
## 不该直接抹掉几十级的进度；「读取存档」列槽挑一个进（只读不写，不用确认）；
## 「继续游戏」直接回最近一次玩的槽。
## 进度档记：哪个场景 + 离开时的世界快照 + 玩家数据（元宝 / 精铁 / 装备 / 强化）。

## 流程起点：城镇。从这里经舆图台进入副本
const LEVEL_PATH := "res://scenes/stages/town.tscn"

## 每页几个槽位、共几页（15 = 5 × 3）
const PAGE_SIZE := 5
const SLOT_PAGES := 3

## 槽位面板模式：start = 选槽开新游戏（有档要确认覆盖），load = 选槽读档
enum SlotMode { START, LOAD }

var _slot_mode: int = SlotMode.START
var _page := 0
## 待覆盖确认的槽位（确认面板开着时有值）
var _pending_slot := 0
## 新的开始：先选人再选槽。选中的角色 id（CharacterData.id）
var _pending_character := &""

var _slot_btns: Array[Button] = []
var _prev_btn: Button
var _next_btn: Button
var _page_label: Label
## 覆盖确认面板（代码建：只在 START 模式 + 有档槽位时露面）
var _confirm: Control = null
var _confirm_text: Label = null
var _yes_btn: Button = null
var _no_btn: Button = null

@onready var _start_btn: Button = $Panel/Box/Start
@onready var _continue_btn: Button = $Panel/Box/Continue
@onready var _load_btn: Button = $Panel/Box/Load
@onready var _settings_btn: Button = $Panel/Box/Settings
@onready var _settings: Node = $SettingsPanel
@onready var _credits_btn: Button = $Panel/Box/Credits
@onready var _credits: Node = $CreditsPanel
@onready var _quit_btn: Button = $Panel/Box/Quit
@onready var _title: Label = $Title
@onready var _slots: Panel = $Slots
@onready var _slots_title: Label = $Slots/Title
@onready var _box: VBoxContainer = $Slots/Box
@onready var _back_btn: Button = $Slots/Box/Back


const Backdrop := preload("res://scripts/core/backdrop.gd")


func _ready() -> void:
	# 主菜单背景（暮色山门）。无相机 → 远景/中景静止，只做底图
	var bd: Node2D = Backdrop.new()
	bd.name = "Backdrop"
	bd.theme = &"title"
	add_child(bd)
	move_child(bd, 0)
	# 版本号：测试版必须能报版本（没有它，反馈「玩不了」时无从问起）。
	# 显式 position/size 而不是 anchors —— 这个项目在 Control 定位上踩过坑，别赌
	var ver := Label.new()
	ver.name = "Version"
	ver.text = "v%s" % ProjectSettings.get_setting("application/config/version", "dev")
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", Color(0.72, 0.7, 0.64, 0.8))
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport_rect().size
	ver.position = Vector2(vp.x - 152.0, vp.y - 32.0)
	ver.size = Vector2(140.0, 20.0)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)
	_start_btn.pressed.connect(_on_start)
	_continue_btn.pressed.connect(_on_continue)
	_load_btn.pressed.connect(_on_load)
	_settings_btn.pressed.connect(_on_settings)
	_credits_btn.pressed.connect(_on_credits)
	_quit_btn.pressed.connect(_on_quit)
	_back_btn.pressed.connect(_close_slots)
	_build_slot_rows()
	_build_confirm_panel()
	_build_character_page()
	if not GameSettings.language_changed.is_connected(_refresh_texts):
		GameSettings.language_changed.connect(_refresh_texts)
	_slots.visible = false
	_refresh_texts()
	_refresh_continue()


## 槽位行全部由代码建（15 个按钮手写 tscn 是自找麻烦；与 HUD 面板同一套做法）。
## 按钮命名 Slot1..Slot5 —— 存档摘要、置灰逻辑都只看「这一页的第几个」
func _build_slot_rows() -> void:
	# 翻页行：◀　第 x/3 页　▶
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	_prev_btn = Button.new()
	_prev_btn.text = "◀"
	_prev_btn.custom_minimum_size = Vector2(56, 32)
	_prev_btn.pressed.connect(_on_prev_page)
	nav.add_child(_prev_btn)
	_page_label = Label.new()
	_page_label.custom_minimum_size = Vector2(120, 32)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(_page_label)
	_next_btn = Button.new()
	_next_btn.text = "▶"
	_next_btn.custom_minimum_size = Vector2(56, 32)
	_next_btn.pressed.connect(_on_next_page)
	nav.add_child(_next_btn)
	_box.add_child(nav)

	for i in PAGE_SIZE:
		var b := Button.new()
		b.name = "Slot%d" % (i + 1)
		b.custom_minimum_size = Vector2(400, 44)
		b.pressed.connect(_on_slot.bind(0))   # 参数在刷新时重绑（翻页会变）
		_box.add_child(b)
		_slot_btns.append(b)
	# 「返回」搬回最底：tscn 里它排在最前，动态行会插在它上面
	_box.move_child(_back_btn, _box.get_child_count() - 1)


## 覆盖确认面板：暗底 + 一块小板 + 槽位摘要 + 覆盖 / 取消。
## **只拦「新的开始」踩到有档的槽** —— 读档只读不写，不拦
func _build_confirm_panel() -> void:
	_confirm = Control.new()
	_confirm.visible = false
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	_confirm.add_child(dim)

	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", load("res://assets/ui/panel_style.tres"))
	# 视口 640×360，420×150 的板手工居中即可（CanvasLayer 锚点那坑的教训：显式定位最稳）
	panel.position = Vector2(110, 105)
	panel.size = Vector2(420, 150)
	_confirm.add_child(panel)

	_confirm_text = Label.new()
	_confirm_text.position = Vector2(16, 14)
	_confirm_text.size = Vector2(388, 80)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_text.add_theme_font_size_override("font_size", 13)
	panel.add_child(_confirm_text)

	_yes_btn = Button.new()
	_yes_btn.position = Vector2(60, 104)
	_yes_btn.size = Vector2(150, 30)
	_yes_btn.pressed.connect(_on_confirm_overwrite)
	panel.add_child(_yes_btn)

	_no_btn = Button.new()
	_no_btn.position = Vector2(230, 104)
	_no_btn.size = Vector2(130, 30)
	_no_btn.pressed.connect(_on_cancel_overwrite)
	panel.add_child(_no_btn)


## 参数是 language_changed 带的语言码，这里用不上但必须留 ——
## Godot 连信号按参数个数严格匹配，少了会「连上但调用报错、界面静默不刷新」。
## 这个坑在 hint.gd 和这里各踩过，别有第三次。
func _refresh_texts(_locale: String = "") -> void:
	_title.text = tr("UI_MENU_TITLE")
	_start_btn.text = tr("UI_MENU_START")
	_continue_btn.text = tr("UI_MENU_CONTINUE")
	_load_btn.text = tr("UI_MENU_LOAD")
	_quit_btn.text = tr("UI_MENU_QUIT")
	_settings_btn.text = tr("UI_MENU_SETTINGS")
	_credits_btn.text = tr("UI_CREDITS")
	_slots_title.text = tr("UI_SLOTS_TITLE_NEW") if _slot_mode == SlotMode.START else tr("UI_SLOTS_TITLE_LOAD")
	_page_label.text = tr("UI_SLOT_PAGE") % [_page + 1, SLOT_PAGES]
	_prev_btn.disabled = _page <= 0
	_next_btn.disabled = _page >= SLOT_PAGES - 1
	_yes_btn.text = tr("UI_CONFIRM_YES")
	_back_btn.text = tr("UI_BACK")
	_no_btn.text = tr("UI_CONFIRM_NO")
	_refresh_continue()
	_refresh_slot_buttons()


func _refresh_continue() -> void:
	# 按钮只在**真有一个能继续的槽**时出现。以前判的是「最近那个槽的文件在不在」——
	# 空壳槽也满足，于是点下去进了个没有进度的世界（见 _on_continue 的注释）
	_continue_btn.visible = _resumable_slot() > 0


func _refresh_slot_buttons() -> void:
	for i in _slot_btns.size():
		var slot := _page * PAGE_SIZE + i + 1
		# 重绑槽位号（翻页后同一颗按钮代表另一个槽）
		for conn in _slot_btns[i].pressed.get_connections():
			_slot_btns[i].pressed.disconnect(conn["callable"])
		_slot_btns[i].pressed.connect(_on_slot.bind(slot))
		# 显示**绝对槽位号**（第 2 页就是 6.~10.）——
		# 每页都从 1 重排的话，玩家记不住自己的档在第几页第几格
		_slot_btns[i].text = _slot_text(slot, slot)
		if _slot_mode == SlotMode.LOAD:
			_slot_btns[i].disabled = not SaveManager.slot_exists(slot)
		else:
			_slot_btns[i].disabled = false


## 槽位按钮上的摘要：空的写「空」，有档写玩家最关心的三样。
## 注意占位符与参数要一一对上 —— 少一个参数整串格式化失败（实测翻过车）
func _slot_text(slot: int, index: int) -> String:
	var info := SaveManager.read_slot_info(slot)
	if info.is_empty():
		return "%d. %s" % [index, tr("UI_SLOT_EMPTY")]
	var st := info.get("state", {}) as Dictionary
	var player := st.get("player", {}) as Dictionary
	var shards := int(player.get("shards", 0))
	var level := int(player.get("level", 1))
	var level_file := str(info.get("level", "")).get_file().get_basename()
	var place := tr("UI_LEVEL_" + level_file.to_upper())
	# 低于 STRUCTURE_VERSION 的档**不可继续**（v2 换了装备模型，读一半比读不了更坏）。
	# **不能静默** —— 列表上必须先说清楚是「玩不了」而不是「空档」
	var tail := tr("UI_SLOT_OLD") if not SaveManager.slot_usable(slot) else place
	# 这档玩的是谁（2026-09-15 黑盒反馈：读档列表看不出哪档是弓手）
	var cid := str(player.get("character_id", ""))
	var who := ""
	var cd := CharacterData.by_id(StringName(cid))
	if cd != null:
		who = tr(cd.name_key) + "　"
	# 摘要里不再写「武器 Lv.N」—— 强化改成逐件之后，那个全局等级不存在了
	return "%d. %s%s　%s ×%d　%s Lv.%d" % [
		index, who, tail, tr("HUD_SHARD"), shards, tr("PANEL_LEVEL"), level]


# ── 选人页（M4：新的开始先选角色）────────────────────────────

## 角色按钮列表（代码建，数量跟着 data/characters/ 里的 .tres 走）
var _char_btns: Array[Button] = []
var _char_page: Control = null
var _char_title: Label = null


## 选人页：暗底 + 标题 + 每个角色一颗按钮（名字 + 一句话介绍）。
## 角色列表来自 CharacterData.all() —— 加角色 = 加 .tres，这页自己长。
##
## ── 布局用显式坐标，不用锚点 ──────────────────────────────────
## 黑盒反馈：第一版标题和按钮全跟主菜单叠在一起 —— 当时依赖
## set_anchors_preset 铺满/居中，控件加进树之前设的锚点没按预期铺开，
## 暗底尺寸为 0 等于没遮。HUD 那次的教训在这里又应验一遍：
## **全屏遮罩一律显式 position + size**。
## 另外打开本页时把主菜单的标题与按钮区**藏起来** —— 叠着就是两层界面。
func _build_character_page() -> void:
	_char_page = Control.new()
	_char_page.visible = false
	_char_page.position = Vector2.ZERO
	_char_page.size = Vector2(640, 360)
	add_child(_char_page)

	var dim := ColorRect.new()
	dim.position = Vector2.ZERO
	dim.size = Vector2(640, 360)
	dim.color = Color(0.07, 0.07, 0.09, 1)
	_char_page.add_child(dim)

	_char_title = Label.new()
	_char_title.position = Vector2(0, 30)
	_char_title.size = Vector2(640, 40)
	_char_title.add_theme_font_size_override("font_size", 20)
	_char_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_char_page.add_child(_char_title)

	var box := VBoxContainer.new()
	box.position = Vector2(110, 88)
	box.size = Vector2(420, 200)
	box.add_theme_constant_override("separation", 10)
	_char_page.add_child(box)

	for c in CharacterData.all():
		var b := Button.new()
		# 四职业时代的高度账：88 + 4×40 + 3×10 = 298，必须停在「返回」(y=300) 之上。
		# 两角色时代的 52px×4 会把第四颗按钮压到返回键上（VBox 不裁剪，直接叠画）
		b.custom_minimum_size = Vector2(420, 40)
		# 有立绘就挂头像（ADR-0015）—— 选人页一眼看到「这是谁」
		if not c.sprite_dir.is_empty():
			var icon_path := c.sprite_dir + "/portrait.png"
			if ResourceLoader.exists(icon_path):
				b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				b.icon = load(icon_path)
				b.expand_icon = true
				b.add_theme_constant_override("h_separation", 12)
		b.pressed.connect(_on_character.bind(c.id))
		box.add_child(b)
		_char_btns.append(b)

	var back := Button.new()
	back.custom_minimum_size = Vector2(420, 32)
	back.position = Vector2(110, 300)
	back.size = Vector2(420, 32)
	back.pressed.connect(_on_back_from_chars)
	_char_page.add_child(back)
	_char_page.set_meta("back_btn", back)


func _on_back_from_chars() -> void:
	_char_page.visible = false
	_title.visible = true
	$Panel.visible = true


## 选人页的文字在打开时刷（角色列表是启动时建死的，数量不会中途变）。
## 打开时**把主菜单的标题与按钮区藏起来** —— 两层界面叠着就是事故（黑盒反馈）
func _open_character_page() -> void:
	_title.visible = false
	$Panel.visible = false
	_char_title.text = tr("UI_CHAR_TITLE")
	back_btn_from_char_page().text = tr("UI_BACK")
	var all := CharacterData.all()
	for i in _char_btns.size():
		var c := all[i] if i < all.size() else null
		if c == null:
			_char_btns[i].visible = false
			continue
		_char_btns[i].visible = true
		_char_btns[i].text = "%s　—　%s" % [tr(c.name_key), tr(c.desc_key)]
	(back_btn_from_char_page()).visible = true
	_char_page.visible = true


func back_btn_from_char_page() -> Button:
	return _char_page.get_meta("back_btn") as Button


## 选中角色 → 进槽位选择（覆盖确认照旧）。选谁记在 _pending_character，
## 真正写进存档是 _begin_new_game 的事 —— 中途返回不留下半个字
func _on_character(cid: StringName) -> void:
	_pending_character = cid
	_char_page.visible = false
	_slot_mode = SlotMode.START
	_page = 0
	_slots.visible = true
	_refresh_texts()


# ── 按钮动作 ───────────────────────────────────────────────────

func _on_start() -> void:
	_pending_character = &""
	_slots.visible = false
	_open_character_page()


func _on_load() -> void:
	_slot_mode = SlotMode.LOAD
	_page = 0
	_slots.visible = true
	_refresh_texts()


func _close_slots() -> void:
	_slots.visible = false
	_confirm.visible = false
	_title.visible = true
	$Panel.visible = true


func _on_prev_page() -> void:
	_page = maxi(_page - 1, 0)
	_refresh_texts()


func _on_next_page() -> void:
	_page = mini(_page + 1, SLOT_PAGES - 1)
	_refresh_texts()


## 选中一个槽。START 模式踩到**有档的槽**必须先问一句 ——
## 「新的开始」误点旧档 = 几十级进度一键蒸发，这种事不能只靠玩家手稳
func _on_slot(slot: int) -> void:
	if _slot_mode == SlotMode.START:
		if SaveManager.slot_exists(slot):
			_pending_slot = slot
			_confirm_text.text = "%s\n%s" % [
				tr("UI_CONFIRM_OVERWRITE"), _slot_text(slot, slot)]
			_confirm.visible = true
			return
		_begin_new_game(slot)
	else:
		_enter_slot(slot)


func _on_confirm_overwrite() -> void:
	var slot := _pending_slot
	_pending_slot = 0
	_confirm.visible = false
	_begin_new_game(slot)


func _on_cancel_overwrite() -> void:
	_pending_slot = 0
	_confirm.visible = false


## 真正开新游戏：清成长数据 → 记下选的角色 → 起新档 → 清解锁进度 → 进城镇
func _begin_new_game(slot: int) -> void:
	PlayerState.reset_for_new_game()
	PlayerState.character_id = String(_pending_character)
	SaveManager.start_new_game(slot, LEVEL_PATH)
	# 开局的解锁进度：只有第一个副本的第一段。其余全靠一关一关打出来
	GameProgress.reset_progress()
	get_tree().change_scene_to_file(LEVEL_PATH)


## 「继续游戏」= 回到最近玩过的那个槽。
##
## **但它必须真的有进度**。空壳槽（`state={}`：开过新档、却从没落过盘）照样能过
## `slot_usable()` 的检查 —— 那一关只看「格式读不读得懂」，不看里面有没有东西。
## 静默进去的后果是玩家以为「我的进度没了」（2026-09-20 实际发生：last_slot 被
## 测试改成 1，而槽 1 是空壳，于是继续游戏一声不吭地进了个全新世界）。
##
## 所以：先认最近那个，它没进度就按 saved_at 退到最近**有**进度的槽；
## 一个都没有才说话（不静默）。
func _on_continue() -> void:
	var slot := _resumable_slot()
	if slot > 0:
		_enter_slot(slot)
		return
	_slots_title.text = tr("UI_SLOT_NO_PROGRESS")


## 挑一个「真能继续」的槽。0 = 一个都没有
func _resumable_slot() -> int:
	var last := SaveManager.last_slot()
	if _slot_has_progress(last):
		return last
	var best := 0
	var best_at := -1
	for s in range(1, SaveManager.SLOT_COUNT + 1):
		if not _slot_has_progress(s):
			continue
		var at := int(SaveManager.read_slot_info(s).get("saved_at", 0))
		if at > best_at:
			best_at = at
			best = s
	return best


## 这一槽有东西可继续吗。判据是**快照里有 player** ——
## 版本号只说明「格式读得懂」，不代表里面真有角色数据（空壳槽就是后者）
func _slot_has_progress(slot: int) -> bool:
	if slot <= 0 or not SaveManager.slot_usable(slot):
		return false
	return SaveManager.read_state(slot).has("player")


## 从槽位进入：场景 + 快照 + 玩家数据，三样都从档里来。
##
## **不可继续的档到这里直接拒收**（v2 起）：旧档里的装备路径一条都读不出来，
## 硬读的结果是「装备栏空了几格、强化表飞了」而且**全都不报错**。
## 不做迁移、不做兜底 —— 把理由写在槽位列表的标题上，让玩家自己决定开新档还是删档
func _enter_slot(slot: int) -> void:
	if not SaveManager.slot_usable(slot):
		# 不静默：这类档点了必须有回应，否则玩家只会觉得「点了没反应」
		_slots_title.text = tr("UI_SLOT_OLD_BLOCK")
		return
	SaveManager.load_game(slot)
	var st := SaveManager.read_state(slot)
	var level := SaveManager.read_progress(slot)
	if level.is_empty() or not ResourceLoader.exists(level):
		SaveManager.erase_slot(slot)
		_refresh_texts()
		return
	if st.has("player"):
		PlayerState.load_from(st.player)
	get_tree().change_scene_to_file(level)


## 设置：**语言从主菜单挪进这里了**（2026-09-14）。
## 挪的理由不是「少一行」，是那行按钮**只干得了语言一件事**：
## 音量、以后的操作/画面选项都没地方放。设置面板是暂停菜单与主菜单
## 共用的同一份场景，两边的默认值不会各漂一套。
##
## 本节点**不管设置面板的暂停** —— 主菜单本来就没在跑游戏，
## 谁开的面板谁管暂停（同 hud.close_all_panels 那次的教训）
func _on_settings() -> void:
	if _settings != null:
		_settings.call("open")


## 素材致谢。面板是独立场景 —— 与设置面板同一个道理：
## 以后暂停菜单也要放这个入口时，共用同一份，不会漂成两套署名
func _on_credits() -> void:
	if _credits != null:
		_credits.call("open")


func _on_quit() -> void:
	get_tree().quit()
