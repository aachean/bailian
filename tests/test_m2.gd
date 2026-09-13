extends Node
## 《百炼》M2 自动验收 —— 主菜单 / 槽位存档 / 语言入口
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m2.tscn
##
## 存档模型（用户验收定的）：3 槽位 + 最近槽「继续」。这里的断言盯三种翻车：
## 槽位之间互相污染、读了不存在的档、新游戏把别的槽抹掉。

const MENU := preload("res://scenes/ui/main_menu.tscn")

var _pass := 0
var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》M2 自动验收 ═══")
	await _t1_menu_buttons()
	await _t2_continue_visibility()
	await _t3_slots_isolated()
	await _t4_language_button()
	await _t5_world_snapshot_roundtrip()
	await _t6_snapshot_survives_file()

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


func _wipe_all_slots() -> void:
	for s in 3:
		SaveManager.erase_slot(s)
	PlayerState.shards = 0
	PlayerState.upgrade_level = 0


## 菜单能摆出来：标题 + 五个按钮，文案是真话不是 key
func _t1_menu_buttons() -> void:
	var menu := MENU.instantiate()
	add_child(menu)
	await _steps(3)

	var missing := PackedStringArray()
	for node_path in ["Panel/Box/Start", "Panel/Box/Continue", "Panel/Box/Load",
			"Panel/Box/Language", "Panel/Box/Quit", "Slots/Box/Slot1", "Slots/Box/Slot3"]:
		if menu.get_node_or_null(node_path) == null:
			missing.append(node_path)
	var title := (menu.get_node("Title") as Label).text
	var start_text := (menu.get_node("Panel/Box/Start") as Button).text
	var ok := missing.is_empty() and not title.is_empty() and title != "UI_MENU_TITLE" \
		and not start_text.is_empty() and start_text != "UI_MENU_START"
	_check("1", "主菜单摆得出来：标题 + 五个按钮 + 三个存档位",
		ok,
		"标题=\"%s\" 开始=\"%s\" 缺节点 %d 个" % [title, start_text, missing.size()])
	menu.queue_free()
	await _steps(2)


## 「继续」只在有进度时出现；读档列表里空槽置灰、有档可选
func _t2_continue_visibility() -> void:
	_wipe_all_slots()
	var menu := MENU.instantiate()
	add_child(menu)
	await _steps(2)
	var cont := menu.get_node("Panel/Box/Continue") as Button
	var slot2 := menu.get_node("Slots/Box/Slot2") as Button

	# 全空：继续隐藏
	menu._refresh_texts()
	await _steps(2)
	var cont_hidden: bool = not cont.visible

	# 在槽 2 开档：继续出现（回最近槽），读档列表里槽 2 可选、槽 1 仍置灰
	SaveManager.start_new_game(2, "res://scenes/stages/town.tscn")
	menu._refresh_texts()
	await _steps(2)
	var cont_shown: bool = cont.visible
	menu._slot_mode = menu.SlotMode.LOAD
	menu._refresh_texts()
	var load_mode_ok: bool = (not slot2.disabled) \
		and (menu.get_node("Slots/Box/Slot1") as Button).disabled
	menu._slot_mode = menu.SlotMode.START
	menu._refresh_texts()

	_check("2", "「继续」回最近槽；读档列表空槽置灰",
		cont_hidden and cont_shown and load_mode_ok,
		"无进度隐藏=%s　有进度显示=%s　读档模式槽2可选/槽1置灰=%s" % [
			str(cont_hidden), str(cont_shown), str(load_mode_ok)])
	menu.queue_free()
	await _steps(2)


## 槽位隔离：三个槽各写各的，读写往返互不污染；新开槽不抹别的槽
func _t3_slots_isolated() -> void:
	_wipe_all_slots()
	SaveManager.start_new_game(1, "res://scenes/stages/town.tscn")
	SaveManager.write_progress("res://scenes/stages/level_1.tscn",
		{"player": {"hp": 50, "shards": 9, "upgrade": 2}, "enemies": []})

	SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")
	SaveManager.write_progress("res://scenes/stages/town.tscn",
		{"player": {"hp": 100, "shards": 1, "upgrade": 0}, "enemies": []})

	var s1 := SaveManager.read_state(1)
	var s3 := SaveManager.read_state(3)
	var s2_empty: bool = SaveManager.read_progress(2).is_empty()
	var s1_player := (s1.get("player", {}) as Dictionary)
	var s3_player := (s3.get("player", {}) as Dictionary)
	var isolated: bool = int(s1_player.get("shards", -1)) == 9 \
		and int(s3_player.get("shards", -1)) == 1 and s2_empty

	_check("3", "三个存档位互不干扰，新开一槽不抹别的槽",
		isolated and s2_empty,
		"槽1 铁=%s Lv=%s　槽2 无档=%s　槽3 铁=%s" % [
			str(s1_player.get("shards")), str(s1_player.get("upgrade")),
			str(s2_empty), str(s3_player.get("shards"))])


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


## 世界快照往返：这是「继续游戏 = 回到离开那一刻」的核心。
func _t5_world_snapshot_roundtrip() -> void:
	var room := (load("res://scenes/stages/test_room.tscn") as PackedScene).instantiate()
	add_child(room)
	for i in 5:
		await get_tree().physics_frame

	var player := room.get_node("Player")
	var walker := room.get_node("Walker")
	var player_h: Health = player.get_node("Health")
	var walker_h: Health = walker.get_node("Health")

	player_h.take_damage(13, Vector2.ZERO, false, 1)
	player.global_position = Vector2(410.0, 288.0)
	walker_h.take_damage(11, Vector2.ZERO, false, 1)
	walker.global_position = Vector2(260.0, 288.0)
	await get_tree().physics_frame

	var snap := room.call("collect") as Dictionary
	var want_player := {"hp": player_h.hp, "x": player.global_position.x, "y": player.global_position.y}
	var want_walker_hp: int = walker_h.hp

	player_h.restore(player_h.max_hp)
	player.global_position = Vector2(320.0, 280.0)
	walker_h.restore(walker_h.max_hp)
	walker.global_position = Vector2(46.0, 288.0)
	await get_tree().physics_frame

	room.call("_apply_state", snap)
	await get_tree().physics_frame

	var got_player := {"hp": player_h.hp, "x": player.global_position.x, "y": player.global_position.y}
	var same_player: bool = int(got_player.hp) == int(want_player.hp) \
		and absf(got_player.x - want_player.x) < 2.0 and absf(got_player.y - want_player.y) < 2.0
	var same_walker: bool = walker_h.hp == want_walker_hp \
		and absf(walker.global_position.x - 260.0) < 2.0

	_check("5", "继续游戏恢复世界快照：玩家与怪的血量位置都是离开时的样子",
		same_player and same_walker,
		"玩家 %d/%d @(%.0f, %.0f)（期望 %d @%.0f）　怪血 %d（期望 %d）@x=%.0f（期望 260）" % [
			got_player.hp, player_h.max_hp, got_player.x, got_player.y,
			want_player.hp, want_player.x, walker_h.hp, want_walker_hp, walker.global_position.x])
	room.queue_free()
	await get_tree().process_frame


## 快照随档序列化：写进存档文件再读回来，一个字段都不能少
func _t6_snapshot_survives_file() -> void:
	var snap := {"player": {"hp": 66, "x": 123.0, "y": 288.0}, "enemies": [
		{"node": "Walker", "hp": 19, "x": 200.0, "y": 288.0}]}
	SaveManager.start_new_game(2, "res://scenes/stages/test_room.tscn")
	SaveManager.write_progress("res://scenes/stages/test_room.tscn", snap)
	var back := SaveManager.read_state()

	var p := back.get("player", {}) as Dictionary
	var e: Array = back.get("enemies", [])
	var ok: bool = int(p.get("hp", -1)) == 66 and absf(float(p.get("x", 0)) - 123.0) < 0.01 \
		and e.size() == 1 and int((e[0] as Dictionary).get("hp", -1)) == 19

	SaveManager.write_progress("res://scenes/stages/test_room.tscn", {})   # 恢复干净进度
	_check("6", "快照写进存档文件再读回，字段一个不少",
		ok, "玩家血 %s @%s　怪 [0] 血 %s" % [
			str(p.get("hp")), str(p.get("x")),
			str((e[0] as Dictionary).get("hp", "?")) if e.size() > 0 else "?"])
