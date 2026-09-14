extends Node
## 《百炼》M3 增量 3 自动验收：对话框 / NPC / 主线推进
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m6.tscn
##
## 在城镇里跑，因为主线对话就在城镇发生。

const TOWN := preload("res://scenes/stages/town.tscn")

const SMITH_X := 480.0
const SMITH_REACH := 44.0        # 站到离 NPC 这个距离内

var _pass := 0
var _fail := 0
var _town: Node2D
var _player: Node
var _smith: Node
var _box: Node


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》M3 增量 3 自动验收 · 对话与主线 ═══")
	_town = TOWN.instantiate()
	add_child(_town)
	for i in 5:
		await get_tree().physics_frame
	_player = _town.get_node("Player")
	_smith = _town.get_node("Smith")
	_box = _town.get_node("Player/DialogueBox")
	_reset_progress()

	await _t1_talk_starts_dialogue()
	await _t2_pauses_world()
	await _t3_typewriter_then_skip()
	await _t4_advance_lines()
	await _t5_close_and_reward()
	await _t6_repeat_dialogue_no_second_gift()
	await _t7_no_other_panel_stacks()
	await _t8_no_key_leak()

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().paused = false          # 安全网：绝不能带着暂停退出
	get_tree().quit(0 if _fail == 0 else 1)


## 包里有没有这个**型号**的装备。
## 背包里存的是实例 uid（`路径#序号`），直接写 bag.has(路径) 永远为假 ——
## 那会让断言静默变成「永远不通过」
func _in_bag(path: String) -> bool:
	for u in PlayerState.bag:
		if PlayerState.path_of(str(u)) == path:
			return true
	return false


func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-3s %s\n              %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-3s %s\n              %s" % [id, desc, detail])


func _pframes(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)


func _release(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)


## 按一下 J（对话里 J 是「继续」）
func _tap_confirm() -> void:
	_press("attack")
	await _pframes(3)
	_release("attack")
	await _pframes(3)


## 把当前这句先显完（打字中按 J 只会显完、不会翻页 —— 这是设计，不是 bug）
func _reveal_current() -> void:
	var text := _box.get_node("Root/Panel/Text") as Label
	if text.visible_characters != -1:
		await _tap_confirm()


## 翻到下一句：先确保当前句显完，再按一下
func _next_line() -> void:
	await _reveal_current()
	await _tap_confirm()


func _reset_progress() -> void:
	PlayerState.set_equipment({}, [])
	PlayerState.flags.clear()
	PlayerState.shards = 0
	PlayerState.set_equipment(PlayerState.equipped, PlayerState.bag, {})   # 强化钉回基线（逐件之后没有全局等级了）
	PlayerState.level = 1
	PlayerState.exp = 0


## 站到铁匠身边（走完整操作链太慢，这里只关心 Area2D 有没有认出玩家）
func _stand_near_smith() -> void:
	_player.global_position = Vector2(SMITH_X - 30.0, 288.0)
	_player.velocity = Vector2.ZERO
	var n := 0
	while not _player.is_on_floor() and n < 60:
		await get_tree().physics_frame
		n += 1
	await _pframes(4)


## 走近铁匠按 J：对话框开、说话人对
func _t1_talk_starts_dialogue() -> void:
	await _stand_near_smith()
	var hint: String = (_smith.get_node("Hint") as Label).text
	var near: bool = _player.global_position.distance_to(_smith.global_position) < SMITH_REACH
	await _tap_confirm()
	var open: bool = bool(_box.call("is_open"))
	var root_visible: bool = (_box.get_node("Root") as Control).visible
	var speaker: String = (_box.get_node("Root/Panel/Speaker") as Label).text
	var name_shown: String = (_smith.get_node("Name") as Label).text
	_check("1", "走到铁匠身边按 J：对话框弹出，说话人是老铁匠",
		near and not hint.is_empty() and open and root_visible \
			and speaker == tr("NPC_SMITH") and name_shown == tr("NPC_SMITH"),
		"进范围=%s（提示「%s」）　对话框开=%s　说话人「%s」　头顶名字「%s」" % [
			str(near), hint, str(open), speaker, name_shown])


## 对话打开时世界真暂停
func _t2_pauses_world() -> void:
	var paused: bool = get_tree().paused
	var player_frozen: bool = not _player.can_process()
	_check("2", "对话期间世界真暂停（怪不会打你，玩家不动）",
		paused and player_frozen,
		"场景树暂停=%s　玩家被冻结=%s" % [str(paused), str(player_frozen)])


## 打字机：先逐字显，按 J 立刻显完（不翻页）
func _t3_typewriter_then_skip() -> void:
	var text := _box.get_node("Root/Panel/Text") as Label
	# 刚进对话时是逐字显示的中间态
	await _pframes(6)
	var partial: int = text.visible_characters
	var total: int = text.text.length()
	var typing: bool = partial >= 0 and partial < total
	await _tap_confirm()             # 打字中按 J：应该立刻显完，且不翻页
	var first_line: String = tr("DLG_SMITH_1")
	var shown_all: bool = text.visible_characters == -1
	var same_line: bool = text.text == first_line
	_check("3", "台词逐字显示；没显完时按 J 立刻显完（不会跳句）",
		typing and shown_all and same_line,
		"显示中 %d/%d 字　按 J 后全显=%s　仍是第 1 句=%s" % [
			partial, total, str(shown_all), str(same_line)])


## 显完之后按 J 翻到下一句
func _t4_advance_lines() -> void:
	var text := _box.get_node("Root/Panel/Text") as Label
	await _next_line()               # → 第 2 句
	await _reveal_current()
	var second_text: String = text.text
	await _next_line()               # → 第 3 句
	await _reveal_current()
	var third_text: String = text.text
	_check("4", "台词一句句翻：第 2 句 → 第 3 句",
		second_text == tr("DLG_SMITH_2") and third_text == tr("DLG_SMITH_3"),
		"第 2 句「%s」　第 3 句「%s」" % [second_text, third_text])


## 最后一句之后按 J：关闭 + 世界恢复 + 真的给了一把剑
func _t5_close_and_reward() -> void:
	await _next_line()               # → 第 4 句
	await _reveal_current()
	var fourth: bool = (_box.get_node("Root/Panel/Text") as Label).text == tr("DLG_SMITH_4")
	await _tap_confirm()             # 关掉

	var closed: bool = not bool(_box.call("is_open"))
	var resumed: bool = not get_tree().paused
	var root_hidden: bool = not (_box.get_node("Root") as Control).visible
	var got: bool = _in_bag("res://data/items/iron_sword.tres")
	var flagged: bool = PlayerState.has_flag(&"met_smith")
	_check("5", "说完最后一句按 J：对话关闭、世界恢复，并获得铁匠给的一把剑",
		fourth and closed and resumed and root_hidden and got and flagged,
		"第 4 句=%s　关闭=%s　恢复=%s　剑进背包=%s　进度标记=%s" % [
			str(fourth), str(closed), str(resumed), str(got), str(flagged)])


## 再聊一次：换了台词，且不再重复给东西
func _t6_repeat_dialogue_no_second_gift() -> void:
	await _pframes(14)               # 等 NPC 的「刚关掉」锁走完
	var bag_before: int = PlayerState.bag.size()
	await _tap_confirm()
	await _pframes(4)
	var open: bool = bool(_box.call("is_open"))
	var text: String = (_box.get_node("Root/Panel/Text") as Label).text
	var is_repeat: bool = text == tr("DLG_SMITH_R1")
	# 一路按到关闭
	var guard := 0
	while bool(_box.call("is_open")) and guard < 10:
		await _tap_confirm()
		guard += 1
	var bag_after: int = PlayerState.bag.size()
	_check("6", "第二次聊天换了一套台词，且不会再给一把剑",
		open and is_repeat and bag_after == bag_before,
		"重开=%s　台词「%s」（期望 %s）　背包 %d → %d 件" % [
			str(open), text, tr("DLG_SMITH_R1"), bag_before, bag_after])


## 对话开着时，Esc / B 不该叠出别的界面
func _t7_no_other_panel_stacks() -> void:
	await _pframes(14)               # 等 NPC 锁走完
	await _tap_confirm()             # 重新开对话
	var open: bool = bool(_box.call("is_open"))

	_press("ui_cancel")
	await _pframes(3)
	_release("ui_cancel")
	await _pframes(3)
	var pm := _player.get_node("PauseMenu")
	var paused_menu: bool = bool(pm.call("is_open"))

	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(3)
	var hud := _player.get_node("HUD")
	var bag_open: bool = bool(hud.call("is_bag_open"))

	var still_talking: bool = bool(_box.call("is_open"))
	# 收尾：把对话关掉
	var guard := 0
	while bool(_box.call("is_open")) and guard < 10:
		await _tap_confirm()
		guard += 1
	_check("7", "对话开着时按 Esc / B 不会叠出暂停菜单或背包",
		open and (not paused_menu) and (not bag_open) and still_talking,
		"对话中=%s　暂停菜单=%s　背包=%s　仍在对话=%s" % [
			str(open), str(paused_menu), str(bag_open), str(still_talking)])


## 对话文本里不能出现翻译 key 本身（漏翻静默失败的老探针）
func _t8_no_key_leak() -> void:
	await _pframes(14)               # 等 NPC 锁走完
	await _tap_confirm()
	await _pframes(6)

	var texts: Array[String] = []
	for path in ["Root/Panel/Speaker", "Root/Panel/Text", "Root/Panel/Hint"]:
		var n := _box.get_node_or_null(path)
		if n is Label:
			texts.append((n as Label).text)
	texts.append((_smith.get_node("Name") as Label).text)
	texts.append((_smith.get_node("Hint") as Label).text)

	var leaks := PackedStringArray()
	var re := RegEx.new()
	re.compile("(UI|DLG|NPC|PANEL|HUD|ITEM)_[A-Z_0-9]+")
	for t in texts:
		for m in re.search_all(t):
			leaks.append(m.get_string())

	var guard := 0
	while bool(_box.call("is_open")) and guard < 10:
		await _tap_confirm()
		guard += 1

	_check("8", "对话框与 NPC 文本里不出现翻译 key 本身",
		leaks.is_empty(),
		"扫了 %d 段文本　泄漏：%s" % [
			texts.size(), "无" if leaks.is_empty() else ", ".join(leaks)])
