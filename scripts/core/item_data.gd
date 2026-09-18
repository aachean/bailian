class_name ItemData
extends Resource
## 一件装备的**型号**数据。加装备 = 写一个 .tres，不改代码（与 SkillData / EnemyData 同一套路）。
##
## ── v2（2026-09-18）：百分比词条换成【平铺区间】────────────────
## v1 的三条词条是 atk_bonus%(进 damage_scale) / def_bonus%(按比例减伤) / hp_bonus(点数)。
## v2 全部改成平铺点数，且存的是**区间 [min,max] 而不是定值**：
## 掉落时在区间里 roll 一次，**结果跟着实例走**（同一个 uid 永远同一个值）。
##
## 为什么存区间：刷子游戏的乐趣有一半来自「这一件比上一件好一点」。
## 型号存定值的话，两把铁剑各方面都一样，「再刷一把」就没有意义了。
## 见 docs/adr/0017-flat-stat-ranges.md、docs/adr/0018-flat-stat-rework.md。
##
## 伤害合成（docs/adr/0018 方案 A，唯一的一条管线）：
##   `最终伤害 = (技能基础伤害 + Σ平铺攻击) × (1 + 等级% + 强化%) × 100/(100 + 目标防御)`
## 攻击是**加算的点数**；防御走护甲曲线、不可免伤、卡 0.6 封顶，**不是减法**。
##
## ── 为什么槽位用字符串 id 而不是 enum 序号 ───────────────────
## 装备栏要进存档（ConfigFile 存 Dictionary）。用 enum 序号当 key 的话，
## 以后往枚举中间插一个部位，老存档的序号会静默指向错误的槽。
## 字符串 key 没这个隐患，存档也一眼能读出含义。
## **v2 从 4 槽扩到 8 槽就是因为这条才没把存档结构弄坏。**

enum Slot { WEAPON, HELM, CHEST, LEGS, BOOTS, RING, NECKLACE, BRACELET }
## 品质六档。颜色见 tier_color()：白 / 绿 / 蓝 / 紫 / 橙 / 红
## 顺序**不能乱** —— forge.tres 的 tier_max 是按这个枚举的下标取值的
enum Tier { COMMON, FINE, UNCOMMON, RARE, EPIC, LEGENDARY }

## 槽位 id，顺序与 Slot 枚举一致。装备栏字典和存档都用它当 key
const SLOT_IDS: Array[StringName] = [
	&"weapon", &"helm", &"chest", &"legs", &"boots", &"ring", &"necklace", &"bracelet",
]
## 槽位显示名的翻译 key，顺序同上
const SLOT_KEYS: Array[StringName] = [
	&"SLOT_WEAPON", &"SLOT_HELM", &"SLOT_CHEST", &"SLOT_LEGS",
	&"SLOT_BOOTS", &"SLOT_RING", &"SLOT_NECKLACE", &"SLOT_BRACELET",
]

## 武器类型 → 职业（CharacterData.weapon_type）。**武器是唯一的职业门**
## （PlayerState.equip），防具饰品留空表示人人可穿
const WEAPON_TYPES: Array[StringName] = [&"sword", &"blade", &"bow", &"staff"]

@export_group("标识")
@export var id: StringName = &""
## 名字的翻译 key。界面一律 tr(name_key)，不写死人话
@export var name_key: StringName = &""
## 中文名，**只给编辑器里看 .tres 时认得出是哪件**。界面不走它（走 tr(name_key)）
@export var display_name: String = ""

@export_group("部位与品质")
@export var slot: Slot = Slot.WEAPON
@export var tier: Tier = Tier.COMMON

@export_group("平铺词条区间（0 = 没有这条；掉落时在实例上 roll 一次）")
## 攻击点数。加进伤害合成的加算项，**不乘进百分比**
@export var atk_min: int = 0
@export var atk_max: int = 0
## 生命上限点数
@export var hp_min: int = 0
@export var hp_max: int = 0
## 防御点数。**不是减伤百分比** —— 走护甲曲线 100/(100+def)，卡 0.6 封顶
@export var def_min: int = 0
@export var def_max: int = 0

@export_group("武器类型（武器必填，防具/饰品留空）")
## 武器归属：sword / blade / bow / staff。**角色只能穿自己类型的武器**
## （CharacterData.weapon_type 对照，PlayerState.equip 是唯一的门）——
## 弓手捡了铁剑可以卖钱，但不能挥
@export var weapon_type: StringName = &""

@export_group("门槛与来源")
## 推荐等级。**只用来上色/提示，不拦人**（与 DungeonData.rec_level 同一态度）
@export var min_level: int = 1
## 来源：drop（普通/精良/优秀，掉实物）| craft（极品/传说/至尊，只出制书）
## 见 docs/adr/0016-tier-source-split.md
@export var source: StringName = &"drop"

@export_group("经济")
## 商店定价（元宝）。掉落与商店标价共用这一个数；
## 出售进账 = 它 × ShopData.sell_ratio（折价率住在 shop.tres，不在这）
@export var gold_price: int = 0


## 本装备所属槽位的字符串 id（存档 / 装备栏字典的 key）
func slot_id() -> StringName:
	return SLOT_IDS[int(slot)]


## 槽位显示名的翻译 key
func slot_key() -> StringName:
	return SLOT_KEYS[int(slot)]


## 品质颜色。白 / 绿 / 蓝 / 紫 / 橙 / 红 —— 六档，与造梦西游的观感一致。
## **同一件装备在掉落物、图标、面板文字四处都是这个色源**（只有一处定义）
func tier_color() -> Color:
	match tier:
		Tier.LEGENDARY:
			return Color(0.92, 0.28, 0.30)     # 至尊 · 红
		Tier.EPIC:
			return Color(0.95, 0.62, 0.25)     # 传说 · 橙
		Tier.RARE:
			return Color(0.78, 0.55, 0.95)     # 极品 · 紫
		Tier.UNCOMMON:
			return Color(0.45, 0.72, 0.95)     # 优秀 · 蓝
		Tier.FINE:
			return Color(0.46, 0.83, 0.42)     # 精良 · 绿
		_:
			return Color(0.88, 0.88, 0.84)     # 普通 · 灰白


## 三个区间里有没有一条是有值的（空装备的兜底显示用）
func has_no_stat() -> bool:
	return atk_max <= 0 and hp_max <= 0 and def_max <= 0


## 这件装备能 roll 出多少种组合。断言与生成器自检用
func roll_span() -> int:
	return (atk_max - atk_min + 1) * (hp_max - hp_min + 1) * (def_max - def_min + 1)


## 在区间内 roll 出这一件实例的平铺词条。
## **调用方负责让同一个 uid 每次都用同一个种子** —— 见 PlayerState.stat_of()
## （结果不进存档：同一个 uid 算出来永远一样，省掉一版存档迁移）
func roll(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"atk": _pick(rng, atk_min, atk_max),
		"hp": _pick(rng, hp_min, hp_max),
		"def": _pick(rng, def_min, def_max),
	}


func _pick(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	if hi <= lo:
		return maxi(lo, 0)
	return rng.randi_range(maxi(lo, 0), hi)
