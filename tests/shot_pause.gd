extends Node
## 暂停菜单与设置面板的观感截图。
##     godot --path <项目根> res://tests/shot_pause.tscn      # 输出到 build/shots/
##
## 为什么必须靠截图（而不是断言）：这一版全是**画出来的东西** ——
## 「回到城镇（放弃本趟）」这种长文案会不会把按钮撑出面板、滑条与百分比
## 挤在一行会不会串行、光圈在不在光标那一行。断言验得到文字，
## 验不到「它有没有溢出或重叠」（项目在横幅那次就是靠截图才发现
## CanvasLayer 下的 Control 用 set_anchors_preset 不生效、字从屏幕上溢出去）。
##
## 五张：暂停菜单（副本内，五项全在）→ 设置面板 → 静音那一行 →
## 主菜单（「设置」替代了原来的「语言」）→ 主菜单里打开的设置面板。

const TOWN := preload("res://scenes/stages/town.tscn")
const MENU := preload("res://scenes/ui/main_menu.tscn")

const SETTINGS_PATH := "user://settings.cfg"

var _town: Node
## 截图会改音量（按 J 静音那一张），而那是**玩家真正在用的那一份**设置 ——
## 先备份，收尾原样还回去。不备份的话：跑一次截图 = 神的音效被静音，
## 而他下次开游戏只会觉得「声音怎么没了」（同 SaveGuard 的理由）
var _bak_settings: PackedByteArray = PackedByteArray()
var _had_settings := false


## 本脚本冒充「副本根节点」：暂停菜单用「当前场景能不能 restart()」
## 判这是副本还是安全区，定义了 restart 才是副本 —— 才会显示「回到城镇」
func restart() -> void:
	pass


func _ready() -> void:
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_bak_settings = FileAccess.get_file_as_bytes(SETTINGS_PATH)

	_town = TOWN.instantiate()
	add_child(_town)
	await _frames(6)
	var player := _town.get_node("Player")
	var pm := player.get_node("PauseMenu")

	# ── 一、暂停菜单：五项全在（副本里，所以「回到城镇」可见）────────
	_press("ui_cancel")
	await _frames(5)
	_release("ui_cancel")
	await _frames(4)
	await _shot("pause_menu.png")

	# ── 二、设置面板叠在暂停菜单上 ────────────────────────────────
	(pm.call("button", &"settings") as Button).pressed.emit()
	await _frames(4)
	await _shot("pause_settings.png")

	# ── 三、静音那一行：光标移到「音效」，按 J；写的是「静音」不是「0%」──
	_tap_key(KEY_DOWN)
	await _frames(2)
	_tap_key(KEY_J)
	await _frames(3)
	await _shot("pause_settings_muted.png")

	_tap_key(KEY_ESCAPE)
	await _frames(3)
	_tap_key(KEY_ESCAPE)
	await _frames(3)
	_town.queue_free()
	await _frames(3)

	# ── 四、主菜单：原来那行「语言」换成了「设置」──────────────────
	var menu := MENU.instantiate()
	add_child(menu)
	await _frames(10)
	await _shot("menu.png")

	# ── 五、主菜单里同一块设置面板（与暂停菜单共用一份场景）────────
	(menu.get_node("Panel/Box/Settings") as Button).pressed.emit()
	await _frames(6)
	await _shot("menu_settings.png")

	_restore_settings()
	get_tree().paused = false
	get_tree().quit()


func _restore_settings() -> void:
	if _had_settings:
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_bak_settings)
			f.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


func _frames(n: int) -> void:
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


func _tap_key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
