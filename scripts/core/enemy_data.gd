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
## 被打死之后过多久满血重生。**<= 0 表示不重生。**
##
## 副本内的小怪一律设 0：过关判据是「清空关内敌人」，会重生的怪会让
## 关卡永远打不完（docs/adr/0009 §2）。重生能力保留在训练房 / 测试场景，
## 不再用于副本内 —— 所以想改回 > 0 之前先想清楚它属于哪一边
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

@export_group("外观（AI 生图管线，ADR-0015）")
## 精灵贴图路径。空 = 维持程序化色块视觉。素材统一**面朝左**（朝向翻转靠
## walker._apply_facing 的 scale.x 与 skin 恒定 -1 相互抵消实现）
@export var sprite_path: String = ""

@export_group("掉落")
## 死亡时掉多少精铁碎片（强化素材）。0 = 不掉
@export var drop_shards: int = 1
## 死亡时掉多少元宝（商店货币）。0 = 不掉。**与精铁是两条管道**（计划 §3.7）：
## 元宝进商店，精铁进铁匠铺，互不兑换
@export var drop_gold: int = 0
## 掉一瓶回血药的概率（0..1）。**药掉在地上，走近直接生效，不进背包**（计划 §3.7）
@export var drop_heal_chance: float = 0.0
## 掉一瓶回蓝药的概率（0..1）。同上
@export var drop_mana_chance: float = 0.0
## 死亡时给多少经验
@export var exp_reward: int = 8
## 装备掉落池（data/items/*.tres 的资源路径）。空数组 = 不掉装备
@export var drop_items: Array[String] = []
## 掉一件装备的概率（0..1）。1.0 = 必掉（Boss），0 = 不掉
@export var drop_item_chance: float = 0.0

@export_group("投射物（远程怪用，0 = 没有远程手段）")
## 投射物飞行速度（像素/秒）。0 = 不投掷
@export var projectile_speed: float = 0.0
@export var projectile_damage: int = 0
## 投射物最长飞行时间（秒），超时消散
@export var projectile_life: float = 1.6
