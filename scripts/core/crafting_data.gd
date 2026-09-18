class_name CraftingData
extends Resource
## 打造经济（data/economy/crafting.tres）：各档配方、制书买价、材料参考价。
##
## 设计期唯一来源 = `docs/gear-v2/ECONOMY.md`（用料表 + 定价表），
## 由 `tools/apply_economy.py` 从设计期 JSON 生成，**别手改**。
##
## ── 两条铁律（都由落地脚本自检盯着）──────────────────────────
## 1. **分解产量 < 同档打造成本**（每件）—— 否则「分解 → 重造」必赚，白嫖刷装。
##    见 disassemble.tres 与 docs/gear-v2/ECONOMY.md「铁律」。
## 2. **无套利**：可打造装备的卖价 ≤ 买齐材料的参考成本 —— 造出来卖掉必亏元宝，
##    打造只为变强；元宝只由「卖多余的怪掉装」这条正路产生（原则 5.1）。
##
## ── 材料的真相分工 ───────────────────────────────────────────
## 五档材料里，**精铁就是 PlayerState.shards**（强化主料，唯一真相不搬家）；
## 其余四种（玄铁/天晶/龙魂/太乙精金）住在 PlayerState.materials 字典里。
## 这里只用 id 字符串引用它们，不持有任何数量。

## 极品及以上各档的用料：tier(int) → { 材料id: 数量 }。
## key 用 int 的 tier（ItemData.Tier），写成 Dictionary 是因为 tres 对嵌套
## int-key 结构的直接支持有限，生成器统一转成 String key（"3"），读取时转回
@export var recipes: Dictionary = {}

## 制书买价（元宝）：tier(int，字符串 key) → 价格。买 = 解锁该档打造，永久
@export var blueprint_price: Dictionary = {}

## 材料参考价（元宝）：id → 价格。**仅用于无套利自检** ——
## 养成材料一律不上架（原则 5.1：精铁↔元宝互不兑换）
@export var material_value: Dictionary = {}

## 材料显示名的 i18n key：id → StringName
@export var material_name_key: Dictionary = {}


## 某档的用料（返回 { id: qty }；没这档的配方 = 空字典）
func cost_for(tier: int) -> Dictionary:
	return (recipes.get(str(tier), {}) as Dictionary)


## 材料的 i18n key。没登记的 id 返回 id 本身 —— 面板显示一个丑 id
## 比显示一句空话好，而且一眼能看出数据漏了
func mat_key(id: StringName) -> StringName:
	var k := str(material_name_key.get(String(id), ""))
	return StringName(k) if not k.is_empty() else id


## 造这一档需要哪本制书（= 档次本身；价格表里有就是可打造档）
func needs_blueprint(tier: int) -> bool:
	return blueprint_price.has(str(tier))


## 无套利自检用的材料总参考价
func value_of(cost: Dictionary) -> int:
	var total := 0
	for id in cost:
		total += int(material_value.get(String(id), 0)) * int(cost[id])
	return total
