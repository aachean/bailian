class_name ForgeData
extends Resource
## 强化的全部数值：各品质能练到几级、每级花多少、每级给多少。
##
## ── 为什么强化上限绑品质（设计原则 5.2）────────────────────────
## 低品质装备要天然有天花板 —— **别让玩家在过渡装上无限投入**。
## 造梦西游的强化上限按品质递增（白装的上限远低于红装），冒险岛的星之力同理。
## 反例是所有品质共用一个上限：过渡装也能练到顶，于是后面拿到的好装备失去意义，
## 玩家白练一次，然后骂游戏。
##
## ── 成本为什么要递增（设计原则 5.4）───────────────────────────
## 成本递增让「再练一级」越来越贵，玩家必须真的去刷，而不是攒够一次练到底。
## 没有它，强化就是纯粹的挂机，中间没有任何决策。
##
## ── 收益为什么要递减（设计原则 5.4 / 3.4）────────────────────
## 第 n 级给 atk_per_level × atk_falloff^(n-1)，是等比数列 ——
## 总加成收敛到一个有限值，天生就是软上限。这比「先线性叠加、事后再去压数值」
## 便宜得多，因为**它一开始就不需要压**。

## 各品质的强化上限，下标 = ItemData.Tier 的枚举序号。
## 顺序必须与 ItemData.Tier 一致：普通 / 精良 / 优秀 / 极品 / 传说 / 至尊（6 档，2026-09-18 扩）
## ⚠️ 这个数组是**按下标取值**的（max_for_tier 用 clampi）—— Tier 枚举一动，
## 这里必须同改，否则越界静默夹到最后一项，等于所有品质共用一个上限（违反 5.2）
@export var tier_max: Array[int] = [3, 4, 5, 6, 7, 8]

@export_group("成本（从第 n 级升到 n+1 级 = base_cost × cost_growth^n）")
@export var base_cost: int = 3
@export var cost_growth: float = 1.6

@export_group("收益（总倍率 = per × (1 - falloff^级数) / (1 - falloff)）")
## 第 1 级的倍率增量。**语义（ADR-0029，2026-09-19）**：
## 武器强化 → 这个值当**攻击%**（进 damage_scale 乘区，武器是唯一攻击杠杆）；
## 护甲/饰品强化 → 这个值当**放大比例**，放大该件自己 roll 的 hp/def。
## 字段名保留 atk_ 前缀是历史遗留 —— 它其实是通用倍率，不只作用于攻击
@export var atk_per_level: float = 0.15
## 每级比上一级少给多少（0.85 = 每级只有上一级的 85%）
@export var atk_falloff: float = 0.85


## 这个品质能练到几级。越界返回最后一个档位 —— 宁可给个保守值也不要崩
func max_for_tier(tier: int) -> int:
	if tier_max.is_empty():
		return 0
	return tier_max[clampi(tier, 0, tier_max.size() - 1)]


## 从 level 级升到 level+1 级要花多少材料
func cost_at_level(level: int) -> int:
	return int(round(float(base_cost) * pow(cost_growth, float(maxi(level, 0)))))


## 练到 level 级时的**倍率**（0.728 = +72.8%，已含收益递减）。
## 武器：当攻击%；护甲/饰品：当 hp/def 的放大比例（ADR-0029）。
## 旧名 atk_bonus_at 已改名 —— 它从来不该只作用于攻击
func mult_at(level: int) -> float:
	if level <= 0:
		return 0.0
	if is_equal_approx(atk_falloff, 1.0):
		return atk_per_level * float(level)          # 不衰减的退化情形
	return atk_per_level * (1.0 - pow(atk_falloff, float(level))) / (1.0 - atk_falloff)


## 已经练到顶了吗
func is_maxed(tier: int, level: int) -> bool:
	return level >= max_for_tier(tier)
