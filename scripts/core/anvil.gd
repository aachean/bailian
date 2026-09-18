extends Area2D
## 城镇铁砧：站上来按 J 打开**铁匠铺**（逐件强化）。
##
## ── 2026-09-14 改过一轮 ────────────────────────────────────────
## 原来是「花 3 块精铁把**全局的武器强化等级** +1」。强化改成
## **逐件 + 按品质封顶**之后（设计原则 5.2 / 5.4），「练哪一件」本身成了
## 玩家的决定 —— 过渡装练到白装的上限就该停手，把精铁留给后面那件。
## 这个决定必须由玩家来做，所以铁砧不再自己算钱，只负责把界面叫出来。
##
## 交互方式**没变**（走近 → 出提示 → 按键）：这是安全区里已经有的语言
## （舆图台 / NPC 都是这样），不发明第二套，见 docs/design-conventions.md。
##
## ── 锻造台（2026-09-18 神要求补上）─────────────────────────────
## 打造（用书 + 材料合成装备）藏在铁砧面板的 Tab 页里，神玩的时候没找到 ——
## 「有了制作书，但没有制作装备的地方」。所以同一张台子分两座：
## **铁砧 = 强化，锻造台 = 打造**（opens_craft 标志区分）。
## 同一场景文件、同一交互语言，只是打开的面板页不同。

## true = 这是**锻造台**：打开面板直接落在打造页
@export var opens_craft: bool = false

var _player: Node2D = null

@onready var _label: Label = $Label


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
	if Input.is_action_just_pressed("attack"):
		_open()


## 打开玩家身上的铁匠铺面板。已经开着 / 别的模态界面开着都不重复开 ——
## 那几个界面抢同一批按键，叠起来只会互相打架（与舆图台同一套约定）
func _open() -> void:
	var panel := _player.get_node_or_null("ForgePanel")
	if panel == null or not panel.has_method("open"):
		return
	if bool(panel.call("is_open")):
		return
	if _other_ui_open():
		return
	if opens_craft and panel.has_method("open_craft"):
		panel.call("open_craft")     # 锻造台：直接落在打造页
	else:
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
	var shop := _player.get_node_or_null("ShopPanel")
	if shop != null and shop.has_method("is_open") and bool(shop.call("is_open")):
		return true
	var box := get_tree().get_first_node_in_group("dialogue_box")
	return box != null and bool(box.call("is_open"))


## 提示牌：当前精铁 + 按哪个键。精铁要写出来 —— 「能不能练得起」是玩家
## 站在这儿第一个想知道的事。锻造台的牌子写制书/材料在背包里
##
## 参数必须留着：Godot 按参数个数严格匹配信号连接（少一个会在 emit 时静默报错）
func _refresh(_locale: String = "") -> void:
	if _player == null:
		_label.text = ""
		return
	if opens_craft:
		_label.text = "%s  %s" % [tr("UI_FORGE_STAND"), tr("UI_FORGE_STAND_HINT")]
		return
	_label.text = "%s  %s ×%d  %s" % [
		tr("UI_ANVIL_TITLE"), tr("HUD_SHARD"),
		PlayerState.shards, tr("UI_ANVIL_HINT")]
