extends CanvasLayer
## 暂停菜单：Esc 打开（游戏真暂停）。
## **继续游戏 / 保存游戏 / 回到城镇 / 设置 / 回主菜单**。
##
## 存档时机的设计（用户验收定的）：玩的过程中要能主动保存，
## 不能只在回主菜单时才写档。保存 = 把当前世界快照写进当前槽位。
##
## process_mode 必须是 ALWAYS：打开菜单要靠它收 Esc（游戏未暂停时），
## 暂停中收 Esc 关菜单（游戏已暂停时）——其他节点全部照常被暂停冻结。
##
## ── 「回到城镇」为什么带「放弃本趟」四个字 ────────────────────
## 它跟死亡界面的「返回城镇」是**同一件事**：换场景 = 世界重置，
## 这一趟的副本进度不算数（快照写成空的）。玩家按之前必须知道这个代价 ——
## **不能静默地丢掉整趟进度**。保存按钮就在上面一行，想留先按那个。
##
## ── 「设置」为什么放在这一层而不是另开一层 ────────────────────
## 设置面板是独立场景（主菜单也用它），这里只负责把界面叫出来。
## 本节点**不管设置面板的暂停** —— 谁开的面板谁管暂停（见
## hud.close_all_panels 那次的教训：让路只管可见性）。

## 安全区（城镇）场景。与死亡界面用的是同一个路径
const TOWN_PATH := "res://scenes/stages/town.tscn"
const CURSOR_MARK := "▶ "
const INDENT := "　"        # 全角空格：与光标标记同宽，换行不跳

@onready var _root: Control = $Root
@onready var _continue_btn: Button = $Root/Panel/Box/Continue
@onready var _save_btn: Button = $Root/Panel/Box/Save
@onready var _town_btn: Button = $Root/Panel/Box/Town
@onready var _settings_btn: Button = $Root/Panel/Box/Settings
@onready var _menu_btn: Button = $Root/Panel/Box/Menu
@onready var _hint: Label = $Root/Panel/Hint
@onready var _settings: Node = $SettingsPanel

var _rows: Array[Button] = []
var _cursor := 0
## 这一趟已经存过档了没。存过之后保存那一行改成「已保存 ✓」（不静默：得让玩家看见）
var _saved := false


func _ready() -> void:
	_root.visible = false
	_rows = [_continue_btn, _save_btn, _town_btn, _settings_btn, _menu_btn]
	_continue_btn.pressed.connect(_close)
	_save_btn.pressed.connect(_on_save)
	_town_btn.pressed.connect(_goto_town)
	_settings_btn.pressed.connect(_on_settings)
	_menu_btn.pressed.connect(_on_back_to_menu)
	if not GameSettings.language_changed.is_connected(_refresh_texts):
		GameSettings.language_changed.connect(_refresh_texts)
	_refresh_texts()


## ALWAYS 模式：暂停与否都收得到
func _unhandled_input(event: InputEvent) -> void:
	# 设置面板开着时本节点不吃按键 —— 它叠在本节点上面，那一层才是当前焦点。
	# **同一帧刚关掉**那种情况也要算进去：设置面板先收到 Esc 并关掉自己之后，
	# 本节点再读 is_open() 就是 false，于是同一下 Esc 会把暂停菜单也一起关掉
	if _settings_open() or _settings_closed_this_frame():
		return
	if event.is_action_pressed("ui_cancel"):
		# 装备背包 / 对话框 / 舆图 / 死亡界面开着时不抢 Esc —— 这几个界面都要用同一批按键，
		# 叠起来只会互相打架。先关掉手头那个，再按 Esc
		if not _root.visible \
				and (_bag_open() or _dialogue_open() or _atlas_open() or _death_open()):
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _root.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				_move(-1)
			KEY_DOWN, KEY_S:
				_move(1)
			KEY_J, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate()
			_:
				return
		get_viewport().set_input_as_handled()


## 菜单是否开着（HUD 靠它判断「该不该叠背包」）
func is_open() -> bool:
	return _root.visible


func _settings_open() -> bool:
	return _settings != null and bool(_settings.call("is_open"))


## 设置面板**就在这一帧**关掉了自己吗？见 `_unhandled_input` 与
## `settings_panel.closed_at_frame()` 的说明 —— 这是「一下 Esc 别关两层」的守门人
func _settings_closed_this_frame() -> bool:
	return _settings != null \
		and int(_settings.call("closed_at_frame")) == Engine.get_process_frames()


func _bag_open() -> bool:
	var hud := get_parent().get_node_or_null("HUD")
	return hud != null and hud.has_method("is_bag_open") and bool(hud.call("is_bag_open"))


func _dialogue_open() -> bool:
	var box := get_tree().get_first_node_in_group("dialogue_box")
	return box != null and bool(box.call("is_open"))


## 舆图开着时让路。它和本节点一样挂在玩家身上
func _atlas_open() -> bool:
	var at := get_parent().get_node_or_null("Atlas")
	return at != null and at.has_method("is_open") and bool(at.call("is_open"))


## 死亡界面同理。**它比本节点更该拿到按键** ——
## 死的那一刻再弹一个暂停菜单出来，玩家面对的就是两层界面
func _death_open() -> bool:
	var dm := get_parent().get_node_or_null("DeathMenu")
	return dm != null and dm.has_method("is_open") and bool(dm.call("is_open"))


func toggle() -> void:
	if _root.visible:
		_close()
	else:
		_open()


func _open() -> void:
	# 「在安全区就不给这一项」：人在城镇里点「回到城镇」等于什么都没发生 ——
	# 而**按了看不出效果**是这个项目最不接受的一种失败。
	# 判据见 `_in_safe_zone()`
	_town_btn.visible = not _in_safe_zone()
	_cursor = 0
	_saved = false
	_root.visible = true
	get_tree().paused = true
	_refresh_texts()


func _close() -> void:
	# 设置面板还开着的话一起收掉：本节点关了它却留着，会变成
	# 「游戏在跑，上面还压着一个设置面板」—— 而且它收 Esc，谁也关不掉它
	if _settings_open():
		_settings.call("close")
	_root.visible = false
	get_tree().paused = false


## 参数必须留着：Godot 按参数个数严格匹配信号连接，少一个会「连上了但一调用就报错」，
## 界面静默不刷新（M1 的语言切换用例抓到过这个家族）
func _refresh_texts(_locale: String = "") -> void:
	var rows := _nav_rows()
	if _cursor >= rows.size():
		_cursor = maxi(rows.size() - 1, 0)
	for i in rows.size():
		var mark := CURSOR_MARK if i == _cursor else INDENT
		rows[i].text = mark + _label_of(rows[i])
	_hint.text = tr("UI_PAUSE_HINT")


## 一行该写什么。**按按钮查，不按序号查** ——
## 「回到城镇」在城镇里是藏起来的，那时行的序号和名字就对不上了，
## 按下标取名字会让光标停在一行、字写在另一行
func _label_of(b: Button) -> String:
	if b == _continue_btn:
		return tr("UI_PAUSE_CONTINUE")
	if b == _save_btn:
		return tr("UI_PAUSE_SAVED") if _saved else tr("UI_PAUSE_SAVE")
	if b == _town_btn:
		return tr("UI_PAUSE_TOWN")
	if b == _settings_btn:
		return tr("UI_PAUSE_SETTINGS")
	return tr("UI_PAUSE_MENU")


## 光标可停的行。**藏起来的不算** —— 光标能停到一个看不见的按钮上，
## 玩家按 J 只会觉得「按了没反应」
func _nav_rows() -> Array[Button]:
	var out: Array[Button] = []
	for b in _rows:
		if b.visible:
			out.append(b)
	return out


func _move(dir: int) -> void:
	var n := _nav_rows().size()
	if n <= 0:
		return
	_cursor = wrapi(_cursor + dir, 0, n)
	_refresh_texts()


func _activate() -> void:
	var rows := _nav_rows()
	if _cursor < 0 or _cursor >= rows.size():
		return
	rows[_cursor].emit_signal("pressed")


## 这个场景路径是不是安全区。**安全区只有城镇一个。**
##
## ── 判据是场景文件路径，不是「有没有 restart()」────────────────
## 第一版写的是「能 `restart()` 的就是副本」（照 death_menu 找当前关卡的办法）。
## **那个判据是错的**：城镇与副本**共用同一个根脚本 `stage.gd`**，
## 而 `restart()` 就在它里面 —— 于是城镇也会被判成副本，
## 「回到城镇」在城镇里照样显示出来，正好是这条规则要防的事。
## 死亡界面那边能用方法名，是因为它只关心「这场景能不能重开」这个**能力**，
## 不是「这是哪种场景」。两件事，不能互相借。
##
## 抽成方法是为了让断言能单独验两个分支：断言没法真的把 `current_scene`
## 换成城镇（换场景会把测试自己整个换掉），所以规则本身得能单独喂进去
func is_safe_zone(path: String) -> bool:
	return path == TOWN_PATH


func _in_safe_zone() -> bool:
	var sc := get_tree().current_scene
	return sc == null or is_safe_zone(sc.scene_file_path)


# ── 按钮动作 ───────────────────────────────────────────────────

## 保存：当前关卡的完整快照写进当前槽位。暂停不影响函数调用
func _on_save() -> void:
	var level := get_tree().current_scene
	if level != null and level.has_method("collect"):
		SaveManager.write_progress(level.scene_file_path, level.call("collect"))
	_saved = true
	_refresh_texts()


func _on_settings() -> void:
	if _settings != null:
		_settings.call("open")


## 回到城镇：**与死亡界面的「返回城镇」走同一条路** ——
## 写空快照（换场景 = 世界重置，不能把这一趟的位置带回城镇）+ 解暂停 + 换场景。
##
## 这一条**没法在断言里真的按下去**：`change_scene_to_file` 会把测试自己那个
## 场景整个换掉，测试当场就死了。所以断言验的是「按钮在不在、接没接动作、
## 该不该显示」，以及这个常量指向的是不是城镇 —— 与 test_m9 验死亡界面同款。
func _goto_town() -> void:
	get_tree().paused = false
	_root.visible = false
	SaveManager.write_progress(TOWN_PATH, {})
	get_tree().change_scene_to_file(TOWN_PATH)


func _on_back_to_menu() -> void:
	var level := get_tree().current_scene
	if level != null and level.has_method("collect"):
		SaveManager.write_progress(level.scene_file_path, level.call("collect"))
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# ── 给断言看的 ─────────────────────────────────────────────────

## 每行现在显示成什么（含光标标记）。断言拿它扫翻译泄漏
func row_texts() -> Array[String]:
	var out: Array[String] = []
	for b in _nav_rows():
		out.append(b.text)
	return out


## 光标停在第几行（0 起，只数看得见的行）
func cursor() -> int:
	return _cursor


## 某个按钮真的接了动作没有。光看文字只能说「画了」，
## `pressed` 上有没有东西才是「按下去会发生事」
func is_wired(b: Button) -> bool:
	return b.pressed.get_connections().size() > 0


func town_visible() -> bool:
	return _town_btn.visible


## 按名字取按钮。
## **参数名不能叫 `name`** —— 那会遮蔽 `Node.name`，GDScript 把整个函数判为
## 编译不过，而**其余方法照常能用**：现象于是是「只有这一个方法不存在」，
## 很难往参数名上想（这条是实测撞出来的，原本那个版本就是这么消失的）
func button(which: StringName) -> Button:
	match which:
		&"continue": return _continue_btn
		&"save": return _save_btn
		&"town": return _town_btn
		&"settings": return _settings_btn
	return _menu_btn


func settings_panel() -> Node:
	return _settings
