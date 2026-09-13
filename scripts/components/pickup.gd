extends Node2D
## 掉落物：怪死后撒在地上，玩家走近吸附拾取。
##
## ── 两种掉落物共用这一个场景 ──────────────────────────────────
## 精铁碎片（item_path 为空）与装备（item_path = ItemData 的资源路径）。
## 吸附 / 拾取 / 排序的代码完全一样，差别只在「捡起来交给谁」。复制成两个场景的话，
## 以后调吸附手感要改两处，迟早会漏一处。
##
## 不做物理弹跳 —— 原型阶段碎片原地散落就够了，吸附拾取的手感（走近被吸走）
## 比弹跳值钱。拾取走轮询距离，不走 Area2D 信号：吸附本身就在逐帧挪位置，
## 反正要逐帧算距离。

const ATTRACT_DIST := 46.0
const COLLECT_DIST := 10.0
const ATTRACT_SPEED := 320.0

## 掉的是什么装备（ItemData 的资源路径）。留空 = 精铁碎片。
## **必须在 add_child 之前设好** —— _ready 里要按它决定长相
var item_path: String = ""

var _player: Node2D = null
var _collected := false
var _icon: ItemIcon = null


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_icon = get_node_or_null("Visual") as ItemIcon
	if not item_path.is_empty():
		_dress_as_item()


## 装备掉落物：图标比碎片大一圈，形状按部位、颜色按品质 ——
## 地上一眼分得出「掉的是剑还是甲、什么成色」。
## 掉了一地精铁里混着一件紫装却看不出来，那这件装备等于没掉
func _dress_as_item() -> void:
	if _icon == null:
		return
	_icon.offset_left = -10.0
	_icon.offset_top = -10.0
	_icon.offset_right = 10.0
	_icon.offset_bottom = 10.0
	_icon.set_item_path(item_path)


func _physics_process(delta: float) -> void:
	if _collected:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var h := _player.get_node_or_null("Health") as Health
	if h == null or h.is_dead:
		return                      # 玩家死了不捡，重生后再来

	var d := global_position.distance_to(_player.global_position)
	if d < COLLECT_DIST:
		_collected = true
		if item_path.is_empty():
			if _player.has_method("collect_shard"):
				_player.call("collect_shard")
		else:
			if _player.has_method("collect_item"):
				_player.call("collect_item", item_path)
		queue_free()
	elif d < ATTRACT_DIST:
		global_position = global_position.move_toward(_player.global_position, ATTRACT_SPEED * delta)
	# 没人靠近就安静躺着
