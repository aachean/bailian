extends CanvasLayer
## 死亡界面：倒下之后**给两条路选**（2026-09-14 神的要求）。
##
##   1. **重新开始** —— 重开这个副本，从第 1 屏第 1 波重来
##   2. **返回城镇** —— 回安全区，满血满蓝，这一趟的进度不算数
##
## ── 为什么是二选一而不是自动重开 ───────────────────────────────
## 第一版是「死了自动重开本关」。神否掉了：不给选，等于替玩家决定了
## 「你必须再来一次」。想先出去买点东西、想让手歇一下、想换个副本 ——
## 这些都得先被迫死磕一遍，这是最不该发生的事。
## 死亡是玩家最需要掌控感的时刻，二选一是最低限度的尊重。
##
## ── 挂法与互斥 ────────────────────────────────────────────────
## 与 HUD / 暂停菜单 / 舆图同一套：挂在玩家下、`process_mode = ALWAYS`、
## 打开即 `get_tree().paused = true`。它**打开时把别的模态界面让开** ——
## 倒下的那一刻不该还叠着背包面板。
##
## 这个界面**不给关掉**（没有 Esc）：两条路都是"离开这一趟"，
## 没有第三条叫"留在这儿"。

const TOWN_PATH := "res://scenes/stages/town.tscn"
const CURSOR := "▶ "
const INDENT := "　"        # 全角空格：与光标标记同宽，换行不跳

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Panel/Title
@onready var _restart_btn: Button = $Root/Panel/Box/Restart
@onready var _town_btn: Button = $Root/Panel/Box/Town
@onready var _hint: Label = $Root/Panel/Hint

var _rows: Array[Button] = []
var _cursor := 0


func _ready() -> void:
	_root.visible = false
	_rows = [_restart_btn, _town_btn]
	_restart_btn.pressed.connect(_on_restart)
	_town_btn.pressed.connect(_on_town)
	if not GameSettings.language_changed.is_connected(_on_language_changed):
		GameSettings.language_changed.connect(_on_language_changed)
	_refresh_texts()


## 参数必须留着：Godot 按参数个数严格匹配信号连接，少一个会「连上了但一调用就报错」
func _on_language_changed(_locale: String = "") -> void:
	if _root.visible:
		_refresh_texts()


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_cursor = 0
	_close_other_modal()
	_root.visible = true
	get_tree().paused = true
	_refresh_texts()


## 别的模态界面（背包 / 技能面板 / 暂停菜单）先让开。
## 它们都是真暂停的界面，叠在一起就是两个界面抢同一批按键
func _close_other_modal() -> void:
	var hud := get_parent().get_node_or_null("HUD")
	if hud != null and hud.has_method("close_all_panels"):
		hud.call("close_all_panels")
	var pm := get_parent().get_node_or_null("PauseMenu")
	if pm != null and pm.has_method("is_open") and bool(pm.call("is_open")):
		pm.call("_close")


func close() -> void:
	_root.visible = false
	get_tree().paused = false


# ── 输入 ───────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
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


func _move(dir: int) -> void:
	if _rows.is_empty():
		return
	_cursor = wrapi(_cursor + dir, 0, _rows.size())
	_refresh_texts()


func _activate() -> void:
	if _cursor < 0 or _cursor >= _rows.size():
		return
	_rows[_cursor].emit_signal("pressed")


func _refresh_texts(_locale: String = "") -> void:
	_title.text = tr("UI_DEATH_TITLE")
	_hint.text = tr("UI_DEATH_HINT")
	var names := [tr("UI_DEATH_RESTART"), tr("UI_DEATH_TOWN")]
	for i in _rows.size():
		var mark := CURSOR if i == _cursor else INDENT
		_rows[i].text = mark + names[i]


# ── 给断言看的 ─────────────────────────────────────────────────

## 两个选项各自现在显示成什么（含光标标记）。断言拿它扫翻译泄漏
func row_texts() -> Array[String]:
	var out: Array[String] = []
	for b in _rows:
		out.append(b.text)
	return out


## 光标停在第几行（0 起）
func cursor() -> int:
	return _cursor


## 某个选项真的接了动作没有 —— 光看文字只能说"画了"，`pressed` 上有没有东西
## 才是"按下去会发生事"。没接的按钮是最静默的一种失败：看着像能点
func is_row_wired(i: int) -> bool:
	if i < 0 or i >= _rows.size():
		return false
	return _rows[i].pressed.get_connections().size() > 0


# ── 两条路 ─────────────────────────────────────────────────────

## 重新开始：重开这个副本。**先解暂停** —— `paused` 挂在场景树上，
## 不解开的话新场景一进来就是暂停的，看起来像卡死
func _on_restart() -> void:
	get_tree().paused = false
	_root.visible = false
	var root := get_tree().current_scene
	if root != null and root.has_method("restart"):
		root.call("restart")
	else:
		get_tree().reload_current_scene()


## 返回城镇：回安全区。玩家在新场景 `_ready` 时满血满蓝（回城即治疗）。
## 换场景 = 世界重置，所以快照要清掉，不能把这一趟的尸体位置带回去
func _on_town() -> void:
	get_tree().paused = false
	_root.visible = false
	SaveManager.write_progress(TOWN_PATH, {})
	get_tree().change_scene_to_file(TOWN_PATH)
