class_name GrowthService
extends RefCounted
## 成长域服务：等级 / 经验 / 主线进度标记（flags）。
##
## 见 [ADR-0027](../../docs/adr/0027-playerstate-decomposition.md)：PlayerState 拆解的第三个域。
##
## ── 过渡期分工 ─────────────────────────────────────────────────
## **数据仍住 PlayerState 容器**（进存档）：level · exp · flags。
## `progression`（成长曲线资源）也留容器上 —— 它被物品域的 `_recalc_bonus` 也读
## （`soften`），是两个域共享的只读数据，不归本域独占。
## 服务持 PlayerState 引用 `_s`，读写数据字段、借 level_up / exp_changed 信号。

var _s: Object


func _init(state: Object) -> void:
	_s = state


## 升到下一级需要的经验。**满级返回 0**，所以调用方比较前先问 is_max_level()
func exp_needed(level: int) -> int:
	return _s.progression.exp_needed(level)


func is_max_level() -> bool:
	return _s.progression.is_max(_s.level)


## 加经验，够数就升级（可连升）。返回升了几级。
## **满级之后不再累积经验**（直接丢）—— 否则 HUD 经验条会在满级后继续涨，玩家以为还能升
func add_exp(amount: int) -> int:
	if amount <= 0 or is_max_level():
		return 0
	_s.exp += amount
	var ups := 0
	while not is_max_level() and _s.exp >= exp_needed(_s.level):
		_s.exp -= exp_needed(_s.level)
		_s.level += 1
		ups += 1
		_s.level_up.emit(_s.level)
	if is_max_level():
		_s.exp = 0
	_s.exp_changed.emit(_s.exp)
	return ups


# ── 主线进度标记 ───────────────────────────────────────────────
# 用字典而不是一堆 bool 成员：flag 会越来越多（每个 NPC / 主线节点一个），
# 加一个零成本。存档里存普通字符串键，没进过历史的 flag 直接不存在，老档天然兼容

func set_flag(name: StringName) -> void:
	if name == &"":
		return
	_s.flags[String(name)] = true


func has_flag(name: StringName) -> bool:
	return name != &"" and _s.flags.has(String(name))
