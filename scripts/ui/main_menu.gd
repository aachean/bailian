extends Control
## 主菜单：开始 / 继续 / 语言 / 退出。
##
## 「开始」进关卡并写档；「继续」只在有档时出现，读档进关卡。
## 语言按钮循环切换已支持的语言 —— GameSettings 落地时用户等的那半句
## 「设置里可以选不同语言」，从这一版开始成立（设置界面本身仍归 M2 的极简 UI 收尾）。

## 现在唯一的关卡。M2 增量 3 加城镇后，这里换成「进入城镇」
const LEVEL_PATH := "res://scenes/stages/test_room.tscn"

@onready var _start_btn: Button = $Panel/Box/Start
@onready var _continue_btn: Button = $Panel/Box/Continue
@onready var _lang_btn: Button = $Panel/Box/Language
@onready var _quit_btn: Button = $Panel/Box/Quit
@onready var _title: Label = $Title


func _ready() -> void:
	_start_btn.pressed.connect(_on_start)
	_continue_btn.pressed.connect(_on_continue)
	_lang_btn.pressed.connect(_on_language)
	_quit_btn.pressed.connect(_on_quit)
	if not GameSettings.language_changed.is_connected(_refresh_texts):
		GameSettings.language_changed.connect(_refresh_texts)
	_refresh_texts()
	_refresh_continue()


## 参数是 language_changed 带的语言码，这里用不上但必须留 ——
## Godot 连信号按参数个数严格匹配，少了会「连上但调用报错、界面静默不刷新」。
## 这个坑在 hint.gd 已经踩过一次，别有第三次。
func _refresh_texts(_locale: String = "") -> void:
	_title.text = tr("UI_MENU_TITLE")
	_start_btn.text = tr("UI_MENU_START")
	_continue_btn.text = tr("UI_MENU_CONTINUE")
	_quit_btn.text = tr("UI_MENU_QUIT")
	# 语言按钮显示「当前语言」，点一下切到下一个 —— 就地循环，不用列表
	_lang_btn.text = "%s：%s" % [tr("UI_MENU_LANGUAGE"), GameSettings.SUPPORTED[GameSettings.language]]


func _refresh_continue() -> void:
	_continue_btn.visible = SaveManager.has_save()


func _on_start() -> void:
	SaveManager.request_new_game(LEVEL_PATH)
	get_tree().change_scene_to_file(LEVEL_PATH)


func _on_continue() -> void:
	var level := SaveManager.read_progress()
	if level.is_empty() or not ResourceLoader.exists(level):
		# 档指向的场景已经不存在了（改版删场景）：当作没档，回新游戏
		SaveManager.erase_save()
		_refresh_continue()
		return
	SaveManager.request_continue()
	get_tree().change_scene_to_file(level)


func _on_language() -> void:
	var codes := GameSettings.SUPPORTED.keys()
	var i := codes.find(GameSettings.language)
	GameSettings.set_language(str(codes[(i + 1) % codes.size()]))
	# language_changed 信号会带回 _refresh_texts，按钮文案自己换


func _on_quit() -> void:
	get_tree().quit()
