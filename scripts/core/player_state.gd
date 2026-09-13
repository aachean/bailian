extends Node
## 玩家成长数据（autoload）：等级 / 经验 / 蓝量上限这些「属于玩家」的东西。
##
## 与 PlayerState 合并过考虑——但它已经叫 PlayerState，等级经验就住在同一家：
## 本文件实际承担 shards / upgrade / level / exp 四样跨场景数据。
## 升级逻辑也在这（纯数据 + 信号），玩家节点只负责听信号改血条和蓝上限。

## 升级时发。玩家听了加血上限 / 蓝上限并回满
signal level_up(new_level: int)

## 经验变化时发（包括没升级的零散经验）—— 场景里的玩家节点听它同步，
## 否则 HUD 上的经验条只会在切场景后「突然」跳起来（实测反馈）
signal exp_changed(new_exp: int)

## 升到下一级需要的经验：线性增长，原型期手感友好
func exp_needed(level: int) -> int:
	return 20 + (level - 1) * 15


var shards: int = 0
var upgrade_level: int = 0

var level: int = 1
var exp: int = 0


func reset_for_new_game() -> void:
	shards = 0
	upgrade_level = 0
	level = 1
	exp = 0


func load_from(d: Dictionary) -> void:
	shards = int(d.get("shards", shards))
	upgrade_level = int(d.get("upgrade", upgrade_level))
	level = int(d.get("level", level))
	exp = int(d.get("exp", exp))


func save_to() -> Dictionary:
	return {"shards": shards, "upgrade": upgrade_level, "level": level, "exp": exp}


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
