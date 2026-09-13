extends CanvasLayer
## 玩家 HUD：左上角色状态栏（血条 / 武器等级），右上背包（精铁碎片）。
##
## 挂在玩家场景里 —— CanvasLayer 不吃相机变换，永远钉在屏幕角上。
## 数据直接读父节点（玩家），每帧对一遍刷新：碎片/等级/血量都可能变，
## 与其给每个变化点接信号，不如一帧一次的轮询便宜又不会漏。

@onready var _player: Node = get_parent()
@onready var _hp_fill: ColorRect = $Status/HPBar/Fill
@onready var _lv_label: Label = $Status/Level
@onready var _bag_label: Label = $Bag/Count


func _ready() -> void:
	refresh()


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var h := _player.get_node("Health") as Health
	if h != null:
		_hp_fill.scale.x = clampf(h.ratio(), 0.0, 1.0)
	_lv_label.text = "%s Lv.%d" % [tr("HUD_WEAPON"), int(_player.get("upgrade_level"))]
	_bag_label.text = "%s ×%d" % [tr("HUD_SHARD"), int(_player.get("shards"))]
