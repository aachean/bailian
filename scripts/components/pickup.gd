extends Node2D
## 掉落物「精铁碎片」：怪死后撒在地上，玩家走近吸附拾取。
##
## 不做物理弹跳 —— 原型阶段碎片原地散落就够了，吸附拾取的手感（走近被吸走）
## 比弹跳值钱。拾取走轮询距离，不走 Area2D 信号：吸附本身就在逐帧挪位置，
## 反正要逐帧算距离。

const ATTRACT_DIST := 46.0
const COLLECT_DIST := 10.0
const ATTRACT_SPEED := 320.0

var _player: Node2D = null
var _collected := false


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")


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
		if _player.has_method("collect_shard"):
			_player.call("collect_shard")
		queue_free()
	elif d < ATTRACT_DIST:
		global_position = global_position.move_toward(_player.global_position, ATTRACT_SPEED * delta)
	# 没人靠近就安静躺着
