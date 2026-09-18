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
##
## 制书**不在这里**：它不是档位商品 —— 神裁定（2026-09-18）制书逐件走，
## 66 本列表由 ShopPanel 从 `GameProgress.drop_pool`（可打造档的装备索引）现拼，
## 价格按档从 CraftingData.blueprint_price 取。商店数据里只留装备货架。


func has_stock(path: String) -> bool:
	return stock.has(path)


## 出售进账（元宝）。输入是装备的定价，不是 uid ——
## 定价怎么来的（哪件装备、几级强化）是调用方的事，这里只有一条公式
func sell_price(gold_price: int) -> int:
	return int(floor(gold_price * sell_ratio))
