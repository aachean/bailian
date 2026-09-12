class_name Health
extends Node
## 血量与无敌状态。
##
## 挂在一个会挨打的东西下面，负责三件事：扣血、死亡、无敌窗口。
## 无敌分两种，互不干扰：
##   · invincible（硬无敌）—— 由外部开关控制，闪避的无敌帧用它
##   · 受击后短暂无敌 —— 内部计时，防止同一次挥砍的多帧判定把血扣几遍
## 这两种很容易混成一件事，混了以后「闪避被打了但还是掉血」这种 bug 会非常难查。

## dir = 被击退的水平方向（+1 向右 / -1 向左 / 0 未知）。受击方靠它决定往哪边后仰
signal damaged(amount: int, hp_left: int, point: Vector2, heavy: bool, dir: int)
signal died
signal revived
signal hp_changed(hp: int, max_hp: int)

@export var max_hp: int = 120
## 挨打之后的无敌时长（秒）。要略大于一次挥砍的判定持续帧数
@export var post_hit_invincible: float = 0.10

var hp: int = 0
var is_dead: bool = false
## 硬无敌。闪避状态开着它，与受击无敌无关
var invincible: bool = false

var _post_hit: float = 0.0


func _ready() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)


func _process(delta: float) -> void:
	if _post_hit > 0.0:
		_post_hit = maxf(_post_hit - delta, 0.0)


func ratio() -> float:
	return 0.0 if max_hp <= 0 else clampf(float(hp) / float(max_hp), 0.0, 1.0)


func can_be_hit() -> bool:
	return not is_dead and not invincible and _post_hit <= 0.0


## 扣血。返回实际造成的伤害；0 表示这次没打中（无敌 / 已死 / 已在受击无敌里）。
## 攻击方靠这个返回值决定「算不算命中」，所以要严格区分 0 和「打出了 0 点伤害」。
func take_damage(amount: int, point: Vector2 = Vector2.ZERO, heavy: bool = false, dir: int = 0) -> int:
	if not can_be_hit() or amount <= 0:
		return 0
	var dealt: int = mini(amount, hp)
	hp = maxi(hp - amount, 0)
	_post_hit = post_hit_invincible
	damaged.emit(dealt, hp, point, heavy, dir)
	hp_changed.emit(hp, max_hp)
	if hp <= 0 and not is_dead:
		is_dead = true
		died.emit()
	return dealt


func heal_full() -> void:
	hp = max_hp
	is_dead = false
	invincible = false
	_post_hit = 0.0
	revived.emit()
	hp_changed.emit(hp, max_hp)
