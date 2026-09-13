class_name EnemyData
extends Resource
## 一种敌人的全部数值。
##
## 敌人 = EnemyData + 通用技能（SkillData）+ AI 脚本。
## 数值在这里调，动作在 data/skills/ 里配 —— 加一种怪不加代码。

@export_group("标识")
@export var id: StringName = &""
@export var display_name: String = ""

@export_group("存活")
@export var max_hp: int = 30
## 被打死之后过多久满血重生。<= 0 表示不重生
@export var revive_delay: float = 2.0
## 被打中的硬直（帧 @60fps）。硬直里既不追人也不攻击
@export var hurt_stun_frames: int = 14

@export_group("AI")
## 巡逻速度 / 追击速度（像素/秒）
@export var patrol_speed: float = 40.0
@export var chase_speed: float = 85.0
## 巡逻时离出生点最远多远（单程，左右各一半）
@export var patrol_range: float = 70.0
## 玩家进这个距离开始追
@export var aggro_range: float = 150.0
## 追击中玩家逃出这个距离就放弃，回巡逻
@export var deaggro_range: float = 240.0
## 玩家进这个距离开始攻击（中心到中心）
@export var attack_range: float = 34.0
## 两次攻击之间最少隔多少帧
@export var attack_cooldown_frames: int = 45

@export_group("动作")
## 攻击用哪张技能表（data/skills/ 里的 SkillData）
@export var attack_skill: SkillData
