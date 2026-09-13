extends Node
## 玩家成长数据（autoload）：等级 / 经验 / 蓝量上限 / 装备 —— 「属于玩家」的东西。
##
## 与 PlayerState 合并过考虑——但它已经叫 PlayerState，等级经验就住在同一家：
## 本文件实际承担 shards / upgrade / level / exp / 装备栏 / 背包 六样跨场景数据。
## 升级逻辑也在这（纯数据 + 信号），玩家节点只负责听信号改血条和蓝上限。
##
## ── 装备为什么也存在这里 ──────────────────────────────────────
## 和碎片同一个理由：切场景会重建玩家节点，挂在节点上的东西会丢（实测丢过碎片）。
## 「属于玩家而不是属于关卡」的数据一律放 autoload，这是第三次因此改架构。
##
## ── 装备用什么当键 ───────────────────────────────────────────
## 存的是【资源路径】（"res://data/items/iron_sword.tres"）而不是 id。
## 理由：读档时要拿回 ItemData 本身，路径可以一步 load()；用 id 还得再维护一张
## id→路径的表，而那张表迟早会和目录里的文件对不上。代价是重命名资源文件会让
## 老存档失效 —— 开发期可接受，写在这里备案。

## 升级时发。玩家听了加血上限 / 蓝上限并回满
signal level_up(new_level: int)

## 经验变化时发（包括没升级的零散经验）—— 场景里的玩家节点听它同步，
## 否则 HUD 上的经验条只会在切场景后「突然」跳起来（实测反馈）
signal exp_changed(new_exp: int)

## 装备栏或背包变化时发（穿戴 / 卸下 / 捡到新装备）。
## 两件事共用一个信号：界面拿到它一律全量重刷，不做增量。
## 场景里的玩家节点也听它 —— 换装要立刻改变攻击倍率 / 生命上限 / 减伤。
signal equipment_changed

## 槽位 id，顺序与 ItemData.Slot 枚举一致
const SLOT_IDS: Array[StringName] = [&"weapon", &"helm", &"armor", &"trinket"]

## 升到下一级需要的经验：线性增长，原型期手感友好
func exp_needed(level: int) -> int:
	return 20 + (level - 1) * 15


var shards: int = 0
var upgrade_level: int = 0

var level: int = 1
var exp: int = 0

## 装备栏：槽位 id → 装备资源路径。没穿的槽不在字典里
var equipped: Dictionary = {}
## 背包：捡到但没穿的装备资源路径，按捡到的先后排
var bag: Array = []

## 主线进度标记（对话有没有发生过、奖励有没有给过）。键是字符串 flag 名，值都是 true。
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

## 词条聚合缓存。装备一变就重算，免得 HUD 每帧去 load 一遍所有装备资源
var _bonus: Dictionary = {"atk": 0.0, "hp": 0, "def": 0.0}


func reset_for_new_game() -> void:
	shards = 0
	upgrade_level = 0
	level = 1
	exp = 0
	equipped.clear()
	bag.clear()
	flags.clear()
	skill_slots = _empty_slots()
	_recalc_bonus()
	equipment_changed.emit()
	skills_changed.emit()


func load_from(d: Dictionary) -> void:
	shards = int(d.get("shards", shards))
	upgrade_level = int(d.get("upgrade", upgrade_level))
	level = int(d.get("level", level))
	exp = int(d.get("exp", exp))
	equipped = (d.get("equipped", {}) as Dictionary).duplicate()
	bag = (d.get("bag", []) as Array).duplicate()
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
		"upgrade": upgrade_level,
		"level": level,
		"exp": exp,
		"equipped": equipped.duplicate(),
		"bag": bag.duplicate(),
		"flags": flags.duplicate(),
		"skill_slots": skill_slots.duplicate(),
	}


func _empty_slots() -> Array:
	var out: Array = []
	for _i in SKILL_SLOT_COUNT:
		out.append("")
	return out


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

## 取某个槽位穿着的装备。空槽返回 null
func item_at(slot: StringName) -> ItemData:
	var p := str(equipped.get(String(slot), ""))
	return load(p) as ItemData if not p.is_empty() else null


## 按槽位顺序取「当前穿着的全部装备」，空槽是 null（界面按顺序画四行）
func equipped_list() -> Array:
	var out: Array = []
	for s in SLOT_IDS:
		out.append(item_at(s))
	return out


## 捡到一件装备：进背包。返回 false = 这不是一件装备（路径坏 / 不是 ItemData）
func add_item(path: String) -> bool:
	if not (load(path) is ItemData):
		push_warning("PlayerState: 不是装备资源: %s" % path)
		return false
	bag.append(path)
	equipment_changed.emit()
	return true


## 穿上一件背包里的装备。返回被替换下来的那件（"" = 原来空槽）。
## 换下来的自动回背包 —— 玩家不该因为换装而丢东西
func equip(path: String) -> String:
	var item := load(path) as ItemData
	if item == null:
		return ""
	var idx := bag.find(path)
	if idx >= 0:
		bag.remove_at(idx)
	var slot := String(item.slot_id())
	var old := str(equipped.get(slot, ""))
	if not old.is_empty():
		bag.append(old)          # 换下来的回背包
	equipped[slot] = path
	_recalc_bonus()
	equipment_changed.emit()
	return old


## 卸下某个槽位，装备回背包。返回卸下的路径（"" = 本来就空着）
func unequip(slot: StringName) -> String:
	var key := String(slot)
	var path := str(equipped.get(key, ""))
	if path.is_empty():
		return ""
	equipped.erase(key)
	bag.append(path)
	_recalc_bonus()
	equipment_changed.emit()
	return path


## 全部装备的词条总和：{"atk": 倍率, "hp": 点, "def": 减伤比例}
func bonus_total() -> Dictionary:
	return _bonus


## 直接摆入装备栏与背包（读档用）。摆完重算词条并发信号让玩家节点跟上
func set_equipment(e: Dictionary, b: Array) -> void:
	equipped = e.duplicate()
	bag = b.duplicate()
	_recalc_bonus()
	equipment_changed.emit()


func _recalc_bonus() -> void:
	var atk := 0.0
	var hp := 0
	var def := 0.0
	for s in SLOT_IDS:
		var it := item_at(s)
		if it == null:
			continue
		atk += it.atk_bonus
		hp += it.hp_bonus
		def += it.def_bonus
	_bonus = {"atk": atk, "hp": hp, "def": def}


# ── 升级 ───────────────────────────────────────────────────────

## 加经验，够数就升级（可连升）。返回升了几级
func add_exp(amount: int) -> int:
	if amount <= 0:
		return 0
	exp += amount
	var ups := 0
	while exp >= exp_needed(level):
		exp -= exp_needed(level)
		level += 1
		ups += 1
		level_up.emit(level)
	exp_changed.emit(exp)
	return ups
