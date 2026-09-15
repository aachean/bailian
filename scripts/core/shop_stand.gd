extends Area2D
## 城镇商店台：站上来按 J 打开**商店**（买装备）。
##
## ── 开张的门（计划 §3.7）─────────────────────────────────────
## 商店**随第一个副本首通解锁**。没开张时站上来只给一句提示 ——
## 建筑一直摆在那儿：玩家从一开始就知道「这儿将来有家店」，
## 通关砺场的奖励感落在「店开门了」这件事上，而不是凭空冒出一栋房子。
##
## 交互方式与铁砧同一套语言（走近 → 出提示 → 按 J），不发明第二套，
## 见 docs/design-conventions.md。

## 开张的门挂哪个副本（数据驱动：场景上配 id，不写死在代码里）
@export var unlock_dungeon: StringName = &""

var _player: Node2D = null

@onready var _label: Label = $Label


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if not GameSettings.language_changed.is_connected(_refresh):
		GameSettings.language_changed.connect(_refresh)
	if not PlayerState.gold_changed.is_connected(_refresh):
		PlayerState.gold_changed.connect(_refresh)
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
	if _player == null or not _unlocked():
		return
	if Input.is_action_just_pressed("attack"):
		_open()


## 开张没有：通关解锁副本（unlock_dungeon 在场景上配）就开。
## 真相在 SaveManager 的通关表里，这里不存第二份
func _unlocked() -> bool:
	var id := unlock_dungeon
	return id != &"" and SaveManager.is_cleared(id)


## 打开玩家身上的商店面板。已经开着 / 别的模态界面开着都不重复开 ——
## 那几个界面抢同一批按键，叠起来只会互相打架（与铁砧同一套约定）
func _open() -> void:
	var panel := _player.get_node_or_null("ShopPanel")
	if panel == null or not panel.has_method("open"):
		return
	if bool(panel.call("is_open")):
		return
	if _other_ui_open():
		return
	panel.call("open")


func _other_ui_open() -> bool:
	var hud := _player.get_node_or_null("HUD")
	if hud != null and hud.has_method("is_bag_open") and bool(hud.call("is_bag_open")):
		return true
	if hud != null and hud.has_method("is_skill_panel_open") \
			and bool(hud.call("is_skill_panel_open")):
		return true
	var pm := _player.get_node_or_null("PauseMenu")
	if pm != null and pm.has_method("is_open") and bool(pm.call("is_open")):
		return true
	var atlas := _player.get_node_or_null("Atlas")
	if atlas != null and atlas.has_method("is_open") and bool(atlas.call("is_open")):
		return true
	var fp := _player.get_node_or_null("ForgePanel")
	if fp != null and fp.has_method("is_open") and bool(fp.call("is_open")):
		return true
	var box := get_tree().get_first_node_in_group("dialogue_box")
	return box != null and bool(box.call("is_open"))


## 提示牌。没开张说没开张；开张了报元宝余额 ——
## 「能不能买得起」是玩家站在这儿第一个想知道的事（与铁砧报精铁同一逻辑）
##
## 参数必须留着且**不带类型**：本方法同时挂在 language_changed（String）与
## gold_changed（int）上，Godot 按参数个数与类型严格匹配信号 —— 带错类型会在
## emit 时报「Cannot convert argument」然后静默断连（实测抓到过）
func _refresh(_arg = null) -> void:
	if _player == null:
		_label.text = ""
		return
	if not _unlocked():
		_label.text = "%s  %s" % [tr("UI_SHOP_TITLE"), tr("UI_SHOP_LOCKED")]
		return
	_label.text = "%s  %s ×%d  %s" % [
		tr("UI_SHOP_TITLE"), tr("HUD_GOLD"),
		PlayerState.gold, tr("UI_SHOP_STAND_HINT")]
