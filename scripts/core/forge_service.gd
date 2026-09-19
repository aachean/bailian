class_name ForgeService
extends RefCounted
## 锻造域服务：强化 + 打造 + 分解 + 制书。
##
## 见 [ADR-0027](../../docs/adr/0027-playerstate-decomposition.md)：PlayerState 拆解的第二个域。
## 逻辑住这里，PlayerState 退成薄门面转发，对外接口一字不变。
##
## ── 过渡期分工（门面阶段）─────────────────────────────────────
## **数据仍住 PlayerState 容器**（进存档、且被 stage.gd / player.gd 直接读写）：
##   forge（uid→强化等级）· materials（稀有材料）· blueprints（制书）· shards（精铁）。
## **本域自己拥有的是三份只读数据资源**：ForgeData / CraftingData / DisassembleData（懒加载）。
## 服务持 PlayerState 引用 `_s`，读写它的数据字段、借它的信号。
##
## ── 跨域调用（都走对方公开方法，这就是缝）──────────────────────
##   物品域：item_of / add_item / _remove_from_bag / _recalc_bonus / equipped_uid / bag / equipment_changed
##   经济域：spend_gold（买制书要花元宝）
## 物品域 / 经济域抽出后，把 `_s.xxx` 改指到对应服务即可。

## 强化的唯一真相（品质上限 / 成本递增 / 收益递减）
const FORGE_PATH := "res://data/forge.tres"
## 打造/分解的经济数据
const CRAFTING_PATH := "res://data/economy/crafting.tres"
const DISASSEMBLE_PATH := "res://data/economy/disassemble.tres"

var _s: Object

## 只读数据资源，懒加载（测试与开局未必用到）
var _forge: ForgeData = null
var _crafting: CraftingData = null
var _disassemble: DisassembleData = null


func _init(state: Object) -> void:
	_s = state


func _forge_data() -> ForgeData:
	if _forge == null:
		_forge = load(FORGE_PATH) as ForgeData
	return _forge


func crafting() -> CraftingData:
	if _crafting == null:
		_crafting = load(CRAFTING_PATH) as CraftingData
	return _crafting


func disassemble_table() -> DisassembleData:
	if _disassemble == null:
		_disassemble = load(DISASSEMBLE_PATH) as DisassembleData
	return _disassemble


# ── 强化 ───────────────────────────────────────────────────────

## 这件装备练到几级了（没练过 = 0）
func forge_level(uid: String) -> int:
	return int(_s.forge.get(uid, 0))


## 这件装备能练到几级（按品质）。不是装备资源就返回 0
func forge_max(uid: String) -> int:
	var it: ItemData = _s.item_of(uid)
	return 0 if it == null else _forge_data().max_for_tier(int(it.tier))


## 从当前等级再练一级要花多少精铁
func forge_cost(uid: String) -> int:
	return _forge_data().cost_at_level(forge_level(uid))


## 这件装备的强化贡献的攻击加成（已含收益递减）
func forge_atk(uid: String) -> float:
	return _forge_data().atk_bonus_at(forge_level(uid))


## 练到 level 级时总共给多少攻击加成（不看具体哪件）
func forge_atk_at(level: int) -> float:
	return _forge_data().atk_bonus_at(level)


func forge_is_maxed(uid: String) -> bool:
	return forge_level(uid) >= forge_max(uid)


## 现在能不能强化这一件（没到顶 + 精铁够）
func can_forge(uid: String) -> bool:
	return not uid.is_empty() and not forge_is_maxed(uid) and _s.shards >= forge_cost(uid)


## 强化一级。花掉精铁、写进 forge 表、重算属性并发信号。
## 返回 true = 成功；false = 到顶了 / 精铁不够 / 不是装备
func forge_once(uid: String) -> bool:
	if not can_forge(uid):
		return false
	_s.shards -= forge_cost(uid)
	_s.forge[uid] = forge_level(uid) + 1
	_s._recalc_bonus()                # ← 跨域：强化改变攻击倍率，物品域重算
	_s.equipment_changed.emit()
	return true


## 所有能强化的装备（已装备的在前，背包在后），元素是 uid。铁匠铺列表用它 —— 顺序稳定
func forgeable_uids() -> Array:
	var out: Array = []
	for s in ItemData.SLOT_IDS:
		var uid: String = _s.equipped_uid(s)
		if not uid.is_empty():
			out.append(uid)
	out.append_array(_s.bag)
	return out


# ── 材料 ───────────────────────────────────────────────────────

## 某种材料的持有量。精铁转发 shards，其余查 materials
func material_count(id: StringName) -> int:
	return _s.shards if id == PlayerState.MAT_REFINED_IRON else int(_s.materials.get(String(id), 0))


## 加材料。扣材料一律走 pay_materials（原子检查），这里只加
func add_material(id: StringName, n: int) -> void:
	if n <= 0:
		return
	if id == PlayerState.MAT_REFINED_IRON:
		_s.shards += n
	else:
		var k := String(id)
		_s.materials[k] = int(_s.materials.get(k, 0)) + n


## 原子付料：**先验够不够、再一次扣清**。返回 false 时一个子都不动。精铁那份转给 shards
func pay_materials(cost: Dictionary) -> bool:
	for id in cost:
		if material_count(StringName(String(id))) < int(cost[id]):
			return false
	for id in cost:
		var k := String(id)
		var n := int(cost[id])
		if id == String(PlayerState.MAT_REFINED_IRON):
			_s.shards -= n
		else:
			_s.materials[k] = int(_s.materials.get(k, 0)) - n
	return true


## 干跑版：只验够不够，一分不动（界面着色/提示用）
func pay_materials_dry_run(cost: Dictionary) -> bool:
	for id in cost:
		if material_count(StringName(String(id))) < int(cost[id]):
			return false
	return true


# ── 分解 / 打造 / 制书 ──────────────────────────────────────────

## 分解一件**背包里的**装备 → 材料（按档）。返回产量字典（空 = 拆不了）。
## 与「出售」互不兑换（原则 5.1）：卖走元宝、拆走材料
func disassemble(uid: String) -> Dictionary:
	if not _s.bag.has(uid):
		return {}
	var it: ItemData = _s.item_of(uid)
	if it == null:
		return {}
	var yld: Dictionary = disassemble_table().yield_for(int(it.tier))
	if yld.is_empty():
		return {}
	_s._remove_from_bag(uid)          # ← 跨域：出背包是物品域的事
	for id in yld:
		add_material(StringName(String(id)), int(yld[id]))
	_s.equipment_changed.emit()
	return yld


## 打造：材料 + **这一件**的制书 → 一件**全新实例**进背包。返回新 uid（空串 = 造不了）
func craft(path: String) -> String:
	var it := load(path) as ItemData
	if it == null:
		return ""
	if not has_blueprint(path):
		return ""
	if not pay_materials(crafting().cost_for(int(it.tier))):
		return ""
	return _s.add_item(path)          # ← 跨域：进背包是物品域的事


## 买制书（逐件）。价格按**装备的档**走。已有再买 = false（不重复付费）
func unlock_blueprint(path: String) -> bool:
	if has_blueprint(path):
		return false
	var it := load(path) as ItemData
	if it == null:
		return false
	var price := int(crafting().blueprint_price.get(str(int(it.tier)), 0))
	if price <= 0 or not _s.spend_gold(price):    # ← 跨域：花元宝是经济域的事
		return false
	_s.blueprints.append(path)
	return true


func has_blueprint(path: String) -> bool:
	return _s.blueprints.has(path)
