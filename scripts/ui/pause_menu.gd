extends CanvasLayer
## 暂停菜单：Esc 打开（游戏真暂停），继续 / 保存 / 回主菜单。
##
## 存档时机的设计（用户验收定的）：玩的过程中要能主动保存，
## 不能只在回主菜单时才写档。保存 = 把当前世界快照写进当前槽位。
##
## process_mode 必须是 ALWAYS：打开菜单要靠它收 Esc（游戏未暂停时），
## 暂停中收 Esc 关菜单（游戏已暂停时）——其他节点全部照常被暂停冻结。

@onready var _root: Control = $Root
@onready var _continue_btn: Button = $Root/Panel/Box/Continue
@onready var _save_btn: Button = $Root/Panel/Box/Save
@onready var _menu_btn: Button = $Root/Panel/Box/Menu


func _ready() -> void:
	_root.visible = false
	_continue_btn.pressed.connect(_close)
	_save_btn.pressed.connect(_on_save)
	_menu_btn.pressed.connect(_on_back_to_menu)
	if not GameSettings.language_changed.is_connected(_refresh_texts):
		GameSettings.language_changed.connect(_refresh_texts)
	_refresh_texts()


## ALWAYS 模式：暂停与否都收得到
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# 装备背包开着时不抢 Esc —— 两个界面都要用 Esc / B，叠起来只会互相打架。
		# 此时先按 B 关背包，再按 Esc 才能开暂停菜单
		if not _root.visible and _bag_open():
			return
		toggle()


## 菜单是否开着（HUD 靠它判断「该不该叠背包」）
func is_open() -> bool:
	return _root.visible


func _bag_open() -> bool:
	var hud := get_parent().get_node_or_null("HUD")
	return hud != null and hud.has_method("is_bag_open") and bool(hud.call("is_bag_open"))


func toggle() -> void:
	if _root.visible:
		_close()
	else:
		_open()


func _open() -> void:
	_root.visible = true
	get_tree().paused = true
	_save_btn.text = tr("UI_PAUSE_SAVE")
	_refresh_texts()


func _close() -> void:
	_root.visible = false
	get_tree().paused = false
	_save_btn.text = tr("UI_PAUSE_SAVE")


## 参数必须留着：Godot 按参数个数严格匹配信号连接，少一个会「连上了但一调用就报错」，
## 界面静默不刷新（M1 的语言切换用例抓到过这个家族）
func _refresh_texts(_locale: String = "") -> void:
	_continue_btn.text = tr("UI_PAUSE_CONTINUE")
	_save_btn.text = tr("UI_PAUSE_SAVE")
	_menu_btn.text = tr("UI_PAUSE_MENU")


## 保存：当前关卡的完整快照写进当前槽位。暂停不影响函数调用
func _on_save() -> void:
	var level := get_tree().current_scene
	if level != null and level.has_method("collect"):
		SaveManager.write_progress(level.scene_file_path, level.call("collect"))
	_save_btn.text = tr("UI_PAUSE_SAVED")


func _on_back_to_menu() -> void:
	var level := get_tree().current_scene
	if level != null and level.has_method("collect"):
		SaveManager.write_progress(level.scene_file_path, level.call("collect"))
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
