class_name ItemsService
extends RefCounted
## 物品域服务：装备实例（uid）+ 背包 / 装备栏 + 词条聚合 + 武器门。
##
## 见 [ADR-0027](../../docs/adr/0027-playerstate-decomposition.md)：PlayerState 拆解的第五个、
## 也是**最重**的域 —— 经济/锻造两域的跨域契约都落在它的公开方法上（add_item / item_of /
## _remove_from_bag / _recalc_bonus / equipped_uid / bag）。压轴拆它，前四域已经把「缝」定好了。
##
## ── 过渡期分工 ─────────────────────────────────────────────────
## **数据仍住 PlayerState 容器**（进存档、被 hud/forge_panel/stage 直接读写）：
##   equipped · bag · forge · next_uid · character_id · _bonus · _stat_cache。
## `UID_SEP` 常量、`progression` 资源也留容器上（外部/跨域共享）。
## **本域自己拥有**：角色定义缓存 `_character` / `_character_loaded_for`（纯派生，无人外部读）。
##
## ── 跨域调用（走对方公开方法）────────────────────────────────
##   锻造域：forge_atk（词条聚合要把强化% 叠进同一个乘区，4.1）

const UID_SEP := "#"

var _s: Object


func _init(state: Object) -> void:
	_s = state


# ── 装备实例 id ────────────────────────────────────────────────

## 新实例的 uid。序号全局递增，只要在同一份存档里唯一就够
func make_uid(path: String) -> String:
	var uid := "%s%s%d" % [path, UID_SEP, _s.next_uid]
	_s.next_uid += 1
	return uid


## uid → 资源路径。没有 # 的串原样返回
func path_of(uid: String) -> String:
	var i := uid.find(UID_SEP)
	return uid if i < 0 else uid.substr(0, i)


## uid → 装备数据。坏路径返回 null（不崩）
func item_of(uid: String) -> ItemData:
	if uid.is_empty():
		return null
	return load(path_of(uid)) as ItemData


## 把 next_uid 推到「所有已存在 uid 的最大序号 + 1」之后（读档兜底：档里漏了 next_uid）
func ensure_uid_counter() -> void:
	var max_seen := 0
	var all: Array = _s.bag.duplicate()
	for s in ItemData.SLOT_IDS:
		all.append(equipped_uid(s))
	for u in all:
		var i := str(u).find(UID_SEP)
		if i >= 0:
			max_seen = maxi(max_seen, int(str(u).substr(i + 1)))
	_s.next_uid = maxi(_s.next_uid, max_seen + 1)


# ── 角色与武器门 ───────────────────────────────────────────────

## 角色定义缓存**住容器**（`_s._character` / `_s._character_loaded_for`）——
## test_m16 / test_charnet 直接写 `PlayerState._character = null` 来强制重载，
## 缓存必须在它们够得着的地方，不能搬进本服务（否则清缓存清了个寂寞 → 静默用旧角色）
func character_def() -> CharacterData:
	if _s._character == null or _s._character_loaded_for != _s.character_id:
		_s._character = CharacterData.by_id(StringName(_s.character_id))
		if _s._character == null:
			_s._character = CharacterData.default_character()
		_s._character_loaded_for = _s.character_id
	return _s._character


## 这件装备当前角色能不能穿。武器看类型匹配；防具/饰品不限
func can_equip(item: ItemData) -> bool:
	if item == null:
		return false
	if item.weapon_type == &"":
		return true
	return item.weapon_type == character_def().weapon_type


# ── 装备栏读取 ─────────────────────────────────────────────────

func equipped_uid(slot: StringName) -> String:
	return str(_s.equipped.get(String(slot), ""))


func item_at(slot: StringName) -> ItemData:
	return item_of(equipped_uid(slot))


## 按槽位顺序取「当前穿着的全部装备」，空槽是 null（界面按顺序画）
func equipped_list() -> Array:
	var out: Array = []
	for s in ItemData.SLOT_IDS:
		out.append(item_at(s))
	return out


# ── 背包 / 装备栏操作 ──────────────────────────────────────────

## 捡到一件装备：发一个新实例 id 进背包。返回新 uid；空串 = 不是装备
func add_item(path: String) -> String:
	if not (load(path) is ItemData):
		push_warning("ItemsService: 不是装备资源: %s" % path)
		return ""
	var uid := make_uid(path)
	_s.bag.append(uid)
	_s.equipment_changed.emit()
	return uid


## 穿上一件背包里的装备（uid）。返回被替换下来的那件 uid（"" = 原来空槽）。
## 换下来的自动回背包。**武器类型是唯一的门**（防具/饰品 weapon_type 为空则不限）
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
		_s.bag.append(old)          # 换下来的回背包
	_s.equipped[slot] = uid
	_recalc_bonus()
	_s.equipment_changed.emit()
	return old


## 卸下某个槽位，装备回背包。返回卸下的 uid（"" = 本来就空着）
func unequip(slot: StringName) -> String:
	var key := String(slot)
	var uid := str(_s.equipped.get(key, ""))
	if uid.is_empty():
		return ""
	_s.equipped.erase(key)
	_s.bag.append(uid)
	_recalc_bonus()
	_s.equipment_changed.emit()
	return uid


## 背包里去掉某件（穿上时调）。找不到就什么都不做（老档装备可能直接摆在装备栏、不在包里）
func _remove_from_bag(uid: String) -> void:
	var idx: int = _s.bag.find(uid)
	if idx >= 0:
		_s.bag.remove_at(idx)


## 直接摆入装备栏、背包与强化表（读档用）。摆完重算词条并发信号
func set_equipment(e: Dictionary, b: Array, f: Dictionary = {}) -> void:
	_s.equipped = e.duplicate()
	_s.bag = b.duplicate()
	_s.forge = f.duplicate()
	ensure_uid_counter()
	_recalc_bonus()
	_s.equipment_changed.emit()


# ── 词条聚合 ───────────────────────────────────────────────────

## 全部装备的词条总和（含各件的强化加成）
func bonus_total() -> Dictionary:
	return _s._bonus


## 这件装备**实例**的平铺词条（已定的值）：{"atk","hp","def"}。
## uid 哈希当种子 —— 同一个实例每次算出来完全一样，不进存档、读档换场景都不变（ADR-0017）
func stat_of(uid: String) -> Dictionary:
	if uid.is_empty():
		return {"atk": 0, "hp": 0, "def": 0}
	if _s._stat_cache.has(uid):
		return _s._stat_cache[uid]
	var it := item_of(uid)
	var out: Dictionary
	if it == null:
		out = {"atk": 0, "hp": 0, "def": 0}
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(uid)
		out = it.roll(rng)
	_s._stat_cache[uid] = out
	return out


func _recalc_bonus() -> void:
	var atk_flat := 0
	var atk_pct := 0.0
	var hp := 0
	var def_flat := 0
	for s in ItemData.SLOT_IDS:
		var uid: String = equipped_uid(s)
		if uid.is_empty():
			continue
		var st := stat_of(uid)
		atk_flat += int(st.get("atk", 0))
		hp += int(st.get("hp", 0))
		def_flat += int(st.get("def", 0))
		atk_pct += _s.forge_atk(uid)              # ← 跨域：强化% 叠进同一个乘区（4.1）
	var prog = _s.progression
	_s._bonus = {
		# 平铺攻击**不进软上限**：能穿件数固定（8 槽各 1），每件上限由档位封死（ADR-0021 §2.6）
		"atk_flat": atk_flat,
		# 强化% 仍要压：单件顶 +72.8%，8 件叠 +582%。knee/cap 沿用 1.0/1.0
		# ⚠️ 别把这条曲线套到平铺攻击上 —— 48 点走 soften(x,1,1) 会变成 1.98
		"atk_pct": prog.soften(atk_pct, prog.soft_knee_atk, prog.soft_cap_atk),
		"hp": hp,
		# 平铺防御不进这里 —— 它走 Health 的护甲曲线，卡 0.6（4.2 的上限仍只有一处）
		"def_flat": def_flat,
	}
