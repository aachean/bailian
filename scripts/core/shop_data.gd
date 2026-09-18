class_name ShopData
extends Resource
## 商店数据（data/shop.tres）：卖什么、收二手打几折。
##
## ── 为什么价格不写在这里 ──────────────────────────────────────
## 买价是**装备自己的属性**（ItemData.gold_price，逐件写在它的 .tres 里）——
## 同一把剑掉落时值多少、商店里标多少，必须是同一个数。
## 这里只存两样商店「作为一家店」才有的事：库存清单和二手折价率。
##
## ── 卖价为什么只算折价 ────────────────────────────────────────
## 卖价 = 定价 × sell_ratio（向下取整），不看成色、不看强化等级。
## 逐件估价（练过的剑卖得贵）是合理的，但第一版不做：
## 它会引出「练到几级最划算再卖」的刷钱玩法，等经济真的转起来再调。

## 库存：ItemData 资源路径列表。**开局就是这份** ——
## 「空店」指解锁前的状态（计划 §3.7），不是指货架会成长
@export var stock: Array[String] = []

## 出售折价率。0.5 = 半价回收（造梦西游观感）
@export_range(0.0, 1.0, 0.05) var sell_ratio: float = 0.5

## 制书上架：tier(int，字符串 key) → 元宝价。价格真相在 CraftingData.blueprint_price，
## 这里存的是「上架了哪几档」+ 面板直接标价用的快照 —— 两边由 apply_economy.py 同源生成。
## **养成材料不上架**（原则 5.1：精铁↔元宝互不兑换），上架的只有制书这种「解锁」类商品
@export var blueprint_tiers: Dictionary = {}


func has_stock(path: String) -> bool:
	return stock.has(path)


## 出售进账（元宝）。输入是装备的定价，不是 uid ——
## 定价怎么来的（哪件装备、几级强化）是调用方的事，这里只有一条公式
func sell_price(gold_price: int) -> int:
	return int(floor(gold_price * sell_ratio))
