extends Node
## 《百炼》**现状固化网**（characterization / golden-master）。
##
## ── 它为什么存在（2026-09-19）───────────────────────────────────
## 这是「把 PlayerState 引力井拆成五个域」这轮重构的**安全网**，先织网、再拆。
## PlayerState 被全项目引用 269 次、一个人扛九个子系统 —— 动它极易引入
## **静默退化**（断言全绿、产品却坏了，见 engineering-notes「静默失败家族」）。
##
## 这张网钉的**不是「应该怎样」，而是「现在就是这样」**：把当前真实行为逐条固化。
## 重构的每一步都必须让这张网保持全绿 —— 门面转发做对了，这里一条都不该变。
## 域拆完、门面掏薄之后，这张网还在，就是这个游戏「成熟」的一部分资产。
##
## 覆盖五个域 + 存档往返：
##   经济域（元宝 / 买卖 / 商店）· 物品域（背包 / 装备栏 / 词条聚合 / 武器门）
##   锻造域（强化 / 打造 / 分解 / 制书）· 成长域（等级 / 经验 / flags）
##   战斗装配域（技能槽 / 消耗品次数 / 还魂丹）· 存档往返（save→load→save 全等）
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_charnet.tscn

const SaveGuard := preload("res://tests/save_guard.gd")

# ── 真实数据事实（对着仓库里真存在的资源，不是编的）──────────────
const HELM0 := "res://data/items/eq_u5934u76d4_0_u76aeu76d4.tres"   # 皮盔 tier0 无武器门 价30 hp5-7 def1-2
const HELM3 := "res://data/items/eq_u5934u76d4_3_u8d64u94dcu76d4.tres" # 赤铜盔 tier3 source=craft 价220
const SWORD0 := "res://data/items/wp_u5251_0_u94c1u5251.tres"       # 铁剑 tier0 sword
const BLADE0 := "res://data/items/wp_u5200_0_u94c1u5200.tres"       # 铁刀 tier0 blade

var _pass := 0
var _fail := 0
var _bak: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》现状固化网（重构安全网） ═══")
	_bak = SaveGuard.backup()

	_economy()
	_items()
	_forge()
	_growth()
	_loadout()
	_save_roundtrip()

	SaveGuard.restore(_bak)
	PlayerState.reset_for_new_game()

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ── 工具 ───────────────────────────────────────────────────────

func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-4s %s\n               %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-4s %s\n               %s" % [id, desc, detail])


## 每个域开头调：从干净状态起手，并把角色设成剑客（清缓存，武器门才认得准）
func _fresh(char_id: String = "swordsman") -> void:
	PlayerState.reset_for_new_game()
	PlayerState.character_id = char_id
	PlayerState._character = null
	PlayerState._character_loaded_for = ""


# ── 经济域（元宝 / 买卖 / 商店）─────────────────────────────────

func _economy() -> void:
	# 元宝加减：加正数涨、加 0/负数不动；花得起扣、花不起原样返回 false
	_fresh()
	PlayerState.add_gold(100)
	var after_add := PlayerState.gold
	PlayerState.add_gold(-50)
	PlayerState.add_gold(0)
	var add_noop: bool = PlayerState.gold == after_add
	var spent_ok := PlayerState.spend_gold(30)
	var after_spend := PlayerState.gold
	var spent_fail := PlayerState.spend_gold(99999)
	var spend_ok: bool = spent_ok and after_spend == after_add - 30 and not spent_fail \
		and PlayerState.gold == after_spend
	_check("E1", "元宝加减：加正数涨、加 0/负数不动；花得起扣、花不起 false 且不动",
		after_add == 100 and add_noop and spend_ok,
		"加后=%d 加0/负后=%d 花30后=%d 超额花=%s" % [
			after_add, PlayerState.gold, after_spend, str(spent_fail)])

	# 买：钱够 → 扣定价、新实例进背包；钱不够 → "" 且分文不动
	_fresh()
	var it := load(HELM0) as ItemData
	var price := it.gold_price
	PlayerState.gold = price + 5
	var bought_uid := PlayerState.buy_item(HELM0)
	var buy_ok: bool = not bought_uid.is_empty() and PlayerState.bag.has(bought_uid) \
		and PlayerState.gold == 5
	PlayerState.gold = price - 1
	var bag_n := PlayerState.bag.size()
	var poor_uid := PlayerState.buy_item(HELM0)
	var buy_poor_ok: bool = poor_uid.is_empty() and PlayerState.bag.size() == bag_n \
		and PlayerState.gold == price - 1
	_check("E2", "买装备：钱够扣定价+新实例进背包；钱不够返回空串、元宝与背包都不动",
		buy_ok and buy_poor_ok,
		"定价=%d 买后元宝=%d 进包=%s／钱不够时=%s 背包%d件不变" % [
			price, PlayerState.gold, str(buy_ok), str(poor_uid.is_empty()), bag_n])

	# 卖：背包里的按 折价率(0.5) 进账、移出背包；穿在身上的/不在包里的卖不了(返 0)
	_fresh()
	var sell_uid := PlayerState.add_item(HELM0)
	var gold0 := PlayerState.gold
	var gain := PlayerState.sell_item(sell_uid)
	var expect_gain := PlayerState.shop().sell_price(price)     # price × sell_ratio 向下取整
	var sell_ok: bool = gain == expect_gain and gain > 0 \
		and not PlayerState.bag.has(sell_uid) and PlayerState.gold == gold0 + gain
	var sell_again := PlayerState.sell_item(sell_uid)          # 已经卖掉了，再卖 = 0
	_check("E3", "卖装备：背包件按折价率(0.5)进账并移出背包；不在包里的卖不了(返0)",
		sell_ok and sell_again == 0,
		"定价=%d 卖得=%d(应%d) 再卖=%d" % [price, gain, expect_gain, sell_again])


# ── 物品域（背包 / 装备栏 / 词条聚合 / 武器门）───────────────────

func _items() -> void:
	# add_item：真装备 → uid 进背包；坏路径 → 空串
	_fresh()
	var uid := PlayerState.add_item(HELM0)
	var bad := PlayerState.add_item("res://data/progression.tres")   # 不是 ItemData
	var add_ok: bool = not uid.is_empty() and PlayerState.bag.has(uid) and bad.is_empty()
	_check("I1", "捡装备：真装备发新实例进背包；非装备资源返回空串",
		add_ok, "皮盔uid=%s 坏路径=%s 背包%d件" % [
			uid.split("#")[-1] if not uid.is_empty() else "空",
			"空" if bad.is_empty() else "非空", PlayerState.bag.size()])

	# 穿：背包→装备栏，空槽换下来是 ""；词条聚合的 hp 跟着涨（皮盔 hp 5-7）
	_fresh()
	var hp_before := int(PlayerState.bonus_total().get("hp", 0))
	var wear_uid := PlayerState.add_item(HELM0)
	var old := PlayerState.equip(wear_uid)
	var hp_after := int(PlayerState.bonus_total().get("hp", 0))
	var equip_ok: bool = old.is_empty() and PlayerState.equipped_uid(&"helm") == wear_uid \
		and not PlayerState.bag.has(wear_uid) and hp_after > hp_before
	# 卸：装备栏→背包，返回卸下的 uid，hp 聚合退回
	var taken := PlayerState.unequip(&"helm")
	var hp_back := int(PlayerState.bonus_total().get("hp", 0))
	var unequip_ok: bool = taken == wear_uid and PlayerState.bag.has(wear_uid) \
		and PlayerState.equipped_uid(&"helm").is_empty() and hp_back == hp_before
	_check("I2", "穿戴：背包↔装备栏对流，空槽换下=空串；词条聚合hp随穿脱涨落",
		equip_ok and unequip_ok,
		"穿后头盔槽=本件%s hp %d→%d／卸后回包=%s hp→%d" % [
			str(equip_ok), hp_before, hp_after, str(unequip_ok), hp_back])

	# 武器门：剑客能穿剑、穿不了刀（唯一的职业门；防具人人可穿已由 I2 覆盖）
	_fresh("swordsman")
	var can_sword := PlayerState.can_equip(load(SWORD0) as ItemData)
	var can_blade := PlayerState.can_equip(load(BLADE0) as ItemData)
	var blade_uid := PlayerState.add_item(BLADE0)
	var equip_blade := PlayerState.equip(blade_uid)          # 应失败：留在背包
	var gate_ok: bool = can_sword and not can_blade \
		and equip_blade.is_empty() and PlayerState.bag.has(blade_uid)
	_check("I3", "武器门：剑客能穿剑、拒穿刀（拒穿的留在背包可卖），是唯一的职业门",
		gate_ok, "can剑=%s can刀=%s 穿刀留包=%s" % [
			str(can_sword), str(can_blade), str(PlayerState.bag.has(blade_uid))])

	# 实例词条可复现：同一个 uid 每次 stat_of 完全一样（uid 哈希当种子，不进存档）
	_fresh()
	var det_uid := PlayerState.add_item(HELM0)
	var s1 := PlayerState.stat_of(det_uid)
	PlayerState._stat_cache.clear()                          # 清缓存也该 roll 出同一个值
	var s2 := PlayerState.stat_of(det_uid)
	var det_ok: bool = s1.get("hp") == s2.get("hp") and s1.get("def") == s2.get("def") \
		and int(s1.get("hp")) >= 5 and int(s1.get("hp")) <= 7      # 皮盔 hp 区间 5-7
	_check("I4", "实例词条可复现：同一 uid 清缓存后 stat_of 仍是同一个值，且落在区间内",
		det_ok, "两次 hp=%d/%d def=%d/%d（皮盔 hp∈[5,7]）" % [
			int(s1.get("hp")), int(s2.get("hp")), int(s1.get("def")), int(s2.get("def"))])


# ── 锻造域（强化 / 打造 / 分解 / 制书）──────────────────────────

func _forge() -> void:
	# 强化：精铁够 → 扣 forge_cost、等级+1；精铁不够 → false 且不动
	_fresh()
	var uid := PlayerState.add_item(HELM0)
	PlayerState.shards = 100000
	var cost0 := PlayerState.forge_cost(uid)                  # tier0 首级 = base_cost 4
	var lvl0 := PlayerState.forge_level(uid)
	var forged := PlayerState.forge_once(uid)
	var forge_ok: bool = forged and PlayerState.forge_level(uid) == lvl0 + 1 \
		and PlayerState.shards == 100000 - cost0 and cost0 == 4
	PlayerState.shards = 0
	var forge_poor := PlayerState.forge_once(uid)            # 没精铁
	var forge_poor_ok: bool = not forge_poor and PlayerState.forge_level(uid) == lvl0 + 1
	_check("F1", "强化：精铁够扣 forge_cost 且等级+1（tier0首级=4）；不够则 false 不动",
		forge_ok and forge_poor_ok,
		"首级花=%d 等级%d→%d 无铁再练=%s" % [
			cost0, lvl0, PlayerState.forge_level(uid), str(forge_poor)])

	# 强化封顶：tier0 封顶 3 级（forge.tres tier_max[0]=3），到顶后 forge_once 恒 false
	_fresh()
	var cuid := PlayerState.add_item(HELM0)
	PlayerState.shards = 100000
	var guard := 0
	while PlayerState.forge_once(cuid) and guard < 50:
		guard += 1
	var cap_ok: bool = PlayerState.forge_level(cuid) == PlayerState.forge_max(cuid) \
		and PlayerState.forge_max(cuid) == 3 and PlayerState.forge_is_maxed(cuid) \
		and not PlayerState.forge_once(cuid)
	_check("F2", "强化封顶：tier0 封顶 3 级，到顶后再练恒 false（品质档位绑定上限）",
		cap_ok, "练到 %d/%d 到顶=%s" % [
			PlayerState.forge_level(cuid), PlayerState.forge_max(cuid),
			str(PlayerState.forge_is_maxed(cuid))])

	# 分解：背包 tier0 → 2 精铁（disassemble.tres yields["0"]），件移出背包
	_fresh()
	var duid := PlayerState.add_item(HELM0)
	PlayerState.shards = 0
	var yld := PlayerState.disassemble(duid)
	var dis_ok: bool = int(yld.get("mat_refined_iron", 0)) == 2 \
		and PlayerState.shards == 2 and not PlayerState.bag.has(duid)
	var dis_again := PlayerState.disassemble(duid)           # 已拆掉，空字典
	_check("F3", "分解：背包 tier0 拆出 2 精铁并移出背包；重复拆返回空字典",
		dis_ok and dis_again.is_empty(),
		"产出精铁=%d shards=%d 再拆空=%s" % [
			int(yld.get("mat_refined_iron", 0)), PlayerState.shards, str(dis_again.is_empty())])

	# 制书 + 打造：买制书(750)→材料齐→craft 出新实例进背包；没书造不了
	_fresh()
	var no_book := PlayerState.craft(HELM3)                  # 还没买书
	PlayerState.gold = 1000
	var bought_bp := PlayerState.unlock_blueprint(HELM3)     # tier3 制书 750
	var bp_ok: bool = bought_bp and PlayerState.has_blueprint(HELM3) and PlayerState.gold == 250
	var dup_bp := PlayerState.unlock_blueprint(HELM3)        # 已有再买 = false 白花钱
	# tier3 配方：black_iron5 + refined_iron8 + sky_crystal3
	PlayerState.add_material(&"mat_black_iron", 5)
	PlayerState.add_material(&"mat_refined_iron", 8)         # 精铁转发 shards
	PlayerState.add_material(&"mat_sky_crystal", 3)
	var bag_n := PlayerState.bag.size()
	var crafted := PlayerState.craft(HELM3)
	var craft_ok: bool = no_book.is_empty() and not dup_bp and not crafted.is_empty() \
		and PlayerState.bag.has(crafted) and PlayerState.bag.size() == bag_n + 1
	_check("F4", "制书+打造：无书造不了；买书(750)扣钱、重复买 false；料齐 craft 出新实例进背包",
		bp_ok and craft_ok,
		"无书造=%s 买书后元宝=%d 重复买=%s 打造uid=%s" % [
			str(no_book.is_empty()), PlayerState.gold, str(dup_bp),
			"空" if crafted.is_empty() else "有"])


# ── 成长域（等级 / 经验 / flags）────────────────────────────────

func _growth() -> void:
	# 加经验：够数升级(可连升)；满级后加经验恒返回 0 且 exp 归 0
	_fresh()
	var need1 := PlayerState.exp_needed(1)
	var ups := PlayerState.add_exp(need1)                    # 正好升 1 级
	var lvl_ok: bool = ups == 1 and PlayerState.level == 2 and PlayerState.exp == 0
	# 一次给足跨多级的经验 → 连升
	var big := 0
	for l in range(2, 6):
		big += PlayerState.exp_needed(l)
	var multi := PlayerState.add_exp(big)
	var multi_ok: bool = multi == 4 and PlayerState.level == 6
	# 满级：拉到 level_cap，再加经验 = 0、exp 不涨
	PlayerState.level = PlayerState.level_cap
	PlayerState.exp = 0
	var at_max := PlayerState.add_exp(999999)
	var max_ok: bool = PlayerState.is_max_level() and at_max == 0 and PlayerState.exp == 0
	_check("G1", "经验：够数升级(可连升)；满级后加经验恒 0、经验条不再涨",
		lvl_ok and multi_ok and max_ok,
		"升1级=%s 连升4级到%d级=%s 满级加经验=%d" % [
			str(lvl_ok), PlayerState.level, str(multi_ok), at_max])

	# flags：set/has；空 flag 不记也查不到
	_fresh()
	PlayerState.set_flag(&"met_smith")
	PlayerState.set_flag(&"")                                # 空的不记
	var flag_ok: bool = PlayerState.has_flag(&"met_smith") \
		and not PlayerState.has_flag(&"never_set") and not PlayerState.has_flag(&"")
	_check("G2", "进度标记：set_flag/has_flag 成对；空 flag 不记也查不到",
		flag_ok, "met_smith=%s 未设的=%s" % [
			str(PlayerState.has_flag(&"met_smith")), str(PlayerState.has_flag(&"never_set"))])


# ── 战斗装配域（技能槽 / 消耗品次数 / 还魂丹）──────────────────

func _loadout() -> void:
	# 技能槽：装进槽；同一技能装到别的槽 = 从原槽挪走(不重复占两格)；清空
	_fresh()
	PlayerState.set_skill_slot(0, "res://data/skills/whirl.tres")
	PlayerState.set_skill_slot(1, "res://data/skills/dash.tres")
	PlayerState.set_skill_slot(2, "res://data/skills/whirl.tres")   # whirl 挪到槽2，槽0该空
	var slots := PlayerState.skill_paths()
	var no_dup: bool = str(slots[0]).is_empty() and str(slots[2]) == "res://data/skills/whirl.tres" \
		and str(slots[1]) == "res://data/skills/dash.tres"
	PlayerState.clear_skill_slot(1)
	var cleared: bool = str(PlayerState.skill_paths()[1]).is_empty()
	_check("L1", "技能槽：装入生效；同一技能改槽=从原槽挪走(不占两格)；清空生效",
		no_dup and cleared,
		"槽[0,1,2]=[%s,%s,%s] 清槽1后=%s" % [
			str(slots[0]).get_file(), str(slots[1]).get_file(),
			str(slots[2]).get_file(), str(PlayerState.skill_paths()[1]).get_file()])

	# 消耗品次数：加/用；用光返回 false；买一份符扣钱加 3 次
	_fresh()
	PlayerState.add_potion_charges(PlayerState.POTION_HP, 2)
	var used1 := PlayerState.use_potion(PlayerState.POTION_HP)
	var used2 := PlayerState.use_potion(PlayerState.POTION_HP)
	var used3 := PlayerState.use_potion(PlayerState.POTION_HP)      # 第3次没得用
	var charge_ok: bool = used1 and used2 and not used3 \
		and PlayerState.potion_charges(PlayerState.POTION_HP) == 0
	PlayerState.gold = 1000
	var g0 := PlayerState.gold
	var buy_p := PlayerState.buy_potion(PlayerState.POTION_HP)
	var buy_ok: bool = buy_p and PlayerState.potion_charges(PlayerState.POTION_HP) == 3 \
		and PlayerState.gold == g0 - PlayerState.potion_price(PlayerState.POTION_HP)
	_check("L2", "消耗品次数：加/用成对，用光返回 false；买一份符扣钱+3次",
		charge_ok and buy_ok,
		"用3次=%s/%s/%s 买后次数=%d 元宝%d→%d" % [
			str(used1), str(used2), str(used3),
			PlayerState.potion_charges(PlayerState.POTION_HP), g0, PlayerState.gold])

	# 还魂丹：进图补给白送2枚(仅首次)；商店限购每图5枚
	_fresh()
	var granted := PlayerState.grant_map_supply(&"map_cuihuo")
	var granted2 := PlayerState.grant_map_supply(&"map_cuihuo")     # 第二次不发
	var supply_ok: bool = granted and not granted2 and PlayerState.revive_tokens == 2
	PlayerState.gold = 100000
	var buys := 0
	for _i in 8:
		if PlayerState.buy_revive_token(&"map_cuihuo"):
			buys += 1
	var limit_ok: bool = buys == 5 and PlayerState.revive_bought_in(&"map_cuihuo") == 5
	# 用一枚：数量-1；用光返回 false
	var use_ok := PlayerState.use_revive_token()
	_check("L3", "还魂丹：进图补给白送2枚(仅首次)；商店每图限购5枚；用一枚数量-1",
		supply_ok and limit_ok and use_ok,
		"首送=%d枚 限购买到%d次(应5) 用一枚=%s" % [
			2 if granted else 0, buys, str(use_ok)])


# ── 存档往返（save→load→save 全等）─────────────────────────────

func _save_roundtrip() -> void:
	# 把每个域都塞进非默认值，再走一遍 save→load→save，两份 dict 必须逐字节相等。
	# 这是整轮重构最关键的一条：门面拆开后只要序列化改了形状，这里立刻红。
	_fresh("archer")
	PlayerState.shards = 77
	PlayerState.gold = 888
	PlayerState.level = 12
	PlayerState.exp = 34
	var u := PlayerState.add_item(HELM0)
	PlayerState.equip(u)
	PlayerState.add_item(SWORD0)
	PlayerState.shards = 100000
	PlayerState.forge_once(PlayerState.equipped_uid(&"helm"))
	PlayerState.add_material(&"mat_black_iron", 9)
	PlayerState.blueprints.append(HELM3)
	PlayerState.revive_tokens = 3
	PlayerState.revive_bought["map_cuihuo"] = 2
	PlayerState.add_potion_charges(PlayerState.POTION_MP, 4)
	PlayerState.set_flag(&"boss1_down")
	PlayerState.set_skill_slot(0, "res://data/skills/whirl.tres")

	var d1 := PlayerState.save_to()
	PlayerState.load_from(d1)
	var d2 := PlayerState.save_to()
	# Godot 4 的 Dictionary/Array == 是深比较（递归按值）—— 直接比整份
	var equal: bool = d1 == d2
	_check("S1", "存档往返：塞满五域后 save→load→save，两份存档 dict 深度全等",
		equal, "字段数=%d 全等=%s" % [d1.size(), str(equal)])

	# 逐字段点名（== 全绿时这条冗余，但一旦某字段掉队，它指出是哪个）
	var fields := ["shards", "gold", "character_id", "level", "exp",
		"equipped", "bag", "forge", "next_uid", "materials", "blueprints",
		"revive_tokens", "revive_bought", "potions", "flags", "skill_slots"]
	var missing: Array = []
	for f in fields:
		if not d2.has(f):
			missing.append(f)
	var char_kept: bool = str(d2.get("character_id", "")) == "archer"
	var lvl_kept: bool = int(d2.get("level", 0)) == 12
	var flag_kept: bool = (d2.get("flags", {}) as Dictionary).has("boss1_down")
	var fields_ok: bool = missing.is_empty() and char_kept and lvl_kept and flag_kept
	_check("S2", "存档字段齐全：16 个持久化字段都在，角色/等级/flags 原值读回",
		fields_ok, "缺失字段=%s 角色=%s 等级=%d flag在=%s" % [
			str(missing) if not missing.is_empty() else "无",
			str(d2.get("character_id")), int(d2.get("level", 0)), str(flag_kept)])
