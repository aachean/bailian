extends Node
## 内容结构 + 推进规则（autoload）：把关卡的副本数据与存档里的进度凑起来，
## 回答所有人都在问的那两个问题 —— 「这个副本开了没有」「通关之后解锁谁」。
##
## ── 为什么要有这一层 ──────────────────────────────────────────
## 副本数据住在 `data/stages/*.tres`（MapData / DungeonData），
## 进度住在 SaveManager 的存档槽里。**两边都不该知道对方**：
## 内容数据不该知道有存档这回事，存档底座不该知道「砺场前面是谁」这种内容细节。
## 谁把它们凑起来？就是本节点。凑法只有一套，所以它只有一个地方可写。
##
## ── 粒度：副本 = 一条 3~4 屏的路（2026-09-14 重定）──────────────
## 副本内部按**屏**推进（屏是关卡根节点在场景里按 x 分出来的段），
## **屏不是可寻址的独立单元** —— 所以这里没有任何「段/屏」级的方法。
## 存档里也只有一张「已通关的副本」表，没有段数。

## 章节的地图数据。第二章加地图时这里会变成一个列表
const MAP_PATH := "res://data/stages/map_quench_ridge.tres"

var _map: MapData = null


## 唯一地图（淬火岭）。缓存住 —— 每次调用都 load 一遍没必要，
## 而且节点之间比对 `map().find_dungeon(x)` 时命中同一实例才不会出怪事
func map() -> MapData:
	if _map == null:
		_map = load(MAP_PATH) as MapData
		if _map == null:
			push_error("GameProgress: 地图数据加载失败 %s" % MAP_PATH)
	return _map


## 按 id 取副本（找不到返回 null）
func dungeon(id: StringName) -> DungeonData:
	var m := map()
	return m.find_dungeon(id) if m != null else null


## 这个副本开了没有。规则：**上一个副本通关了就开**，第一个副本天生就开。
## 明确不做首通奖励（docs/adr/0009 §8）—— 清完一个副本的结果只是下一个副本解锁。
##
## id 根本不在数据里时返回 false（当成「没这个东西」），不是「开放」——
## 认不出来的 id 不该被放进任何一个副本
func is_dungeon_unlocked(id: StringName) -> bool:
	var m := map()
	if m == null or m.find_dungeon(id) == null:
		return false
	var before := m.dungeon_before(id)
	return before == null or SaveManager.is_cleared(before.id)


## 通关一个副本：记一笔，并返回**因此解锁的下一个副本**（没有下一个时返回 null）。
## 调用方（关卡根节点）拿它决定过关界面上高亮谁
func on_dungeon_cleared(id: StringName) -> DungeonData:
	var m := map()
	if m == null or m.find_dungeon(id) == null:
		push_error("GameProgress: 认不出的副本 id %s" % str(id))
		return null
	SaveManager.mark_cleared(id)
	return m.dungeon_after(id)


## 新游戏：清空副本通关记录。**不需要解锁任何东西** ——
## 第一个副本天生就开（见 is_dungeon_unlocked），其余靠一关一关打出来
func reset_progress() -> void:
	SaveManager.clear_progress()
