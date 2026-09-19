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

@onready var progression: ProgressionData = load(PROGRESSION_PATH) as ProgressionData

## 经济域服务（元宝 / 买卖 / 商店货架）。逻辑住 EconomyService，本类只转发（门面）。
## 见 ADR-0027：PlayerState 拆解的第一个域。懒加载
var _economy_svc: EconomyService = null

func economy() -> EconomyService:
	if _economy_svc == null:
		_economy_svc = EconomyService.new(self)
	return _economy_svc

## 等级上限（给界面用，省得到处 PlayerState.progression.level_cap）
@onready var level_cap: int = progression.level_cap

## 成长域服务（等级 / 经验 / flags）。懒加载
var _growth_svc: GrowthService = null

func growth() -> GrowthService:
	if _growth_svc == null:
		_growth_svc = GrowthService.new(self)
	return _growth_svc

## 战斗装配域服务（技能槽 / 消耗品次数 / 还魂丹）。懒加载
var _loadout_svc: CombatLoadoutService = null

func loadout() -> CombatLoadoutService:
	if _loadout_svc == null:
		_loadout_svc = CombatLoadoutService.new(self)
	return _loadout_svc


## 升到下一级需要的经验。**满级返回 0**。→ 成长域
func exp_needed(level: int) -> int:
	return growth().exp_needed(level)


func is_max_level() -> bool:
	return growth().is_max_level()


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

## 当前角色定义的缓存（物品域 ItemsService 用）。**留在容器上**：
## test_m16 / test_charnet 直接写 `PlayerState._character = null` 强制重载，
## 缓存必须在它们够得着的地方（服务通过 `_s._character` 读写同一份）
var _character: CharacterData = null
var _character_loaded_for := ""


func reset_for_new_game() -> void:
	shards = 0
	gold = 0
	materials.clear()
	blueprints.clear()
	revive_tokens = 0
	revive_bought.clear()
	potions.clear()
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
	# 旧档没有这字段 → 空字典 = 没买过预载（纯增量，不作废进度，见 SaveManager VERSION 13）
	potions = (d.get("potions", {}) as Dictionary).duplicate()
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
		"potions": potions.duplicate(),
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


# ── 物品域（逻辑 → ItemsService，ADR-0027；下面都是薄门面转发）────────
# equipped / bag / forge / next_uid / _bonus / _stat_cache 数据字段仍住本容器
# （进存档、被 hud/forge_panel/stage 直接读写）

## 物品域服务（装备实例 / 背包 / 装备栏 / 词条聚合 / 武器门）。懒加载
var _items_svc: ItemsService = null

func items() -> ItemsService:
	if _items_svc == null:
		_items_svc = ItemsService.new(self)
	return _items_svc


## 把 next_uid 推到最大序号 + 1 之后（读档兜底）。→ 物品域
func _ensure_uid_counter() -> void:
	items().ensure_uid_counter()


func _empty_slots() -> Array:
	var out: Array = []
	for _i in SKILL_SLOT_COUNT:
		out.append("")
	return out


# ── 装备实例 id（→ 物品域）────────────────────────────────────
func make_uid(path: String) -> String:
	return items().make_uid(path)

func path_of(uid: String) -> String:
	return items().path_of(uid)

func item_of(uid: String) -> ItemData:
	return items().item_of(uid)


# ── 强化（逻辑 → ForgeService，ADR-0027；下面都是薄门面转发）──────
# forge / shards / materials / blueprints 数据字段仍住本容器（进存档、被 stage.gd 直接读写）

## 锻造域服务（强化 / 打造 / 分解 / 制书）。懒加载
var _forge_svc: ForgeService = null

func forge_svc() -> ForgeService:
	if _forge_svc == null:
		_forge_svc = ForgeService.new(self)
	return _forge_svc


func forge_level(uid: String) -> int:
	return forge_svc().forge_level(uid)

func forge_max(uid: String) -> int:
	return forge_svc().forge_max(uid)

func forge_cost(uid: String) -> int:
	return forge_svc().forge_cost(uid)

func forge_atk(uid: String) -> float:
	return forge_svc().forge_atk(uid)

func forge_atk_at(level: int) -> float:
	return forge_svc().forge_atk_at(level)

func forge_is_maxed(uid: String) -> bool:
	return forge_svc().forge_is_maxed(uid)

func can_forge(uid: String) -> bool:
	return forge_svc().can_forge(uid)

func forge_once(uid: String) -> bool:
	return forge_svc().forge_once(uid)

func forgeable_uids() -> Array:
	return forge_svc().forgeable_uids()


## 摆回实例计数器（读档用）。**uid 管理是物品域的事，留在容器上**（Phase 3 物品域会收）
func set_uid_counter(n: int) -> void:
	next_uid = maxi(n, 1)
	_ensure_uid_counter()


# ── 元宝（商店经济，计划 §3.7）────────────────────────────────
# 两条管道进、一条管道出：打怪掉小额 + 出售装备 → 元宝 → 商店买。
# 与精铁（shards）刻意**互不兑换** —— 两笔钱让玩家每次花钱都要判断该用哪个；
# 能互换就等于只有一种。精铁只进强化，元宝只进商店。

## 商店数据（库存 / 折价率）。→ 经济域
func shop() -> ShopData:
	return economy().shop()

## 元宝进账。→ 经济域
func add_gold(n: int) -> void:
	economy().add_gold(n)


## 花 n 个元宝，花不起返回 false（不静默）。→ 经济域
func spend_gold(n: int) -> bool:
	return economy().spend_gold(n)


## 从商店买一件，成功返回新实例 uid、失败返回空串。→ 经济域
func buy_item(path: String) -> String:
	return economy().buy_item(path)


## 出售背包里的一件装备换元宝，返回进账（0 = 卖不了）。→ 经济域
func sell_item(uid: String) -> int:
	return economy().sell_item(uid)


# ── 材料与打造（逻辑 → ForgeService，ADR-0027；下面都是薄门面转发）────

## 材料的元 id。**精铁就是 shards**（强化主料的唯一真相，不搬家 ——
## 材料字典里没有它，靠 MAT_REFINED_IRON 这个 id 转发到 shards）。
## **const 留在容器上**：外部 hud.gd 直接读 `PlayerState.MAT_REFINED_IRON`（const 不能转发）
const MAT_REFINED_IRON := &"mat_refined_iron"


## 四种稀有材料的持有量：id → 数量。精铁不在里面（见 MAT_REFINED_IRON）。
## **数据字段留容器**（进存档、被 ForgeService 与 stage.gd 读写）
var materials: Dictionary = {}

## 已到手的**逐件制书**（装备资源路径数组）。制书是逐件的（不是档位），
## 存装备路径本身当唯一键，打造页 / 商店 / 掉落引用同一串。**数据字段留容器**
var blueprints: Array = []


func crafting() -> CraftingData:
	return forge_svc().crafting()

func disassemble_table() -> DisassembleData:
	return forge_svc().disassemble_table()

func material_count(id: StringName) -> int:
	return forge_svc().material_count(id)

func add_material(id: StringName, n: int) -> void:
	forge_svc().add_material(id, n)

func pay_materials(cost: Dictionary) -> bool:
	return forge_svc().pay_materials(cost)

func pay_materials_dry_run(cost: Dictionary) -> bool:
	return forge_svc().pay_materials_dry_run(cost)

func disassemble(uid: String) -> Dictionary:
	return forge_svc().disassemble(uid)

func craft(path: String) -> String:
	return forge_svc().craft(path)

func unlock_blueprint(path: String) -> bool:
	return forge_svc().unlock_blueprint(path)

func has_blueprint(path: String) -> bool:
	return forge_svc().has_blueprint(path)


# ── 商店货架（刷新逻辑 → EconomyService，ADR-0027）───────────────
#
# **刷新逻辑住 EconomyService**（_load_shop_state / _roll_* / SHOP_STATE_PATH 都搬过去了）；
# 下面这三个字段留在容器上，因为 shop_panel.gd 直接读写它们（门面过渡期）。
#
# ── 刷新状态住**全局文件**，不进存档槽（2026-09-18 神圈注）────────
# 「每 4 现实小时」意味着时钟属于**现实世界**，不属于某个存档：
# 放进存档槽的话，退出时机不对（商店状态没赶上下一次保存）重进就会
# 回到 4:00:00。user://shop_refresh.cfg 是唯一真相：所有存档槽共享
# 同一家店的同一批货、同一个钟 —— 商店是「世界的店」，不随读档回滚。

## 当前货架（随机抽的装备路径数组）。**不是 ShopData.stock** ——
## stock 是「这家店卖什么档次」的底线清单，offers 是这一批实际摆出来的货。
## **字段留在容器上**：shop_panel.gd 直接 `.erase()`、测试直接赋值（门面过渡期，Phase 6 再掏薄）
var shop_offers: Array = []

## 本期的**随机制书货架**（装备路径数组）。每期独立 roll，**本期限购 1 本**（买走即撤）
var shop_bp_offers: Array = []

## 上次刷新的时刻（Unix 秒，现实时间）
var shop_refreshed_at: float = 0.0


## 货架状态写回全局文件（抽新货 / 买走撤下时调）。→ 经济域
func save_shop_state() -> void:
	economy().save_shop_state()


## 货架过期了就重抽（进商店面板前调）。→ 经济域
func ensure_shop_fresh() -> void:
	economy().ensure_shop_fresh()


## 距下次刷新还剩多少秒（面板倒计时用）。→ 经济域
func shop_refresh_in() -> float:
	return economy().shop_refresh_in()


# ── 还魂丹（原则 5.7：死亡罚效率不罚进度，丹是安全网不是免死金牌）──

## 还魂丹持有数。用一枚 = 原地满血复活，省掉「重开本」这一趟
var revive_tokens: int = 0

## 每张地图已买的还魂丹数（map_id → n）。**限购按图记** ——
## 设计 5.7：商店 200 元宝/个、每章限购 5；不限购它就成了「死了花钱续命」的常规操作
var revive_bought: Dictionary = {}


## 还魂丹（逻辑 → CombatLoadoutService，ADR-0027；下面都是薄门面转发）
func use_revive_token() -> bool:
	return loadout().use_revive_token()

func grant_map_supply(map_id: StringName) -> bool:
	return loadout().grant_map_supply(map_id)

func buy_revive_token(map_id: StringName) -> bool:
	return loadout().buy_revive_token(map_id)

func revive_bought_in(map_id: StringName) -> int:
	return loadout().revive_bought_in(map_id)


## 还魂丹定价（200 元宝）。放这儿是因为唯一动它的两个界面（商店标价 / 买）
## 都从这取 —— 别在面板里写第二份 200
const REVIVE_PRICE := 200


# ── 预载消耗品（原则 5.6 的第二条：买「次数」、按 6 / 7 主动用）──────
#
# 5.6 原本只有「掉在地上走近直接生效」。2026-09-18 加了第二条，**两条并存**：
# 免费掉落是保底，买的那一份是长 Boss 战里**可控**的回血手段 ——
# 那段时间没有小怪可杀，也就没有掉落可捡。
# 见 docs/adr/0022 §2.3、docs/design-conventions「反馈原则 · 消耗品」。

## 剩余**次数**（不是「几份」—— 一份符 = 3 次）。键是 String(POTION_HP / POTION_MP)。
##
## 用字典而不是两个 int：与 flags / materials 同一条路，「加第三种符」是零成本的。
## 不进 _bonus / 不发 equipment_changed —— 次数不是成长属性，HUD 每次 refresh
## 都当场重读（与元宝同一条态度），没有需要失效的缓存
var potions: Dictionary = {}

const POTION_HP := &"hp"
const POTION_MP := &"mp"
## 技能栏后两格的顺序就是它：第 6 格 = hp、第 7 格 = mp。
## **UI 与断言都从这取**，别各写一份顺序
const POTION_KINDS: Array[StringName] = [&"hp", &"mp"]

## 一份符给几次。补给包同理，血蓝各 5 次
const POTION_CHARGES := 3
const SUPPLY_CHARGES := 5

## 定价（元宝）。**唯一出处** —— 商店标价与购买都从这取，别在面板里写第二份
const POTION_HP_PRICE := 60
const POTION_MP_PRICE := 50
const SUPPLY_PRICE := 160


## 消耗品次数（逻辑 → CombatLoadoutService，ADR-0027；下面都是薄门面转发）
func potion_charges(kind: StringName) -> int:
	return loadout().potion_charges(kind)

func potion_price(kind: StringName) -> int:
	return loadout().potion_price(kind)

func add_potion_charges(kind: StringName, n: int) -> void:
	loadout().add_potion_charges(kind, n)

func use_potion(kind: StringName) -> bool:
	return loadout().use_potion(kind)

func buy_potion(kind: StringName) -> bool:
	return loadout().buy_potion(kind)

func buy_supply() -> bool:
	return loadout().buy_supply()


# ── 主线进度标记 ───────────────────────────────────────────────

## 主线进度标记。→ 成长域
func set_flag(name: StringName) -> void:
	growth().set_flag(name)

func has_flag(name: StringName) -> bool:
	return growth().has_flag(name)


# ── 技能栏（逻辑 → CombatLoadoutService，ADR-0027；下面都是薄门面转发）──

func skill_at(i: int) -> SkillData:
	return loadout().skill_at(i)

func skill_paths() -> Array:
	return loadout().skill_paths()

func carries(path: String) -> bool:
	return loadout().carries(path)

func set_skill_slot(i: int, path: String) -> void:
	loadout().set_skill_slot(i, path)

func clear_skill_slot(i: int) -> void:
	loadout().clear_skill_slot(i)

func clear_skill_slot_by_path(path: String) -> void:
	loadout().clear_skill_slot_by_path(path)

func auto_fill_slots(available: Array) -> bool:
	return loadout().auto_fill_slots(available)


# ── 装备栏操作（逻辑 → ItemsService，ADR-0027；下面都是薄门面转发）────

func character_def() -> CharacterData:
	return items().character_def()

func can_equip(item: ItemData) -> bool:
	return items().can_equip(item)

func equipped_uid(slot: StringName) -> String:
	return items().equipped_uid(slot)

func item_at(slot: StringName) -> ItemData:
	return items().item_at(slot)

func equipped_list() -> Array:
	return items().equipped_list()

func add_item(path: String) -> String:
	return items().add_item(path)

func equip(uid: String) -> String:
	return items().equip(uid)

func unequip(slot: StringName) -> String:
	return items().unequip(slot)

## 背包里去掉某件（穿上时调）。跨域服务（经济/锻造）也调它 → 物品域
func _remove_from_bag(uid: String) -> void:
	items()._remove_from_bag(uid)

func bonus_total() -> Dictionary:
	return items().bonus_total()

func stat_of(uid: String) -> Dictionary:
	return items().stat_of(uid)

## 直接摆入装备栏、背包与强化表（读档用）。→ 物品域
func set_equipment(e: Dictionary, b: Array, f: Dictionary = {}) -> void:
	items().set_equipment(e, b, f)

## 词条重算。跨域服务（锻造 forge_once）也调它 → 物品域
func _recalc_bonus() -> void:
	items()._recalc_bonus()


## 比例类属性的硬上限（设计原则 4.2）。**所有比例属性都必须从这儿过一道** ——
## 将来加暴击 / 闪避 / 穿透时，把上限加进这个 match，别在各自的计算里各写一份。
## 未知的比例属性一律夹到 [0, 1]：宁可保守，也不要一个没设上限的百分比流出去。
## **暂留容器上**：无人外部调用、域归属未定（既非纯物品也非纯战斗），Phase 6 再议
##
## ⚠️ 2026-09-18（v2）：**防御已经不是比例属性了**。它现在是平铺点数，
## 上限改由 `Health.armor_reduction()` 的护甲曲线自己卡（def=150 → 0.6）。
func clamp_ratio(key: StringName, value: float) -> float:
	match key:
		_:
			return clampf(value, 0.0, 1.0)


# ── 升级 ───────────────────────────────────────────────────────

## 加经验，够数就升级（可连升）。返回升了几级。→ 成长域
func add_exp(amount: int) -> int:
	return growth().add_exp(amount)
