extends Node
## 玩家的跨场景持久数据（autoload）。
##
## 碎片、强化等级这类「属于玩家、不属于关卡」的数据**不能**存在玩家节点上：
## 每次切场景玩家节点整个重建，存在它身上的东西就没了 ——
## 用户实测「回到安全区碎片全没了」就是这么丢的。
## 玩家节点在 _ready 从这里取、_exit_tree 写回；这里的数据跨场景、随快照进存档。
##
## HP 不在这里：安全区回城自动满血（回城即治疗，原型阶段的简单约定）。

var shards: int = 0
var upgrade_level: int = 0


func reset_for_new_game() -> void:
	shards = 0
	upgrade_level = 0


func load_from(d: Dictionary) -> void:
	shards = int(d.get("shards", shards))
	upgrade_level = int(d.get("upgrade", upgrade_level))


func save_to() -> Dictionary:
	return {"shards": shards, "upgrade": upgrade_level}
