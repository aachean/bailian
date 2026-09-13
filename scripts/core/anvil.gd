extends Area2D
## 城镇铁砧：站上来按 J，花 3 块精铁把武器强化一级（伤害 +20%）。
##
## 「打怪 → 掉碎片 → 回城镇强化 → 打得更顺」这半条循环的地表部分。
## 用 J 键做交互（专用交互键等手柄适配一起定），提示牌上写清代价和当前等级。

const COST := 3

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
		_try_upgrade()


## 玩家身上的强化进度（碎片 / 等级）。由 stage.gd 的快照负责存取
func _refresh() -> void:
	if _player == null:
		_label.text = ""
		return
	var shards := int(_player.get("shards"))
	var level := int(_player.get("upgrade_level"))
	if shards >= COST:
		_label.text = "%s  %d/3 → Lv.%d" % [tr("UI_ANVIL_READY"), shards, level + 1]
	else:
		_label.text = "%s  %d/3  (Lv.%d)" % [tr("UI_ANVIL_POOR"), shards, level]


func _try_upgrade() -> void:
	if _player == null:
		return
	var shards := int(_player.get("shards"))
	if shards < COST:
		return
	_player.set("shards", shards - COST)
	_player.set("upgrade_level", int(_player.get("upgrade_level")) + 1)
	if _player.has_method("_apply_upgrade"):
		_player.call("_apply_upgrade")
	_refresh()
