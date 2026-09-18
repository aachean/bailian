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
## 一开始存的是资源路径（"res://data/items/iron_sword.tres"）——
## 那等于「铁剑」这个**型号**，于是两把铁剑在系统眼里是同一件东西。
## 强化一旦做成逐件（设计原则 5.2：品质档位绑定强化上限），这个模型就塌了：
## 练过的剑卖掉、再捡一把同型号的，它居然也是练过的。
##
## 现在每个**实例**有一个 uid：`资源路径#序号`，例如
## `res://data/items/iron_sword.tres#7`。背包和装备栏存 uid，
## 强化等级挂在 uid 上（`forge` 表），一件装备练到几级只跟它自己有关。
##
## **旧档天然兼容**：老存档里的纯路径就是一个「没有 # 后缀的 uid」，
## path_of() 原样返回，forge 表里查不到就是 0 级。不需要迁移代码。
##
## 代价：重命名资源文件仍会让老档失效（开发期可接受，写在这里备案）。

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
	_migrate_legacy_upgrade(int(d.get("upgrade", 0)))
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


## 老档的「全局强化等级」搬到当前武器上（clamp 到该品质的上限）。
## 旧档里 upgrade 是玩家身上的一个数字，与装备无关 —— 新模型里没有它的位置了。
## 找不到武器就丢掉（无法归属），这一点写在 ADR 里
func _migrate_legacy_upgrade(legacy: int) -> void:
	if legacy <= 0:
		return
	var w := equipped_uid(&"weapon")
	if w.is_empty():
		return
	forge[w] = mini(legacy, forge_max(w))


## 把 next_uid 推到「所有已存在 uid 的最大序号 + 1」之后。
## 存档里没带 next_uid（旧档 / 手改档）时靠这一步兜底，
## 否则新捡的装备会撞上档案里已有的 uid
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


## uid → 资源路径。**没有 # 的串原样返回** —— 老存档里的纯路径就是这种情况
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
	if _shop == null or not _shop.has_stock(path):
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
