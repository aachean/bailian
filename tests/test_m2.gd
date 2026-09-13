extends Node
## 《百炼》M2 自动验收 —— 增量 2：主菜单 / 存档底座 / 语言入口
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m2.tscn
##
## 战斗 / 移动的 33 条在 tests/test_m1.tscn，这里只管增量 2 的新东西。
## 场景切换本身（按开始 → 进关卡）是引擎一行调用，且会把本测试场景换掉，
## 无头环境测不了 —— 那条走人工验收，其余全部机器兜底。

const MENU := preload("res://scenes/ui/main_menu.tscn")

var _pass := 0
var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》M2 增量 2 自动验收 ═══")
	await _t1_menu_buttons()
	await _t2_continue_visibility()
	await _t3_save_roundtrip()
	await _t4_language_button()

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-3s %s\n              %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-3s %s\n              %s" % [id, desc, detail])


func _steps(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## 菜单能摆出来，四个按钮都在，文案是真话不是 key
func _t1_menu_buttons() -> void:
	var menu := MENU.instantiate()
	add_child(menu)
	await _steps(3)

	var missing := PackedStringArray()
	for node_path in ["Panel/Box/Start", "Panel/Box/Continue", "Panel/Box/Language", "Panel/Box/Quit"]:
		if menu.get_node_or_null(node_path) == null:
			missing.append(node_path)
	var title := (menu.get_node("Title") as Label).text
	var start_text := (menu.get_node("Panel/Box/Start") as Button).text
	var ok := missing.is_empty() and not title.is_empty() and title != "UI_MENU_TITLE" \
		and not start_text.is_empty() and start_text != "UI_MENU_START"
	_check("1", "主菜单摆得出来：标题 + 四个按钮，文案随语言",
		ok,
		"标题=\"%s\" 开始=\"%s\" 缺节点 %d 个" % [title, start_text, missing.size()])
	menu.queue_free()
	await _steps(2)


## 「继续」只在有档时出现 —— 这是存档系统在菜单上唯一可感知的开关
func _t2_continue_visibility() -> void:
	var menu := MENU.instantiate()
	add_child(menu)
	await _steps(2)
	var cont := menu.get_node("Panel/Box/Continue") as Button

	# 清档 → 继续隐藏；写档 → 继续出现
	SaveManager.erase_save()
	menu._refresh_continue()
	await _steps(2)
	var hidden_without_save: bool = not cont.visible

	SaveManager.write_progress("res://scenes/stages/test_room.tscn")
	menu._refresh_continue()
	await _steps(2)
	var shown_with_save: bool = cont.visible

	_check("2", "「继续」按钮只在有存档时出现",
		hidden_without_save and shown_with_save,
		"无档隐藏=%s　有档显示=%s" % [str(hidden_without_save), str(shown_with_save)])
	menu.queue_free()
	await _steps(2)


## 存档写读往返；读不存在的档返回空串而不是崩
func _t3_save_roundtrip() -> void:
	SaveManager.erase_save()
	var empty: String = SaveManager.read_progress()

	SaveManager.write_progress("res://scenes/stages/test_room.tscn")
	var back := SaveManager.read_progress()
	var has := SaveManager.has_save()

	_check("3", "存档写读往返一致，无档时读出空串",
		empty.is_empty() and has and back == "res://scenes/stages/test_room.tscn",
		"无档读出=\"%s\"　has_save=%s　读回=\"%s\"" % [empty, str(has), back])


## 语言按钮：点一下切到下一个语言，按钮文案跟着换，再点能绕回来
func _t4_language_button() -> void:
	var menu := MENU.instantiate()
	add_child(menu)
	await _steps(2)
	var lang_btn := menu.get_node("Panel/Box/Language") as Button
	var original := GameSettings.language
	var original_text := lang_btn.text

	lang_btn.pressed.emit()
	await _steps(2)
	var switched := GameSettings.language
	var switched_text := lang_btn.text

	lang_btn.pressed.emit()
	await _steps(2)
	var back := GameSettings.language

	var codes := GameSettings.SUPPORTED.keys()
	var expected_next := str(codes[(codes.find(original) + 1) % codes.size()])
	_check("4", "语言按钮循环切换，按钮文案即时刷新",
		switched == expected_next and switched != original and back == original
			and switched_text != original_text,
		"%s → %s → %s　按钮文案「%s」→「%s」" % [
			original, switched, back, original_text, switched_text])
	menu.queue_free()
	await _steps(2)
