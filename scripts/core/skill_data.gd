class_name SkillData
extends Resource
## 一次战斗动作的全部参数。
##
## 攻击和闪避共用这一个结构 —— 它们本质上是同一件事：
## 「前摇 → 判定 → 后摇」，中间带一段位移冲量和一段无敌窗口。
## 闪避只是那种「没有判定、但有无敌」的技能。以后加冲刺斩、上挑、格挡，
## 也都是往这张表里加字段，而不是新写一个类。
##
## ── 时间单位是【帧】，基准 60 fps ─────────────────────────────
## 不用秒。判定持续 4 帧写成 0.0666... 秒的话，调参和断言都会很难受，
## 而且浮点误差会让「第几帧生效」变得不可复现。

enum Kind { ATTACK, DODGE }

@export_group("标识")
@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.ATTACK

@export_group("时序（帧 @ 60fps）")
## 前摇：按下到判定生效。越长越「重」，但越迟钝
@export var startup_frames: int = 6
## 判定持续帧数。这段时间内判定框每帧都在查
@export var active_frames: int = 4
## 后摇：判定结束到动作真正结束。只有不接下一段时才走完
@export var recovery_frames: int = 8

@export_group("伤害")
@export var damage: int = 8
## 伤害浮动比例（0.12 = ±12%）。0 表示固定伤害
@export var damage_variance: float = 0.12
## 命中时给目标的后仰力度。只影响表现，不推动位置
@export var knockback: float = 120.0
## 命中顿帧（帧）。攻击方和被击方一起冻结，是打击感的主要来源
@export var hitstop_frames: int = 6
## 重击：飘字更大更亮。第 3 段用
@export var heavy: bool = false
## 能不能被下一段取消。第 3 段为 false —— 那是这套连招的收招硬直，是刻意的
@export var chainable: bool = true

@export_group("判定框")
@export var hitbox_size: Vector2 = Vector2(46, 32)
## 相对角色的偏移。x 会按朝向镜像
@export var hitbox_offset: Vector2 = Vector2(26, -2)

@export_group("位移")
## 出招瞬间沿朝向给的水平速度（像素/秒）
@export var lunge_speed: float = 0.0
## 上述速度线性衰减到 0 所需帧数
@export var lunge_decay_frames: int = 10

@export_group("无敌")
## 无敌窗口 [invincible_from, invincible_to)，按技能起点算的帧号。
## to <= from 表示这个技能没有无敌
@export var invincible_from: int = 0
@export var invincible_to: int = 0

@export_group("冷却")
## 技能结束后再过多少帧才能再次使用
@export var cooldown_frames: int = 0

@export_group("消耗")
## 释放消耗的蓝量。0 = 免费（普攻 / 闪避都是 0）
@export var mp_cost: int = 0

@export_group("技能树（M3-4）")
## 解锁等级。角色等级到了，这个技能才进技能池
@export var unlock_level: int = 1
## 名字的翻译 key。界面一律 tr(name_key)，display_name 只是数据里给自己看的注
@export var name_key: StringName = &""

@export_group("效果（M3-4）")
## 施放时回血多少点（0 = 不回）。调息用
@export var heal_amount: int = 0
## 施放期间额外减伤（0.6 = 少挨 60%）。铁壁用。
## 与装备减伤**取较大值，不叠加** —— 叠上去很容易变成免伤
@export var guard_reduction: float = 0.0
## 判定帧发射的投射物场景（剑气斩用）。空 = 不发射
@export var projectile_scene: PackedScene = null
@export var projectile_speed: float = 420.0
@export var projectile_life: float = 1.1


## 这个技能从按下到彻底结束一共多少帧
func total_frames() -> int:
	return startup_frames + active_frames + recovery_frames


## 判定窗口的第一帧
func active_from() -> int:
	return startup_frames


## 判定窗口之后的第一帧
func active_to() -> int:
	return startup_frames + active_frames


## 第 t 帧（0 起算）是否处于判定中
func is_active_at(t: int) -> bool:
	return t >= active_from() and t < active_to()


## 第 t 帧是否无敌
func is_invincible_at(t: int) -> bool:
	return invincible_to > invincible_from and t >= invincible_from and t < invincible_to


## 第 t 帧的前冲速度系数（1 → 0 线性衰减）
func lunge_factor(t: int) -> float:
	if lunge_decay_frames <= 0:
		return 1.0 if t == 0 else 0.0
	return clampf(1.0 - float(t) / float(lunge_decay_frames), 0.0, 1.0)


## 掷出本次伤害值
func roll_damage(rng: RandomNumberGenerator) -> int:
	if damage_variance <= 0.0:
		return damage
	var lo := float(damage) * (1.0 - damage_variance)
	var hi := float(damage) * (1.0 + damage_variance)
	return int(round(rng.randf_range(lo, hi)))
