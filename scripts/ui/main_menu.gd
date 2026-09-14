extends Control
## 主菜单：开始 / 继续 / 读取存档 / 语言 / 退出 + 存档槽位面板。
##
## 存档模型（用户验收定的）：3 个槽位。「开始游戏」先选槽（选中有档的槽 = 覆盖），
## 「读取存档」列槽挑一个进；「继续游戏」直接回最近一次玩的槽。
## 进度档记：哪个场景 + 离开时的世界快照 + 玩家数据（碎片 / 强化）。

## 流程起点：城镇。从这里经传送门进入关卡
const LEVEL_PATH := "res://scenes/stages/town.tscn"

## 槽位面板模式：start = 选槽开新游戏（可覆盖），load = 选槽读档
enum SlotMode { START, LOAD }

var _slot_mode: int = SlotMode.START

@onready var _start_btn: Button = $Panel/Box/Start
@onready var _continue_btn: Button = $Panel/Box/Continue
@onready var _load_btn: Button = $Panel/Box/Load
@onready var _lang_btn: Button = $Panel/Box/Language
@onready var _quit_btn: Button = $Panel/Box/Quit
@onready var _title: Label = $Title
@onready var _slots: Panel = $Slots
@onready var _slots_title: Label = $Slots/Title
@onready var _slot_btns: Array[Button] = [$Slots/Box/Slot1, $Slots/Box/Slot2, $Slots/Box/Slot3]
@onready var _back_btn: Button = $Slots/Box/Back


func _ready() -> void:
	_start_btn.pressed.connect(_on_start)
	_continue_btn.pressed.connect(_on_continue)
	_load_btn.pressed.connect(_on_load)
	_lang_btn.pressed.connect(_on_language)
	_quit_btn.pressed.connect(_on_quit)
	_back_btn.pressed.connect(_close_slots)
	for i in _slot_btns.size():
		var idx := i + 1
		_slot_btns[i].pressed.connect(_on_slot.bind(idx))
	if not GameSettings.language_changed.is_connected(_refresh_texts):
		GameSettings.language_changed.connect(_refresh_texts)
	_slots.visible = false
	_refresh_texts()
	_refresh_continue()


## 参数是 language_changed 带的语言码，这里用不上但必须留 ——
## Godot 连信号按参数个数严格匹配，少了会「连上但调用报错、界面静默不刷新」。
## 这个坑在 hint.gd 和这里各踩过，别有第三次。
func _refresh_texts(_locale: String = "") -> void:
	_title.text = tr("UI_MENU_TITLE")
	_start_btn.text = tr("UI_MENU_START")
	_continue_btn.text = tr("UI_MENU_CONTINUE")
	_load_btn.text = tr("UI_MENU_LOAD")
	_quit_btn.text = tr("UI_MENU_QUIT")
	_lang_btn.text = "%s：%s" % [tr("UI_MENU_LANGUAGE"), GameSettings.SUPPORTED[GameSettings.language]]
	_slots_title.text = tr("UI_SLOTS_TITLE_NEW") if _slot_mode == SlotMode.START else tr("UI_SLOTS_TITLE_LOAD")
	_refresh_continue()
	_refresh_slot_buttons()


func _refresh_continue() -> void:
	var last := SaveManager.last_slot()
	_continue_btn.visible = last > 0 and SaveManager.slot_exists(last)


func _refresh_slot_buttons() -> void:
	for i in _slot_btns.size():
		var slot := i + 1
		_slot_btns[i].text = _slot_text(slot, i + 1)
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
	var upgrade := int(player.get("upgrade", 0))
	var level_file := str(info.get("level", "")).get_file().get_basename()
	var place := tr("UI_LEVEL_" + level_file.to_upper())
	# 旧结构的档：等级 / 装备 / 精铁都在，但「打到第几关」那套记录已经作废
	# （线性三关 → 地图/副本/关卡三层）。**不能静默** ——
	# 玩家点进去会发现自己站在城镇、进度从头开始，得先在这里说清楚
	var stale := SaveManager.slot_version(slot) < SaveManager.VERSION
	var tail := tr("UI_SLOT_OLD") if stale else place
	return "%d. %s　%s ×%d　%s Lv.%d" % [
		index, tail, tr("HUD_SHARD"), shards, tr("HUD_WEAPON"), upgrade]


# ── 按钮动作 ───────────────────────────────────────────────────

func _on_start() -> void:
	_slot_mode = SlotMode.START
	_slots.visible = true
	_refresh_texts()


func _on_load() -> void:
	_slot_mode = SlotMode.LOAD
	_slots.visible = true
	_refresh_texts()


func _close_slots() -> void:
	_slots.visible = false


func _on_slot(slot: int) -> void:
	if _slot_mode == SlotMode.START:
		PlayerState.reset_for_new_game()
		SaveManager.start_new_game(slot, LEVEL_PATH)
		# 开局的解锁进度：只有第一个副本的第一段。其余全靠一关一关打出来
		GameProgress.reset_progress()
		get_tree().change_scene_to_file(LEVEL_PATH)
	else:
		_enter_slot(slot)


func _on_continue() -> void:
	var last := SaveManager.last_slot()
	if last > 0 and SaveManager.slot_exists(last):
		_enter_slot(last)


## 从槽位进入：场景 + 快照 + 玩家数据，三样都从档里来
func _enter_slot(slot: int) -> void:
	SaveManager.load_game(slot)
	var st := SaveManager.read_state(slot)
	# 旧结构的档（三层结构之前存的）：等级 / 装备 / 精铁照旧带回，
	# 但「打到第几关」那套记录已经作废 —— 把玩家送回城镇，解锁进度重新初始化。
	# **保留成长、只重来关卡进度**：直接作废整份档等于让玩家白玩，太粗暴
	if SaveManager.slot_version(slot) < SaveManager.VERSION:
		if st.has("player"):
			PlayerState.load_from(st.player)
		# 那份快照里的坐标是老关卡的（x 可能到 1800），套不进城镇。
		# 撤掉恢复请求 = 只带成长数据、世界从头开始
		SaveManager.drop_pending_restore()
		GameProgress.reset_progress()
		get_tree().change_scene_to_file(LEVEL_PATH)
		return
	var level := SaveManager.read_progress(slot)
	if level.is_empty() or not ResourceLoader.exists(level):
		SaveManager.erase_slot(slot)
		_refresh_texts()
		return
	if st.has("player"):
		PlayerState.load_from(st.player)
	get_tree().change_scene_to_file(level)


func _on_language() -> void:
	var codes := GameSettings.SUPPORTED.keys()
	var i := codes.find(GameSettings.language)
	GameSettings.set_language(str(codes[(i + 1) % codes.size()]))


func _on_quit() -> void:
	get_tree().quit()
