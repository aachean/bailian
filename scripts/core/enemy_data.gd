class_name EnemyData
extends Resource
## 一种敌人的全部数值。
##
## 敌人 = EnemyData + 通用技能（SkillData）+ AI 脚本。
## 数值在这里调，动作在 data/skills/ 里配 —— 加一种怪不加代码。

@export_group("标识")
@export var id: StringName = &""
@export var display_name: String = ""

@export_group("分类")
## 小怪 / 精英 / Boss（`trash` / `elite` / `boss`）。
## **只给数值工具与断言用**，AI 行为不看它 —— 但它决定了三件事：
## ① 从阶段表取哪一档血量与单发伤害（ADR-0019）② 掉落档次池（ADR-0016/批 5）
## ③ 断言里的伤害阶梯（小怪 < 精英、小怪 < Boss）
@export var kind: StringName = &"trash"

## 相位期间怎么位移。
##
## ⚠️ **没有「突进/冲锋」这一档，是刻意的**：让 Boss 高速朝玩家冲过去，
## 它会像推土机一样把玩家一路拱到地图边缘掉出世界 —— `walker._chase` 已经踩过
## 这个坑（见那里的注释）。要加冲锋之前先把「Boss 推不动玩家」这件事解决掉。
enum PhaseMove {
	STILL,     ## 原地亮护罩。最简单的相位，用于**引入**（ch1 前两章）
	RETREAT,   ## 朝远离玩家的方向快速后撤，逼玩家追 —— 用于**转折/考核**（ch3 起）
}

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

@export_group("防御（v2：平铺点数，走护甲曲线）")
## 平铺防御点数。减伤 = `def/(100+def)`，卡 0.6（def=150 到顶，见 ADR-0019）。
## **这是「敌人变强靠机制不靠堆血」那条原则的落点**（design-principles 4.3）：
## Boss 的「打不动」来自它，而不是一根更长的血条。
## 小怪 0（早期手感不动）／精英半个 boss 档／Boss 由阶段表的 `boss_def` 给
@export var defense: int = 0

@export_group("攻击（v2：平铺点数，与玩家同一套伤害合成）")
## 该类的**阶段基准单发点数**（不含技能自己的 damage）。
## 单发最终伤害 = `attack_skill.roll_damage() + attack_power()` ——
## 技能那一份保留「重砸比普攻疼」的相对差，基准那一份负责整体重标。
## **别逐怪拍数字**：按 kind + 章节从 `data/combat_defense.csv` 派生，
## 见 `tools/apply_enemy_scaling.py`
@export var atk_flat: int = 0
## 这只怪的个体倍率。同一档内部的强弱差异走它（重甲 1.2、快攻 0.85），
## 改它就是「这只怪比同类更疼」，不会碰到全章的基准
@export var atk_mult: float = 1.0

@export_group("相位（ADR-0019 的 B 口径：「玩家打不到它」的那一段时间）")
##
## ── 这一组字段是干什么的 ───────────────────────────────────────
## 设计原则 4.3 要求「敌人变强靠机制不靠堆血」，ADR-0019 把这句话变成了一个**时长预算**：
##   `BossHP = 玩家等效DPS × UPTIME(0.55) × 可打时间占比 × 目标秒数`
## 其中「可打时间占比」= 下面这组参数算出来的 `1 - phase_ratio()`，
## 也就是设计表 `enemy_scaling.csv` 里 `boss_active` 那一列（ch1 0.85 → ch5 0.65）。
## **没有相位，Boss 战就只剩一根更长的血条** —— 那正是 4.3 明令避免的。
##
## ── 形态（三段，缺一段就是背板）───────────────────────────────
##   ① 架势（`phase_warn_frames`）：护罩渐亮，**此时仍然可打** ——
##      这是给反应快的玩家的窗口，也是「读招」这件事的物理形状。
##      这一段的伤害**不会打断相位**（否则远程角色能永久取消它，预算就没了）。
##   ② 相位（`phase_frames`）：**无敌** + 按 `phase_move` 位移。打上去是「铛」。
##   ③ 恢复（`phase_recover_frames`）：护罩碎、原地硬直不动 ——
##      **这是给玩家的奖励窗口**：读对招的人该拿到输出机会，
##      否则相位就只是「等」而不是「考」（4.3 的意图）。
##
## ── 为什么必须无敌，不能只靠走位 ──────────────────────────────
## 弓手（远程）存在。只靠后撤的话，远程角色站在原地就能把相位期间的 DPS 打满，
## 「可打时间占比」当场失真 —— 时长预算就白算了。
@export var phase_interval_frames: int = 0
## 一次相位持续多少帧。**0 = 这只怪没有相位**（小怪 / 未参与时长预算的怪）
@export var phase_frames: int = 0
## 架势（相位前摇）帧数。**只加范围/无敌而不给前摇就是背板，不是难度**（4.3）
@export var phase_warn_frames: int = 18
## 相位结束后的可反击硬直窗口（帧）
@export var phase_recover_frames: int = 24
## 相位期间怎么动。见 PhaseMove
@export var phase_move: PhaseMove = PhaseMove.STILL

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
## 帧序列目录（walk_N.png 循环 + idle_0/hurt_0/dead_0）。非空时优先于 sprite_path
@export var sprite_dir: String = ""

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


## 这只怪的单发攻击力（点数）。**已经含个体倍率**
func attack_power() -> int:
	return int(round(float(atk_flat) * atk_mult))


## 它挨打时实际吃到的减伤比例。与 `Health.armor_reduction()` 同一条曲线 ——
## 放这里是为了让生成脚本与断言能**不看场景**就核对「def 有没有越过 0.6 红线」
func armor_reduction() -> float:
	return minf(float(defense) / (100.0 + float(defense)), Health.MAX_DAMAGE_REDUCTION)


## 相位占整场战斗时间的比例 = **`1 - boss_active`**（ADR-0019）。
## 分母是**完整的一轮**：架势 + 相位 + 间隔。架势也算进去了 ——
## 它虽然可以打，但它占的是「还没进入下一轮」的时间，少算它比例会偏高。
##
## 数据落地脚本按这个比例反推 `phase_frames` / `phase_interval_frames`，
## 断言也靠它对账 `enemy_scaling.csv` 的 `boss_active` —— **两处不许各算一份**
func phase_ratio() -> float:
	var cycle := phase_cycle_frames()
	return 0.0 if cycle <= 0 else float(phase_frames) / float(cycle)


## 一轮相位的总帧数（架势 + 相位 + 间隔）。0 = 没有相位
func phase_cycle_frames() -> int:
	if phase_frames <= 0:
		return 0
	return phase_warn_frames + phase_frames + maxi(phase_interval_frames, 0)


## 这只怪有没有相位
func has_phase() -> bool:
	return phase_frames > 0
