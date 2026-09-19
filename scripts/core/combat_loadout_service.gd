class_name CombatLoadoutService
extends RefCounted
## 战斗装配域服务：技能槽 + 预载消耗品次数 + 还魂丹。
## 「带在身上、战斗中用的东西」—— 运行时被 player.gd 调用。
##
## 见 [ADR-0027](../../docs/adr/0027-playerstate-decomposition.md)：PlayerState 拆解的第四个域。
##
## ── 过渡期分工 ─────────────────────────────────────────────────
## **数据仍住 PlayerState 容器**（进存档）：skill_slots · potions · revive_tokens · revive_bought。
## **常量留容器上**（外部按 PlayerState.POTION_HP 等引用，const 不能转发）。
## 服务持 PlayerState 引用 `_s`，读写数据、借 skills_changed 信号。
##
## ── 跨域调用（走对方公开方法）────────────────────────────────
##   经济域：spend_gold（买符 / 买补给 / 买还魂丹）
##   成长域：flags（进图补给用 flag 记「这图领过没」）

var _s: Object


func _init(state: Object) -> void:
	_s = state


# ── 技能栏 ─────────────────────────────────────────────────────

## 取某个槽位的技能（空槽返回 null）
func skill_at(i: int) -> SkillData:
	if i < 0 or i >= _s.skill_slots.size():
		return null
	var p := str(_s.skill_slots[i])
	return load(p) as SkillData if not p.is_empty() else null


func skill_paths() -> Array:
	return _s.skill_slots.duplicate()


func carries(path: String) -> bool:
	return _s.skill_slots.has(path)


## 把技能装进指定槽位。同一个技能已经在别的槽里的话先摘掉 ——
## 不然会「同一个技能占两格、按两个键放同一招」
func set_skill_slot(i: int, path: String) -> void:
	if i < 0 or i >= PlayerState.SKILL_SLOT_COUNT:
		return
	var idx: int = _s.skill_slots.find(path)
	if idx >= 0 and idx != i:
		_s.skill_slots[idx] = ""
	_s.skill_slots[i] = path
	_s.skills_changed.emit()


func clear_skill_slot(i: int) -> void:
	if i < 0 or i >= PlayerState.SKILL_SLOT_COUNT:
		return
	_s.skill_slots[i] = ""
	_s.skills_changed.emit()


func clear_skill_slot_by_path(path: String) -> void:
	var idx: int = _s.skill_slots.find(path)
	if idx >= 0:
		clear_skill_slot(idx)


## 自动补位：把「已解锁但没带着」的技能依次填进空槽。
## 只在有空槽时填 —— 槽满了以后换哪个是玩家的决定
func auto_fill_slots(available: Array) -> bool:
	var changed := false
	for path in available:
		var p := str(path)
		if p.is_empty() or carries(p):
			continue
		var empty: int = _s.skill_slots.find("")
		if empty < 0:
			break
		_s.skill_slots[empty] = p
		changed = true
	if changed:
		_s.skills_changed.emit()
	return changed


# ── 预载消耗品（原则 5.6 第二条：买「次数」、按 6 / 7 主动用）────
# 次数不是成长属性，不进 _bonus / 不发 equipment_changed —— HUD 每次 refresh 当场重读

## 还剩几次
func potion_charges(kind: StringName) -> int:
	return int(_s.potions.get(String(kind), 0))


## 一种消耗品的单价。**认不出的 kind 要炸**，不许静默按另一种的价算
func potion_price(kind: StringName) -> int:
	match kind:
		PlayerState.POTION_HP:
			return PlayerState.POTION_HP_PRICE
		PlayerState.POTION_MP:
			return PlayerState.POTION_MP_PRICE
	push_error("CombatLoadout: 认不出的消耗品种类 %s" % str(kind))
	return 0


## 加次数（商店买，以后别的来源也走这里）
func add_potion_charges(kind: StringName, n: int) -> void:
	if n <= 0:
		return
	_s.potions[String(kind)] = potion_charges(kind) + n


## 用掉一次。返回 false = 没次数了 —— 调用方**必须**把这件事说出来（不许静默）
func use_potion(kind: StringName) -> bool:
	var left := potion_charges(kind)
	if left <= 0:
		return false
	_s.potions[String(kind)] = left - 1
	return true


## 买一份符（回血 / 回蓝）
func buy_potion(kind: StringName) -> bool:
	if not _s.spend_gold(potion_price(kind)):     # ← 跨域：花元宝是经济域的事
		return false
	add_potion_charges(kind, PlayerState.POTION_CHARGES)
	return true


## 买补给包：**一次扣钱、血蓝各加 5 次**（不做成扣两次钱的半成交状态）
func buy_supply() -> bool:
	if not _s.spend_gold(PlayerState.SUPPLY_PRICE):
		return false
	add_potion_charges(PlayerState.POTION_HP, PlayerState.SUPPLY_CHARGES)
	add_potion_charges(PlayerState.POTION_MP, PlayerState.SUPPLY_CHARGES)
	return true


# ── 还魂丹（原则 5.7：死亡罚效率不罚进度，丹是安全网不是免死金牌）──

## 用一枚还魂丹。返回 false = 没丹了（调用方别把按钮按出「没反应」）
func use_revive_token() -> bool:
	if _s.revive_tokens <= 0:
		return false
	_s.revive_tokens -= 1
	return true


## 进图补给：每张地图**第一次进**送 2 枚（进图就领，与通关无关）。
## 返回 true = 这次真的发了（第一次进）
func grant_map_supply(map_id: StringName) -> bool:
	var key := "revive_supply_%s" % map_id
	if _s.flags.has(key):                          # ← 跨域：flag 是成长域的事
		return false
	_s.flags[key] = true
	_s.revive_tokens += 2
	return true


## 商店买还魂丹（限购：每图 5 枚）
func buy_revive_token(map_id: StringName) -> bool:
	var key := String(map_id)
	var bought := int(_s.revive_bought.get(key, 0))
	if bought >= 5:
		return false
	if not _s.spend_gold(PlayerState.REVIVE_PRICE):
		return false
	_s.revive_bought[key] = bought + 1
	_s.revive_tokens += 1
	return true


func revive_bought_in(map_id: StringName) -> int:
	return int(_s.revive_bought.get(String(map_id), 0))
