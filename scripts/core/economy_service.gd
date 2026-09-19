class_name EconomyService
extends RefCounted
## 经济域服务：元宝流动 + 买卖 + 商店货架刷新。
##
## ── 它为什么存在（2026-09-19，[ADR-0027](../../docs/adr/0027-playerstate-decomposition.md)）──
## `PlayerState` 曾一个人扛九个子系统、被全项目引用 269 次 —— 动一处抖一片。
## 这是拆解的**第一个域**（试点）：逻辑搬到这里，`PlayerState` 退成薄门面转发，
## 对外接口一字不变（`PlayerState.buy_item()` 照样能调，269 处引用不炸）。
##
## ── 过渡期的分工（门面阶段）───────────────────────────────────
## **数据仍住 `PlayerState`**（gold / shop_offers / shop_bp_offers / shop_refreshed_at）——
## 因为 `shop_panel.gd` 直接 `.erase()`、测试直接赋值，字段得留在容器上（Phase 6 再掏薄）。
## 本服务持有 `PlayerState` 的引用 `_s`，读写它的字段、借它的信号广播。
## **商店数据 `ShopData` 归本域自己拥有**（懒加载），不再挂在 `PlayerState` 上。
##
## ── 跨域契约（第一份，供后续四个域照抄）──────────────────────
## `buy_item` / `sell_item` 要碰**物品域**（进背包 / 出背包）。物品域这轮还没抽出来，
## 所以这里调 `_s.add_item()` / `_s.item_of()` / `_s._remove_from_bag()` —— 它们现在还在
## `PlayerState` 上。物品域抽出来时（Phase 3），把这几个调用点改指到物品域服务即可，
## **这就是缝**：一个域要用另一个域，只经过对方的公开方法，不碰对方的私有数据。

## 商店的唯一真相（库存 / 折价率）。买与卖的钱都从这儿过
const SHOP_PATH := "res://data/shop.tres"

## 商店货架刷新状态住**全局文件**，不进存档槽（2026-09-18 神圈注）：
## 「每 4 现实小时」意味着时钟属于现实世界、不属于某个存档 —— 放存档槽里
## 退出时机不对就会回到 4:00:00。所有存档槽共享同一家店的同一批货、同一个钟。
const SHOP_STATE_PATH := "user://shop_refresh.cfg"

## 数据容器（PlayerState）。读写它的字段 gold / shop_offers / ...，借它的信号
var _s: Object

## 商店数据（懒加载 —— 测试与开局未必用到）
var _shop: ShopData = null


func _init(state: Object) -> void:
	_s = state


## 商店数据（库存 / 折价率）。界面要列货架、算卖价都从这儿拿
func shop() -> ShopData:
	if _shop == null:
		_shop = load(SHOP_PATH) as ShopData
	return _shop


# ── 元宝 ───────────────────────────────────────────────────────
# 两条管道进、一条管道出：打怪掉小额 + 出售装备 → 元宝 → 商店买。
# 与精铁刻意**互不兑换**（原则 5.1）：精铁只进强化，元宝只进商店。

func add_gold(n: int) -> void:
	if n <= 0:
		return
	_s.gold += n
	_s.gold_changed.emit(_s.gold)


## 花 n 个元宝。花不起返回 false —— 「为什么没花成」由调用方说出来（不静默）
func spend_gold(n: int) -> bool:
	if n <= 0 or _s.gold < n:
		return false
	_s.gold -= n
	_s.gold_changed.emit(_s.gold)
	return true


## 从商店买一件（必须在库存里）。成功 = 扣钱 + 新实例进背包，返回 uid；
## 失败返回空串（不在库存 / 不是装备 / 元宝不够 —— 界面负责区分原因）。
## 买来的是**新实例**：商店卖的是型号，玩家拿到的是自己那一件（与掉落同一模型）
func buy_item(path: String) -> String:
	# 货架有两份：stock（底线清单）与 shop_offers（本期随机货）—— 两处都算在售
	var sd := shop()
	var on_sale: bool = sd != null and (sd.has_stock(path) or _s.shop_offers.has(path))
	if sd == null or not on_sale:
		return ""
	var it := load(path) as ItemData
	if it == null:
		return ""
	if not spend_gold(it.gold_price):
		return ""
	return _s.add_item(path)     # ← 跨域契约：进背包是物品域的事


## 出售一件**背包里的**装备，换元宝。卖价 = 定价 × 折价率（向下取整）。
## 返回进账（0 = 卖不了）。穿在身上的不收 —— 先卸下再来。
func sell_item(uid: String) -> int:
	if not _s.bag.has(uid):       # ← 跨域契约：背包归物品域
		return 0
	var it: ItemData = _s.item_of(uid)
	if it == null:
		return 0
	var gain := shop().sell_price(int(it.gold_price))
	_s._remove_from_bag(uid)      # ← 跨域契约：出背包是物品域的事
	_s.equipment_changed.emit()
	add_gold(gain)
	return gain


# ── 商店货架刷新（每 4 现实小时换一批装备；制书也随机）──────────

## 从全局文件恢复货架状态（ensure_shop_fresh 开头调）
func _load_shop_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SHOP_STATE_PATH) != OK:
		return
	_s.shop_offers = cfg.get_value("shop", "offers", [])
	_s.shop_bp_offers = cfg.get_value("shop", "bp_offers", [])
	_s.shop_refreshed_at = float(cfg.get_value("shop", "refreshed_at", 0.0))


## 货架状态写回全局文件。抽新货 / 买走撤下时都要调
func save_shop_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("shop", "offers", _s.shop_offers)
	cfg.set_value("shop", "bp_offers", _s.shop_bp_offers)
	cfg.set_value("shop", "refreshed_at", _s.shop_refreshed_at)
	cfg.save(SHOP_STATE_PATH)


## 货架过期了就重抽。**进商店面板前调**（打开时看一眼，不靠时钟轮询）。
## 装备：从已建档的掉落档次（普通/精良/优秀）里不重复抽 7 件。
## 制书：8 个书位独立 roll（10/5/1%），出书才占位。
## 首次（没有任何记录）：立刻抽一批并把时刻设为现在
func ensure_shop_fresh() -> void:
	var hours := 4.0
	var sd := shop()
	if sd != null:
		hours = float(sd.refresh_hours)
	_load_shop_state()
	var now := Time.get_unix_time_from_system()
	if now - _s.shop_refreshed_at >= hours * 3600.0:
		_s.shop_offers = _roll_shop_offers(7)   # 7 件 + 尾部一条还魂丹 = 左栏 8 行正好
		_s.shop_bp_offers = _roll_bp_offers(8)
		_s.shop_refreshed_at = now
		save_shop_state()
	elif _s.shop_offers.is_empty():
		# 没到点但装备卖光了：只补装备，**时钟不动**（制书不补）
		_s.shop_offers = _roll_shop_offers(7)
		save_shop_state()


## 抽一批装备货架：三档混合（普通偏多）。不重复
func _roll_shop_offers(n: int) -> Array:
	var pool: Array = []
	for t in [ItemData.Tier.COMMON, ItemData.Tier.COMMON, ItemData.Tier.FINE, ItemData.Tier.UNCOMMON]:
		pool.append_array(GameProgress.drop_pool(t))     # 普通抽两份权重
	pool.shuffle()
	var out: Array = []
	for p in pool:
		if not out.has(p):
			out.append(p)
		if out.size() >= n:
			break
	return out


## 抽本期的制书：8 个书位，每位独立 roll 档次（极品 10% / 传说 5% / 至尊 1%，
## 其余 84% 这期不出）—— 出了就随机该档的一件装备。独立 roll 天然混合档次
func _roll_bp_offers(slots: int) -> Array:
	var out: Array = []
	for _i in slots:
		var r := randf()
		var tier := -1
		if r < 0.10:
			tier = ItemData.Tier.RARE
		elif r < 0.15:
			tier = ItemData.Tier.EPIC
		elif r < 0.16:
			tier = ItemData.Tier.LEGENDARY
		if tier < 0:
			continue
		var pool := GameProgress.drop_pool(tier)
		if pool.is_empty():
			continue
		var path: String = pool.pick_random()
		if not out.has(path):
			out.append(path)
	return out


## 距下次刷新还剩多少秒（面板倒计时用；0 = 已过期，下次打开就换）
func shop_refresh_in() -> float:
	var hours := 4.0
	var sd := shop()
	if sd != null:
		hours = float(sd.refresh_hours)
	var left: float = _s.shop_refreshed_at + hours * 3600.0 - Time.get_unix_time_from_system()
	return maxf(left, 0.0)
