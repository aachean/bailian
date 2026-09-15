extends Node2D
## 掉落物：怪死后撒在地上，玩家走近吸附拾取。
##
## ── 四种掉落物共用这一个场景 ──────────────────────────────────
## 精铁碎片（默认）与装备（item_path 非空）是老的两样；
## 元宝（gold_amount > 0）与消耗品（potion 非空）是经济增量（M3 第 3 步）加的。
## 吸附 / 拾取 / 排序的代码完全一样，差别只在「捡起来交给谁」。复制成四个场景的话，
## 以后调吸附手感要改四处，迟早会漏一处。
##
## ── 消耗品的门（计划 §3.7）───────────────────────────────────
## 药掉在地上，走近直接生效 —— 不进背包、不占快捷键。
## 但**满血 / 满蓝时不拾取，留在地上**：吸附的门也一并关掉，
## 不然它会贴着玩家飘，像个甩不掉的跟班。
## 元宝与精铁没有门 —— 钱不会嫌多。
##
## 不做物理弹跳 —— 原型阶段碎片原地散落就够了，吸附拾取的手感（走近被吸走）
## 比弹跳值钱。拾取走轮询距离，不走 Area2D 信号：吸附本身就在逐帧挪位置，
## 反正要逐帧算距离。

const ATTRACT_DIST := 46.0
const COLLECT_DIST := 10.0
const ATTRACT_SPEED := 320.0

## 回血药回多少血。掉落物的属性住在掉落物上 —— 玩家只负责「喝」
const HEAL_HP := 40
## 回蓝药回多少蓝
const RESTORE_MP := 25

## 掉的是什么装备（ItemData 的资源路径）。非空 = 装备掉落。
## **必须在 add_child 之前设好** —— _ready 里要按它决定长相
var item_path: String = ""
## 掉的是多少元宝。0 = 不是元宝
var gold_amount: int = 0
## 掉的是哪种药：&"hp" 回血 / &"mp" 回蓝。空 = 不是药
var potion: StringName = &""

var _player: Node2D = null
var _collected := false
var _icon: ItemIcon = null


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_icon = get_node_or_null("Visual") as ItemIcon
	if not item_path.is_empty():
		_dress_as_item()
	elif gold_amount > 0:
		_dress(&"gold", 8.0)
	elif potion == &"hp":
		_dress(&"potion_hp", 9.0)
	elif potion == &"mp":
		_dress(&"potion_mp", 9.0)


## 掉落物统一换装：换形态 + 换大小。装备的图标比钱和药大一圈 ——
## 掉了一地里混着一件紫装却看不出来，那这件装备等于没掉
func _dress(icon_kind: StringName, half: float) -> void:
	if _icon == null:
		return
	_icon.kind = icon_kind
	_icon.offset_left = -half
	_icon.offset_top = -half
	_icon.offset_right = half
	_icon.offset_bottom = half


func _dress_as_item() -> void:
	_dress(&"", 10.0)
	_icon.set_item_path(item_path)


## 药水的门：满了他就不收。返回 true = 现在不收
func _potion_not_needed() -> bool:
	if potion == &"hp":
		var h := _player.get_node_or_null("Health") as Health
		return h == null or h.hp >= h.max_hp
	if potion == &"mp":
		return int(_player.get("mp")) >= int(_player.get("max_mp"))
	return false


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

	# 满血 / 满蓝的药：不吸附、不拾取，安静躺在地上等需要它的人
	var gated := not potion.is_empty() and _potion_not_needed()

	var d := global_position.distance_to(_player.global_position)
	if not gated and d < COLLECT_DIST:
		_collected = true
		if not item_path.is_empty():
			if _player.has_method("collect_item"):
				_player.call("collect_item", item_path)
		elif gold_amount > 0:
			if _player.has_method("collect_gold"):
				_player.call("collect_gold", gold_amount)
		elif potion == &"hp":
			if _player.has_method("drink_heal"):
				_player.call("drink_heal", HEAL_HP)
		elif potion == &"mp":
			if _player.has_method("drink_mana"):
				_player.call("drink_mana", RESTORE_MP)
		else:
			# 精铁碎片 —— 四类掉落里最老的那一种，别在扩表时把它挤掉
			# （2026-09-15 重写时丢过这个分支，m3/m11 的既有断言当场抓住）
			if _player.has_method("collect_shard"):
				_player.call("collect_shard")
		queue_free()
	elif not gated and d < ATTRACT_DIST:
		global_position = global_position.move_toward(_player.global_position, ATTRACT_SPEED * delta)
	# 没人靠近就安静躺着
