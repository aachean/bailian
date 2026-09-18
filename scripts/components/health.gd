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
## 打上来了，但被**硬无敌**挡下（相位的护罩 / 闪避的无敌帧）。
##
## ── 为什么单独一个信号，而不是让 take_damage 返回个负数 ──────────
## 「没打动」有三种完全不同的原因，收益也完全不同：
##   · 硬无敌（相位护罩）→ **必须出声** —— 玩家看得见护罩，得知道「这一下被挡住了」
##   · 受击后无敌窗口   → 不出声（那是同一次挥砍的第 2~4 帧，玩家刚看到那一下打中了）
##   · 已经死了         → 不出声（尸体在淡出，玩家不会以为自己砍中了什么）
## 三者混在一个返回值里，调用方就只能靠猜。见 design-conventions「不能静默的三件事」：
## **「不能做」和「已经记下」都不能静默。**
signal blocked(point: Vector2, dir: int)
signal died
signal revived
signal hp_changed(hp: int, max_hp: int)

@export var max_hp: int = 120
## 挨打之后的无敌时长（秒）。要略大于一次挥砍的判定持续帧数
@export var post_hit_invincible: float = 0.10
## 平铺防御（点数）。**不是减伤百分比** —— 内部走护甲曲线 `def/(100+def)`。
## 装备的「防御」词条写这里；敌人没填就是 0（挨打全额）
## （2026-09-18 从按比例的 damage_reduction 换成平铺点数，见 docs/adr/0018）
@export var defense: int = 0
## 技能格挡的临时减伤（比例）。与护甲曲线**取 max，不是相加** ——
## 相加会让「格挡 + 满装」叠出设计上没有的减伤档。技能结束由持有者清零
@export var guard_reduction: float = 0.0

## 减伤上限。留住这道天花板是为了「堆防御到无敌」不会成为解 —— 见 docs/adr/0005。
## 护甲曲线在 def=150 时正好到 0.6，之后一刀切平（ADR-0019 的 def≤150 封顶）
const MAX_DAMAGE_REDUCTION := 0.6

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


## 扣血。返回实际造成的伤害；0 表示这次没打中（无敌 / 已死 / 已在受击无敌里）。
## 攻击方靠这个返回值决定「算不算命中」，所以要严格区分 0 和「打出了 0 点伤害」。
## 护甲在这一层生效：攻击方算出的伤害先去减伤，再落到血上。
## 放在 Health 而不是攻击方，是因为「挨打的人有多硬」属于挨打的人。
## **玩家与敌人共用这一套**（敌人填 def 就自动生效，见 docs/adr/0020）
##
## ⚠️ 三种「返回 0」**故意写开、不合并**（2026-09-18，ADR-0023）：
## 原来这里是一句 `if not can_be_hit(): return 0`，而 `can_be_hit()` 把
## 「死了 / 硬无敌 / 受击无敌窗口」揉成一个 bool —— 于是加了相位之后，
## **打不动这件事彻底静默**（砍护罩 = 砍空气，没声音没火花）。
## 合并是省了一行，代价是丢掉「为什么打不动」这条信息。**别再把它合并回去。**
func take_damage(amount: int, point: Vector2 = Vector2.ZERO, heavy: bool = false, dir: int = 0) -> int:
	if is_dead or amount <= 0:
		return 0
	# 硬无敌（相位的护罩 / 闪避的无敌帧）：**必须发 blocked**，攻击方据此出「铛」的反馈
	if invincible:
		blocked.emit(point, dir)
		return 0
	# 挨打之后的短暂无敌窗口：安静。那是同一次挥砍的第 2~4 帧，
	# 玩家刚看见第一下打中了 —— 这里再喊一声反而是噪声
	if _post_hit > 0.0:
		return 0
	var actual := _reduced(amount)
	var dealt: int = mini(actual, hp)
	hp = maxi(hp - actual, 0)
	_post_hit = post_hit_invincible
	damaged.emit(dealt, hp, point, heavy, dir)
	hp_changed.emit(hp, max_hp)
	if hp <= 0 and not is_dead:
		is_dead = true
		died.emit()
	return dealt


## 护甲曲线：减伤比例 = def/(100+def)，卡 0.6。
## **这不是「攻击 − 防御」减法**（design-principles 4.5 明令禁止）：曲线连续、单调、
## 有渐近线，不会出现「差一点就无敌 / 差一点就白给」的砖墙。
## 例：def=20 → 16.7%，def=40 → 28.6%，def=150 → 60%（到顶）
func armor_reduction() -> float:
	return minf(float(defense) / (100.0 + float(defense)), MAX_DAMAGE_REDUCTION)


## 实际生效的减伤：护甲曲线与技能格挡取 max。两条都过同一道封顶
func effective_reduction() -> float:
	return clampf(maxf(armor_reduction(), guard_reduction), 0.0, MAX_DAMAGE_REDUCTION)


## 减伤计算。至少留 1 点 —— 「全身神装站着不掉血」会让挨打彻底失去代价，
## 而保底 1 点守住了这条底线（掉出世界的 9999 点照样秒杀，减伤不吃掉它）
func _reduced(amount: int) -> int:
	var r := effective_reduction()
	if r <= 0.0:
		return amount
	return maxi(1, int(round(float(amount) * (1.0 - r))))


func heal_full() -> void:
	hp = max_hp
	is_dead = false
	invincible = false
	_post_hit = 0.0
	revived.emit()
	hp_changed.emit(hp, max_hp)


## 治疗指定点数（不超过上限）。技能「调息」用。返回实际回了多少
func heal(amount: int) -> int:
	if amount <= 0 or is_dead:
		return 0
	var before := hp
	hp = mini(hp + amount, max_hp)
	if hp != before:
		hp_changed.emit(hp, max_hp)
	return hp - before


## 恢复到指定血量（读档用）。与 take_damage 不同：不发 damaged、不触发死亡，
## 只把血量和状态摆到位 —— 「继续游戏」时世界该是离开时的样子。
func restore(value: int) -> void:
	hp = clampi(value, 0, max_hp)
	is_dead = false
	invincible = false
	_post_hit = 0.0
	hp_changed.emit(hp, max_hp)
