extends Node
## 玩家成长数据（autoload）：等级 / 经验 / 蓝量上限 / 装备 / 强化 —— 「属于玩家」的东西。
##
## 与 PlayerState 合并过考虑——但它已经叫 PlayerState，等级经验就住在同一家：
## 本文件实际承担 shards / level / exp / 装备栏 / 背包 / 强化 六样跨场景数据。
## 升级逻辑也在这（纯数据 + 信号），玩家节点只负责听信号改血条和蓝上限。
##
## ── 装备为什么也存在这里 ──────────────────────────────────────
## 和碎片同一个理由：切场景会重建玩家节点，挂在节点上的东西会丢（实测丢过碎片）。
## 「属于玩家而不是属于关卡」的数据一律放 autoload，这是第三次因此改架构。
##
## ── 装备是【实例】，不是【型号】（2026-09-14 改）────────────────
## 一开始存的是资源路径（`res://data/items/xxx.tres` 这种）——
## 那等于「铁剑」这个**型号**，于是两把铁剑在系统眼里是同一件东西。
## 强化一旦做成逐件（设计原则 5.2：品质档位绑定强化上限），这个模型就塌了：
## 练过的剑卖掉、再捡一把同型号的，它居然也是练过的。
##
## 现在每个**实例**有一个 uid：`资源路径#序号`，例如
## `res://data/items/wp_u5251_0_u94c1u5251.tres#7`。背包和装备栏存 uid，
## 强化等级挂在 uid 上（`forge` 表），一件装备练到几级只跟它自己有关。
## **逐件随机的平铺词条也从 uid 推**（`stat_of`：uid 哈希当种子）——
## 于是「同一个实例的数值固定」不需要额外的存档结构。
##
## 代价：重命名资源文件仍会让存档失效（写在这里备案）。v2 就是这样一批重命名，
## 所以旧档整份不可继续（见 SaveManager.STRUCTURE_VERSION=11）。

## 升级时发。玩家听了加血上限 / 蓝上限并回满
signal level_up(new_level: int)

## 元宝变化时发（拾取 / 出售 / 购买）。HUD 与商店面板听了重刷数字
signal gold_changed(new_gold: int)

## 经验变化时发（包括没升级的零散经验）—— 场景里的玩家节点听它同步，
## 否则 HUD 上的经验条只会在切场景后「突然」跳起来（实测反馈）
signal exp_changed(new_exp: int)

## 装备栏 / 背包 / 强化变化时发（穿戴 / 卸下 / 捡到 / 强化成功）。
## 这些事共用一个信号：界面拿到它一律全量重刷，不做增量。
## 场景里的玩家节点也听它 —— 换装与强化要立刻改变攻击倍率 / 生命上限 / 减伤。
signal equipment_changed

## 槽位 id **不再在这里重复定义** —— 唯一来源是 `ItemData.SLOT_IDS`。
## 2026-09-18 删掉这份副本：v1 时它和 ItemData 各有一份（4 项硬编码），
## 扩到 8 槽时两处都要改，漏一处就是「装备栏少几个槽」这种静默错位。
## 单一定义 = `ItemData.SLOT_IDS`（顺序与 ItemData.Slot 枚举一致）

## 实例 id 的分隔符
const UID_SEP := "#"

## 成长曲线的唯一真相（等级上限 / 经验幂函数 / 每级给多少）
const PROGRESSION_PATH := "res://data/progression.tres"
## 强化的唯一真相（品质上限 / 成本递增 / 收益递减）
const FORGE_PATH := "res://data/forge.tres"
## 商店的唯一真相（库存 / 出售折价率）。买与卖的钱都从这儿过（ADR 无，计划 §3.7）
const SHOP_PATH := "res://data/shop.tres"

@onready var progression: ProgressionData = load(PROGRESSION_PATH) as ProgressionData
@onready var _forge: ForgeData = load(FORGE_PATH) as ForgeData
@onready var _shop: ShopData = load(SHOP_PATH) as ShopData

## 等级上限（给界面用，省得到处 PlayerState.progression.level_cap）
@onready var level_cap: int = progression.level_cap


## 升到下一级需要的经验。**满级返回 0**，所以调用方比较之前先问 is_max()
func exp_needed(level: int) -> int:
	return progression.exp_needed(level)


func is_max_level() -> bool:
	return progression.is_max(level)


var shards: int = 0

## 元宝：**唯一通用货币**（计划 §3.7），只进商店（买 / 卖）。
## 与精铁（shards）刻意互不兑换 —— 两笔钱各管各的，见计划 §3.7 的按语
var gold: int = 0

## 选的角色 id（CharacterData.id）。**属于存档**：每个档可以玩不同的人。
## 空 = 老档 / 还没选过，玩家节点回退默认角色
var character_id: String = ""

var level: int = 1
var exp: int = 0

## 装备栏：槽位 id → 装备**实例 uid**。没穿的槽不在字典里
var equipped: Dictionary = {}
## 背包：捡到但没穿的装备 uid，按捡到的先后排
var bag: Array = []
## 强化表：装备 uid → 强化等级。没练过的 uid 不在表里（= 0 级）
var forge: Dictionary = {}

## 下一个要发的实例序号。进存档 —— 不存的话读档后从 1 重来，
## 新捡的装备会和档案里已有的 uid 撞号，两件东西从此共享强化等级
var next_uid: int = 1

## 主线进度标记（有没有发生过、奖励有没有给过）。键是字符串 flag 名，值都是 true。
## 为什么用字典而不是一堆 bool 成员：flag 会越来越多（每个 NPC、每个主线节点一个），
## 加一个就要改存档结构、改 reset、改测试。字典是加一个 flag 零成本的形状。
## 存档里存的是普通字符串键，没进过历史的 flag 直接不存在 —— 老存档天然兼容。
var flags: Dictionary = {}

## 能同时携带的技能数（人物技能栏就 5 格）
const SKILL_SLOT_COUNT := 5

## 携带的技能：5 个槽，存 SkillData 的资源路径，空串 = 空槽。
## 为什么技能要「解锁了还得挑着带」：技能池会一直长（现在 7 个），
## 但玩家的手只有那么几个键。让玩家在「带哪几个」上做选择，
## 是技能从「收集品」变成「build」的那一步。
var skill_slots: Array = ["", "", "", "", ""]

## 携带的技能变了（装上 / 卸下 / 自动补位）—— 玩家节点听了重建技能表
signal skills_changed

## 词条聚合缓存。装备一变就重算，免得 HUD 每帧去 load 一遍所有装备资源。
## v2 的形状（2026-09-18 从 {"atk": 百分比, "hp": 点, "def": 百分比} 拆开）：
##   atk_flat – 装备平铺攻击合计（点数，**加算**进伤害）
##   atk_pct  – 百分比攻击合计（**只剩强化**；装备攻击不再进这里）
##   hp       – 装备平铺生命合计（点数）
##   def_flat – 装备平铺防御合计（点数，走护甲曲线，不是减伤百分比）
var _bonus: Dictionary = {"atk_flat": 0, "atk_pct": 0.0, "hp": 0, "def_flat": 0}

## 实例词条缓存：uid → {"atk","hp","def"} 已 roll 定的值。
## 不缓存的话，HUD 每帧刷新、每次 take_damage 都要重新 roll 一遍
var _stat_cache: Dictionary = {}


func reset_for_new_game() -> void:
	shards = 0
	gold = 0
	materials.clear()
	blueprints.clear()
	revive_tokens = 0
	revive_bought.clear()
	shop_offers.clear()
	shop_bp_offers.clear()
	shop_refreshed_at = 0.0
	character_id = ""
	level = 1
	exp = 0
	equipped.clear()
	bag.clear()
	forge.clear()
	next_uid = 1
	flags.clear()
	skill_slots = _empty_slots()
	_recalc_bonus()
	equipment_changed.emit()
	skills_changed.emit()


func load_from(d: Dictionary) -> void:
	shards = int(d.get("shards", shards))
	gold = int(d.get("gold", 0))     # 旧档没有这字段 → 从 0 开始（元宝是增量 12 才有的）
	# 旧档没有这字段 → 保持空串，玩家节点回退默认角色
	character_id = str(d.get("character_id", character_id))
	level = progression.clamp_level(int(d.get("level", level)))
	exp = int(d.get("exp", exp))
	equipped = (d.get("equipped", {}) as Dictionary).duplicate()
	bag = (d.get("bag", []) as Array).duplicate()
	forge = (d.get("forge", {}) as Dictionary).duplicate()
	next_uid = int(d.get("next_uid", 0))
	materials = (d.get("materials", {}) as Dictionary).duplicate()
	blueprints = (d.get("blueprints", []) as Array).duplicate()
	revive_tokens = int(d.get("revive_tokens", 0))
	revive_bought = (d.get("revive_bought", {}) as Dictionary).duplicate()
	shop_offers = (d.get("shop_offers", []) as Array).duplicate()
	shop_bp_offers = (d.get("shop_bp_offers", []) as Array).duplicate()
	shop_refreshed_at = float(d.get("shop_refreshed_at", 0.0))
	_ensure_uid_counter()
	flags = (d.get("flags", {}) as Dictionary).duplicate()
	var slots := (d.get("skill_slots", []) as Array)
	skill_slots = _empty_slots()
	for i in mini(slots.size(), SKILL_SLOT_COUNT):
		skill_slots[i] = str(slots[i])
	_recalc_bonus()
	equipment_changed.emit()
	skills_changed.emit()


func save_to() -> Dictionary:
	return {
		"shards": shards,
		"gold": gold,
		"materials": materials.duplicate(),
		"blueprints": blueprints.duplicate(),
		"revive_tokens": revive_tokens,
		"revive_bought": revive_bought.duplicate(),
		"shop_offers": shop_offers.duplicate(),
		"shop_bp_offers": shop_bp_offers.duplicate(),
		"shop_refreshed_at": shop_refreshed_at,
		"character_id": character_id,
		"level": level,
		"exp": exp,
		"equipped": equipped.duplicate(),
		"bag": bag.duplicate(),
		"forge": forge.duplicate(),
		"next_uid": next_uid,
		"flags": flags.duplicate(),
		"skill_slots": skill_slots.duplicate(),
	}


## 老档的「全局强化等级」搬到当前武器上 —— **v2 起删掉了**。
##
## 它存在的意义是让「全局 upgrade 一个数字」那个年代（v8 之前）的存档能读回来。
## v2 换了装备模型（槽位 4→8、品质 3→6、132 件资源全换 id），旧档**整份不可继续**
## （见 SaveManager.slot_usable），所以这段迁移已经是死代码，留着只会误导下一个人。
## 见 docs/adr/0021-gear-v2-rework.md §2.5「删旧件、新 id、不写迁移」


## 把 next_uid 推到「所有已存在 uid 的最大序号 + 1」之后。
## 兜的是**存档里漏了 next_uid**（手改档、以后增字段时的兼容空白）——
## 不兜的话新捡的装备会和档案里已有的 uid 撞号，两件东西从此共享强化等级
func _ensure_uid_counter() -> void:
	var max_seen := 0
	var all: Array = bag.duplicate()
	for s in ItemData.SLOT_IDS:
		all.append(equipped_uid(s))
	for u in all:
		var i := str(u).find(UID_SEP)
		if i >= 0:
			max_seen = maxi(max_seen, int(str(u).substr(i + 1)))
	next_uid = maxi(next_uid, max_seen + 1)


func _empty_slots() -> Array:
	var out: Array = []
	for _i in SKILL_SLOT_COUNT:
		out.append("")
	return out


# ── 装备实例 id ────────────────────────────────────────────────

## 新实例的 uid。序号全局递增，不按路径分 —— 只要在同一份存档里唯一就够了
func make_uid(path: String) -> String:
	var uid := "%s%s%d" % [path, UID_SEP, next_uid]
	next_uid += 1
	return uid


## uid → 资源路径。**没有 # 的串原样返回** ——
## 存档里的 uid 一定是 `路径#序号` 的形状（make_uid 生成），
## 这里不特殊处理「纯路径」，那只是同一个字符串函数的自然结果
func path_of(uid: String) -> String:
	var i := uid.find(UID_SEP)
	return uid if i < 0 else uid.substr(0, i)


## uid → 装备数据。坏路径返回 null（不崩）
func item_of(uid: String) -> ItemData:
	if uid.is_empty():
		return null
	return load(path_of(uid)) as ItemData


# ── 强化 ───────────────────────────────────────────────────────

## 这件装备练到几级了（没练过 = 0）
func forge_level(uid: String) -> int:
	return int(forge.get(uid, 0))


## 这件装备能练到几级（按品质）。不是装备资源就返回 0
func forge_max(uid: String) -> int:
	var it := item_of(uid)
	return 0 if it == null else _forge.max_for_tier(int(it.tier))


## 从当前等级再练一级要花多少精铁
func forge_cost(uid: String) -> int:
	return _forge.cost_at_level(forge_level(uid))


## 这件装备的强化贡献的攻击加成（已含收益递减）
func forge_atk(uid: String) -> float:
	return _forge.atk_bonus_at(forge_level(uid))


## 练到 level 级时总共给多少攻击加成（**不看具体哪件**）。
## 面板要显示「再练一级能多多少」，断言要验「每级给的比上一级少」—— 两条都需要它
func forge_atk_at(level: int) -> float:
	return _forge.atk_bonus_at(level)


func forge_is_maxed(uid: String) -> bool:
	return forge_level(uid) >= forge_max(uid)


## 现在能不能强化这一件（没到顶 + 精铁够）
func can_forge(uid: String) -> bool:
	return not uid.is_empty() and not forge_is_maxed(uid) and shards >= forge_cost(uid)


## 强化一级。花掉精铁、写进 forge 表、重算属性并发信号。
## 返回 true = 成功了；false = 到顶了 / 精铁不够 / 不是装备
func forge_once(uid: String) -> bool:
	if not can_forge(uid):
		return false
	shards -= forge_cost(uid)
	forge[uid] = forge_level(uid) + 1
	_recalc_bonus()
	equipment_changed.emit()
	return true


## 摆回实例计数器（读档用）。直接写字段也行，但这个方法会顺手跟已有的 uid 取大值 ——
## 手改过档 / 旧档漏了 next_uid 时，这是最后一道兜底
func set_uid_counter(n: int) -> void:
	next_uid = maxi(n, 1)
	_ensure_uid_counter()


## 所有能强化的装备（已装备的 4 件在前，背包在后），元素是 uid。
## 铁匠铺的列表就用它 —— 顺序稳定，光标不会跳
func forgeable_uids() -> Array:
	var out: Array = []
	for s in ItemData.SLOT_IDS:
		var uid := equipped_uid(s)
		if not uid.is_empty():
			out.append(uid)
	out.append_array(bag)
	return out


# ── 元宝（商店经济，计划 §3.7）────────────────────────────────
# 两条管道进、一条管道出：打怪掉小额 + 出售装备 → 元宝 → 商店买。
# 与精铁（shards）刻意**互不兑换** —— 两笔钱让玩家每次花钱都要判断该用哪个；
# 能互换就等于只有一种。精铁只进强化，元宝只进商店。

## 商店数据（库存 / 折价率）。界面要列货架、要算卖价都从这儿拿，
## 别摸 _shop 私有成员
func shop() -> ShopData:
	return _shop

func add_gold(n: int) -> void:
	if n <= 0:
		return
	gold += n
	gold_changed.emit(gold)


## 花 n 个元宝。花不起返回 false —— 「为什么没花成」由调用方说出来（不静默）
func spend_gold(n: int) -> bool:
	if n <= 0 or gold < n:
		return false
	gold -= n
	gold_changed.emit(gold)
	return true


## 从商店买一件（必须在库存里）。成功 = 扣钱 + 新实例进背包，返回 uid；
## 失败返回空串（不在库存 / 不是装备 / 元宝不够 —— 界面负责区分原因）。
## 买来的是**新实例**：商店卖的是型号，玩家拿到的是自己那一件（与掉落同一模型）
func buy_item(path: String) -> String:
	# 货架有两份：stock（底线清单）与 shop_offers（本期随机货）——
	# 买的是「这家店摆出来的东西」，两处都算在售
	var sd := shop()
	var on_sale: bool = sd != null and (sd.has_stock(path) or shop_offers.has(path))
	if sd == null or not on_sale:
		return ""
	var it := load(path) as ItemData
	if it == null:
		return ""
	if not spend_gold(it.gold_price):
		return ""
	return add_item(path)


## 出售一件**背包里的**装备，换元宝。价格只有一套算法：
## 卖价 = 定价 × 折价率（ShopData.sell_ratio，向下取整）。
## 返回进账（0 = 卖不了）。穿在身上的不收 —— 先卸下再来，
## 「一个按键卖掉正在穿的甲」不该是可能发生的事故
func sell_item(uid: String) -> int:
	if not bag.has(uid):
		return 0
	var it := item_of(uid)
	if it == null:
		return 0
	var gain := _shop.sell_price(int(it.gold_price))
	_remove_from_bag(uid)
	equipment_changed.emit()
	add_gold(gain)
	return gain


# ── 材料与打造（批 6 · 回收闭环，原则 5.5）────────────────────

## 打造/强化的经济数据（懒加载 —— 测试与开局都未必用到）
var _crafting: CraftingData = null
var _disassemble: DisassembleData = null

const CRAFTING_PATH := "res://data/economy/crafting.tres"
const DISASSEMBLE_PATH := "res://data/economy/disassemble.tres"

## 材料的元 id。**精铁就是 shards**（强化主料的唯一真相，不搬家 ——
## 材料字典里没有它，靠 MAT_REFINED_IRON 这个 id 转发到 shards）
const MAT_REFINED_IRON := &"mat_refined_iron"


## 四种稀有材料的持有量：id → 数量。精铁不在里面（见 MAT_REFINED_IRON）
var materials: Dictionary = {}

## 已到手的**逐件制书**（装备资源路径数组）。神拍板：制书不是「档位」的 ——
## 打造寒月剑要「寒月剑制作书」，具体到每一件；一本档位书解锁 22 件
## 等于把 66 件神装一次全放出来，打造就没有「下一件目标」了。
## 存装备路径而不是另编制书 id：路径本身就是那件装备的唯一键，
## 打造页 / 商店 / 掉落引用的是同一串，不会出现两套 id 对不上的事
var blueprints: Array = []


func crafting() -> CraftingData:
	if _crafting == null:
		_crafting = load(CRAFTING_PATH) as CraftingData
	return _crafting


func disassemble_table() -> DisassembleData:
	if _disassemble == null:
		_disassemble = load(DISASSEMBLE_PATH) as DisassembleData
	return _disassemble


## 某种材料的持有量。精铁转发 shards，其余查 materials
func material_count(id: StringName) -> int:
	return shards if id == MAT_REFINED_IRON else int(materials.get(String(id), 0))


## 加材料。数量可为负吗？不 —— 扣材料一律走 pay_materials（原子检查），这里只加
func add_material(id: StringName, n: int) -> void:
	if n <= 0:
		return
	if id == MAT_REFINED_IRON:
		shards += n
	else:
		var k := String(id)
		materials[k] = int(materials.get(k, 0)) + n


## 原子付料：**先验够不够、再一次扣清** —— 半路断货的扣一半是最难看的 bug。
## 返回 false 时一个子都不会动。精铁那份转给 shards
func pay_materials(cost: Dictionary) -> bool:
	for id in cost:
		if material_count(StringName(String(id))) < int(cost[id]):
			return false
	for id in cost:
		var k := String(id)
		var n := int(cost[id])
		if id == String(MAT_REFINED_IRON):
			shards -= n
		else:
			materials[k] = int(materials.get(k, 0)) - n
	return true


## 干跑版：只验够不够，一分不动。界面在「能不能造」的着色与提示上用它 ——
## 刷新一帧跑一次真扣款就成事故了
func pay_materials_dry_run(cost: Dictionary) -> bool:
	for id in cost:
		if material_count(StringName(String(id))) < int(cost[id]):
			return false
	return true


## 分解一件**背包里的**装备 → 材料（按档；强化等级不返还 —— 见 disassemble.tres 注）。
## 返回产量字典（空 = 拆不了：不在包里 / 资源丢失 / 这个档没登记产量）。
## 与「出售」互不兑换（原则 5.1）：卖走元宝、拆走材料，玩家按缺什么选
func disassemble(uid: String) -> Dictionary:
	if not bag.has(uid):
		return {}
	var it := item_of(uid)
	if it == null:
		return {}
	var yld: Dictionary = disassemble_table().yield_for(int(it.tier))
	if yld.is_empty():
		return {}
	_remove_from_bag(uid)
	for id in yld:
		add_material(StringName(String(id)), int(yld[id]))
	equipment_changed.emit()
	return yld


## 打造：材料 + **这一件**的制书 → 一件**全新实例**进背包。
## 返回新 uid（空串 = 造不了；原因只有调用方需要时才查 —— 界面上逐条说）：
## 没这本书 / 材料不够 / 路径不是装备。打造不做「缺一件也造，回头补」——
## 那等于让玩家欠账，欠账清单是另一套系统
func craft(path: String) -> String:
	var it := load(path) as ItemData
	if it == null:
		return ""
	if not has_blueprint(path):
		return ""
	if not pay_materials(crafting().cost_for(int(it.tier))):
		return ""
	return add_item(path)


## 买制书（逐件）。价格按**装备的档**走（CraftingData.blueprint_price，
## 商店面板标同一份）—— 书是逐件的，钱仍是档位价：同一档的打造难度一样，
## 没理由「寒月剑的书比破军剑的贵」。
## 已有这本书再买 = 白花钱，直接拒绝 —— 「重复付费解锁已拥有的东西」
## 不该是可能的事故
func unlock_blueprint(path: String) -> bool:
	if has_blueprint(path):
		return false
	var it := load(path) as ItemData
	if it == null:
		return false
	var price := int(crafting().blueprint_price.get(str(int(it.tier)), 0))
	if price <= 0 or not spend_gold(price):
		return false
	blueprints.append(path)
	return true


func has_blueprint(path: String) -> bool:
	return blueprints.has(path)


# ── 商店货架刷新（每 4 现实小时换一批装备；制书常驻）──────────

## 当前货架（随机抽的装备路径数组）。**不是 ShopData.stock** ——
## stock 是「这家店卖什么档次」的底线清单，offers 是这一批实际摆出来的货
var shop_offers: Array = []

## 本期的**随机制书货架**（装备路径数组）。制书不再常驻 66 本 ——
## 每期独立 roll：10% 极品 / 5% 传说 / 1% 至尊（2026-09-18 神定的概率与定价），
## 出了就随机该档的一件装备。**本期限购 1 本**：买走即从货架上撤下，
## 再想要只能等下次刷新
var shop_bp_offers: Array = []

## 上次刷新的时刻（Unix 秒）。存档 —— 关游戏时间也在走
var shop_refreshed_at: float = 0.0


## 货架过期了就重抽。**进商店面板前调**（打开时看一眼，不靠时钟轮询）。
## 装备：从已建档的掉落档次（普通/精良/优秀）里不重复抽 7 件 ——
## 极品+永远不进货（途径隔离，ADR-0016）。
## 制书：8 个书位独立 roll（10/5/1%），出书才占位。
## 首次（没档/刚 reset）：立刻抽一批并把时刻设为现在
func ensure_shop_fresh() -> void:
	var hours := 4.0
	var sd := shop()
	if sd != null:
		hours = float(sd.refresh_hours)
	var now := Time.get_unix_time_from_system()
	if shop_offers.is_empty() or now - shop_refreshed_at >= hours * 3600.0:
		shop_offers = _roll_shop_offers(7)   # 7 件 + 尾部一条还魂丹 = 左栏 8 行正好
		shop_bp_offers = _roll_bp_offers(8)
		shop_refreshed_at = now


## 抽一批装备货架：三档混合（普通偏多）。不重复 —— 同一件摆两份没有意义
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


## 抽本期的制书：8 个书位，每位独立 roll 档次（2026-09-18 神定：
## 极品 10% / 传说 5% / 至尊 1%，其余 84% 这期不出）——
## 出了就随机该档的一件装备。**独立 roll 天然混合档次**，不会一整批全是同一档
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
	var left: float = shop_refreshed_at + hours * 3600.0 - Time.get_unix_time_from_system()
	return maxf(left, 0.0)


# ── 还魂丹（原则 5.7：死亡罚效率不罚进度，丹是安全网不是免死金牌）──

## 还魂丹持有数。用一枚 = 原地满血复活，省掉「重开本」这一趟
var revive_tokens: int = 0

## 每张地图已买的还魂丹数（map_id → n）。**限购按图记** ——
## 设计 5.7：商店 200 元宝/个、每章限购 5；不限购它就成了「死了花钱续命」的常规操作
var revive_bought: Dictionary = {}


## 用一枚还魂丹。返回 false = 没丹了（调用方别把按钮按出「没反应」）
func use_revive_token() -> bool:
	if revive_tokens <= 0:
		return false
	revive_tokens -= 1
	return true


## 进图补给：每张地图**第一次进**送 2 枚（进图就领，与通关无关 ——
## 「首通不附带奖励」的红线不能碰，进图补给是唯一合规的白送挂点）。
## 返回 true = 这次真的发了（第一次进）
func grant_map_supply(map_id: StringName) -> bool:
	var key := "revive_supply_%s" % map_id
	if flags.has(key):
		return false
	flags[key] = true
	revive_tokens += 2
	return true


## 商店买还魂丹（限购：每图 5 枚）。map_id 用**玩家最近进的图** ——
## 人在城镇买，账记到他要打的图上
func buy_revive_token(map_id: StringName) -> bool:
	var key := String(map_id)
	var bought := int(revive_bought.get(key, 0))
	if bought >= 5:
		return false
	if not spend_gold(REVIVE_PRICE):
		return false
	revive_bought[key] = bought + 1
	revive_tokens += 1
	return true


func revive_bought_in(map_id: StringName) -> int:
	return int(revive_bought.get(String(map_id), 0))


## 还魂丹定价（200 元宝）。放这儿是因为唯一动它的两个界面（商店标价 / 买）
## 都从这取 —— 别在面板里写第二份 200
const REVIVE_PRICE := 200


# ── 主线进度标记 ───────────────────────────────────────────────

func set_flag(name: StringName) -> void:
	if name == &"":
		return
	flags[String(name)] = true


func has_flag(name: StringName) -> bool:
	return name != &"" and flags.has(String(name))


# ── 技能栏 ─────────────────────────────────────────────────────

## 取某个槽位的技能（空槽返回 null）
func skill_at(i: int) -> SkillData:
	if i < 0 or i >= skill_slots.size():
		return null
	var p := str(skill_slots[i])
	return load(p) as SkillData if not p.is_empty() else null


func skill_paths() -> Array:
	return skill_slots.duplicate()


func carries(path: String) -> bool:
	return skill_slots.has(path)


## 把技能装进指定槽位。同一个技能已经在别的槽里的话先摘掉 ——
## 不然会出现「同一个技能占两格、按两个键放同一招」这种明显是 bug 的配置
func set_skill_slot(i: int, path: String) -> void:
	if i < 0 or i >= SKILL_SLOT_COUNT:
		return
	var idx := skill_slots.find(path)
	if idx >= 0 and idx != i:
		skill_slots[idx] = ""
	skill_slots[i] = path
	skills_changed.emit()


func clear_skill_slot(i: int) -> void:
	if i < 0 or i >= SKILL_SLOT_COUNT:
		return
	skill_slots[i] = ""
	skills_changed.emit()


func clear_skill_slot_by_path(path: String) -> void:
	var idx := skill_slots.find(path)
	if idx >= 0:
		clear_skill_slot(idx)


## 自动补位：把「已解锁但没带着」的技能依次填进空槽。
## 只在有空槽时填 —— 槽满了以后换哪个，是玩家的决定，不是系统的
func auto_fill_slots(available: Array) -> bool:
	var changed := false
	for path in available:
		var p := str(path)
		if p.is_empty() or carries(p):
			continue
		var empty := skill_slots.find("")
		if empty < 0:
			break
		skill_slots[empty] = p
		changed = true
	if changed:
		skills_changed.emit()
	return changed


# ── 装备栏操作 ─────────────────────────────────────────────────

## 当前角色的定义（缓存住 —— 目录扫描不必每次装备都跑一遍）
var _character: CharacterData = null
var _character_loaded_for := ""


func character_def() -> CharacterData:
	if _character == null or _character_loaded_for != character_id:
		_character = CharacterData.by_id(StringName(character_id))
		if _character == null:
			_character = CharacterData.default_character()
		_character_loaded_for = character_id
	return _character


## 这件装备当前角色能不能穿。武器看类型匹配；防具/饰品不限
func can_equip(item: ItemData) -> bool:
	if item == null:
		return false
	if item.weapon_type == &"":
		return true
	return item.weapon_type == character_def().weapon_type

## 某槽位穿着的装备 uid（空槽返回空串）
func equipped_uid(slot: StringName) -> String:
	return str(equipped.get(String(slot), ""))


## 取某个槽位穿着的装备。空槽返回 null
func item_at(slot: StringName) -> ItemData:
	return item_of(equipped_uid(slot))


## 按槽位顺序取「当前穿着的全部装备」，空槽是 null（界面按顺序画四行）
func equipped_list() -> Array:
	var out: Array = []
	for s in ItemData.SLOT_IDS:
		out.append(item_at(s))
	return out


## 捡到一件装备：发一个新实例 id 进背包。返回新 uid；空串 = 这不是一件装备
func add_item(path: String) -> String:
	if not (load(path) is ItemData):
		push_warning("PlayerState: 不是装备资源: %s" % path)
		return ""
	var uid := make_uid(path)
	bag.append(uid)
	equipment_changed.emit()
	return uid


## 穿上一件背包里的装备（参数是 uid）。返回被替换下来的那件 uid（"" = 原来空槽）。
## 换下来的自动回背包 —— 玩家不该因为换装而丢东西。
##
## **武器类型是唯一的门**（M4 第二角色）：武器必须与当前角色的 weapon_type 匹配
## —— 弓手捡了铁剑可以卖钱，但不能挥。防具/饰品（weapon_type 为空）不限
func equip(uid: String) -> String:
	var item := item_of(uid)
	if item == null:
		return ""
	if not can_equip(item):
		return ""
	_remove_from_bag(uid)
	var slot := String(item.slot_id())
	var old := equipped_uid(StringName(slot))
	if not old.is_empty():
		bag.append(old)          # 换下来的回背包
	equipped[slot] = uid
	_recalc_bonus()
	equipment_changed.emit()
	return old


## 卸下某个槽位，装备回背包。返回卸下的 uid（"" = 本来就空着）
func unequip(slot: StringName) -> String:
	var key := String(slot)
	var uid := str(equipped.get(key, ""))
	if uid.is_empty():
		return ""
	equipped.erase(key)
	bag.append(uid)
	_recalc_bonus()
	equipment_changed.emit()
	return uid


## 背包里去掉某件（穿上时调）。找不到就什么都不做 ——
## 老档里的装备可能是「直接摆进装备栏」的，不在背包里
func _remove_from_bag(uid: String) -> void:
	var idx := bag.find(uid)
	if idx >= 0:
		bag.remove_at(idx)


## 全部装备的词条总和（含各件的强化加成）。形状见 `_bonus` 的声明处
func bonus_total() -> Dictionary:
	return _bonus


## 这件装备**实例**的平铺词条（已定的值）：{"atk": 点, "hp": 点, "def": 点}
##
## ── 为什么结果不进存档 ────────────────────────────────────────
## 用 uid 的哈希当随机种子 —— **同一个实例每次算出来完全一样**。
## 于是「逐件随机」（ADR-0017）既不需要新的存档结构、也不会因为读档或换场景而变；
## 断言也能直接对账（与 audio.gd 用哈希生成噪声同一个理由：可复现才拿得住）。
## 区间是 0/0 的装备（防具只有防御那种）取到 0，不影响别的轨道
func stat_of(uid: String) -> Dictionary:
	if uid.is_empty():
		return {"atk": 0, "hp": 0, "def": 0}
	if _stat_cache.has(uid):
		return _stat_cache[uid]
	var it := item_of(uid)
	var out: Dictionary
	if it == null:
		out = {"atk": 0, "hp": 0, "def": 0}
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(uid)
		out = it.roll(rng)
	_stat_cache[uid] = out
	return out


## 直接摆入装备栏、背包与强化表（读档用）。摆完重算词条并发信号让玩家节点跟上
func set_equipment(e: Dictionary, b: Array, f: Dictionary = {}) -> void:
	equipped = e.duplicate()
	bag = b.duplicate()
	forge = f.duplicate()
	_ensure_uid_counter()
	_recalc_bonus()
	equipment_changed.emit()


## 比例类属性的硬上限（设计原则 4.2）。**所有比例属性都必须从这儿过一道** ——
## 将来加暴击 / 闪避 / 穿透时，把上限加进这个 match，别在各自的计算里各写一份。
## 未知的比例属性一律夹到 [0, 1]：宁可保守，也不要一个没设上限的百分比流出去
##
## ⚠️ 2026-09-18（v2）：**防御已经不是比例属性了**。它现在是平铺点数，
## 上限改由 `Health.armor_reduction()` 的护甲曲线自己卡（def=150 → 0.6）。
## 所以这里删掉了 `&"def"` 分支 —— **别再往这儿送 def**，那会变成「夹 0.6 但单位是点」
## 这种静默的错。（4.2「比例属性要有天花板」这条本身没变，只是天花板搬了家）
func clamp_ratio(key: StringName, value: float) -> float:
	match key:
		_:
			return clampf(value, 0.0, 1.0)


func _recalc_bonus() -> void:
	var atk_flat := 0
	var atk_pct := 0.0
	var hp := 0
	var def_flat := 0
	for s in ItemData.SLOT_IDS:
		var uid := equipped_uid(s)
		if uid.is_empty():
			continue
		var st := stat_of(uid)
		atk_flat += int(st.get("atk", 0))
		hp += int(st.get("hp", 0))
		def_flat += int(st.get("def", 0))
		atk_pct += forge_atk(uid)                 # 强化加成叠进同一个乘区（4.1）
	var prog := progression
	_bonus = {
		# 平铺攻击**不进软上限**：能穿的件数是固定的（8 槽各 1 件），每件的上限由档位封死
		# —— 压根不存在「无限堆叠」这件事（ADR-0021 §2.6）
		"atk_flat": atk_flat,
		# 强化% 仍然要压：单件练到顶是 +72.8%，8 件叠起来 +582%。
		# knee/cap 沿用 1.0/1.0（量级没变，还是百分比）。
		# ⚠️ **别把这条曲线套到平铺攻击上** —— 48 点攻击走 soften(x,1,1) 会变成 1.98
		"atk_pct": prog.soften(atk_pct, prog.soft_knee_atk, prog.soft_cap_atk),
		# 平铺生命同理不进软上限：8 件是固定件数，档位也封了每件的上限
		"hp": hp,
		# 平铺防御不进这里 —— 它走 Health 的护甲曲线，在那里卡 0.6（4.2 的上限仍只有一处）
		"def_flat": def_flat,
	}


# ── 升级 ───────────────────────────────────────────────────────

## 加经验，够数就升级（可连升）。返回升了几级。
##
## **满级之后不再累积经验**（直接丢），不是「攒着但没用」——
## 后者会让 HUD 上的经验条在满级后继续涨，玩家以为还能升。
func add_exp(amount: int) -> int:
	if amount <= 0 or is_max_level():
		return 0
	exp += amount
	var ups := 0
	while not is_max_level() and exp >= exp_needed(level):
		exp -= exp_needed(level)
		level += 1
		ups += 1
		level_up.emit(level)
	if is_max_level():
		exp = 0
	exp_changed.emit(exp)
	return ups
