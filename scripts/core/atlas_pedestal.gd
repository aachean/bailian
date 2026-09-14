extends Area2D
## 舆图台：安全区里的一件设施。走近 → 提示「按 P 打开舆图」→ 按 P 打开舆图。
##
## ── 为什么是「走近 → 出提示 → 按键」而不是「走上去就弹」───────
## 这是安全区里已经有的语言：铁砧（按 J 强化）、NPC（按 J 交谈）都是这样。
## 不发明第二套交互，玩家不用学新东西（docs/design-conventions.md）。
##
## ── 它只是个**引导物** ────────────────────────────────────────
## 界面本身挂在玩家身上（与 HUD / 暂停菜单同一套挂法）。
## 本节点负责的只有两件事：在安全区里把「这里可以开舆图」说出来，
## 以及把 P 转成一次打开动作。玩家在关卡里过关后自动开舆图，不经过这里。

var _player: Node2D = null

@onready var _title: Label = $Title
@onready var _hint: Label = $Hint


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if not GameSettings.language_changed.is_connected(_refresh):
		GameSettings.language_changed.connect(_refresh)
	_refresh()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player = body
		_refresh()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player = null
		_refresh()


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	if Input.is_action_just_pressed("atlas"):
		_open()


## 打开玩家身上的舆图。别的模态界面开着时不开 —— 那几个界面抢同一批按键，
## 叠起来只会互相打架（与 HUD / 暂停菜单互查 is_open 是同一套约定）
func _open() -> void:
	var atlas := _player.get_node_or_null("Atlas")
	if atlas == null or not atlas.has_method("open"):
		return
	if bool(atlas.call("is_open")):
		return
	if _other_ui_open():
		return
	atlas.call("open")


func _other_ui_open() -> bool:
	if _player == null:
		return false
	var hud := _player.get_node_or_null("HUD")
	if hud != null and hud.has_method("is_bag_open") and bool(hud.call("is_bag_open")):
		return true
	if hud != null and hud.has_method("is_skill_panel_open") \
			and bool(hud.call("is_skill_panel_open")):
		return true
	var pm := _player.get_node_or_null("PauseMenu")
	if pm != null and pm.has_method("is_open") and bool(pm.call("is_open")):
		return true
	var box := get_tree().get_first_node_in_group("dialogue_box")
	return box != null and bool(box.call("is_open"))


## 参数必须留着：Godot 按参数个数严格匹配信号连接（少一个会在 emit 时静默报错）
func _refresh(_locale: String = "") -> void:
	_title.text = tr("UI_PEDESTAL_TITLE")
	_hint.text = tr("UI_PEDESTAL_HINT") if _player != null else ""
