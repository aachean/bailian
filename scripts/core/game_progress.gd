extends Node
## 内容结构 + 推进规则（autoload）：把关卡的三层结构数据与存档里的进度凑起来，
## 回答所有人都在问的那几个问题 —— 「这一关开了没有」「清完它解锁谁」。
##
## ── 为什么要有这一层 ──────────────────────────────────────────
## 三层结构的数据住在 `data/stages/*.tres`（MapData / DungeonData / StageData），
## 进度住在 SaveManager 的存档槽里。**两边都不该知道对方**：
## 内容数据不该知道有存档这回事，存档底座不该知道「砺场有几关」这种内容细节。
## 谁把它们凑起来？就是本节点。凑法只有一套，所以它只有一个地方可写。
##
## 术语以 docs/CONTEXT.md 为准：地图 → 副本 → 关卡。
##
## ── 游戏里没有第二个地方可以算「下一关是谁」────────────────────
## 关卡根节点过关、舆图界面渲染、主菜单的新游戏初始化，三处都调这里。
## 有第二套算法的那天，就是「打完了却解锁错关卡」这类 bug 的出生时刻。

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


## 按关卡 id 反查它在结构里的位置：{"dungeon": 副本 id, "index": 段号}。
## 找不到（数据与场景对不上）返回空字典 —— 调用方要当成硬错误处理，
## 不能默默当成「第一关」，否则「这一关打完不解锁下一关」会被当成玄学
func locate(stage_id: StringName) -> Dictionary:
	var m := map()
	if m == null:
		return {}
	for d in m.dungeons:
		if d == null:
			continue
		for i in d.stages.size():
			if d.stages[i] != null and d.stages[i].id == stage_id:
				return {"dungeon": d.id, "index": i}
	return {}


## 这一关开了没有
func is_stage_unlocked(dungeon_id: StringName, index: int) -> bool:
	return SaveManager.unlocked_stages(dungeon_id) > index


## 这个副本开了没有（有没有至少解锁一段）
func is_dungeon_unlocked(dungeon_id: StringName) -> bool:
	return SaveManager.unlocked_stages(dungeon_id) >= 1


# ── 过关 ───────────────────────────────────────────────────────

## 清空一关之后调。做两件事并返回「接下来是哪一关」：
##   1. 把这一关本身标成已解锁（它会一直在，可以反复进）
##   2. 解锁下一关；下一关在别的副本时，说明本副本清完了，记一笔
##
## 返回值：{"dungeon": id, "index": n} = 新解锁的下一关；{} = 全打完了，没有下一关。
## **不做首通奖励**（docs/adr/0009 §8）—— 清完一个副本的结果只是「下一个副本解锁」，
## 外加最后一段 Boss 照常掉的那点东西。没有额外的里程碑奖励，别顺手加回来。
func on_stage_cleared(dungeon_id: StringName, index: int) -> Dictionary:
	var m := map()
	if m == null:
		return {}
	SaveManager.unlock_stage(dungeon_id, index)
	var nxt := m.next_stage(dungeon_id, index)
	if nxt.is_empty() or String(nxt["dungeon"]) != String(dungeon_id):
		SaveManager.mark_cleared(dungeon_id)   # 本副本的最后一段通了
	if nxt.is_empty():
		return {}
	SaveManager.unlock_stage(nxt["dungeon"], nxt["index"])
	return nxt


## 新游戏：清空解锁进度，然后只开第一个副本的第一段。
## 开局玩家能进的只有「砺场的第 1 段」，其余全靠一关一关打出来
func reset_progress() -> void:
	SaveManager.clear_unlock_progress()
	var m := map()
	if m == null:
		return
	var d := m.first_dungeon()
	if d != null:
		SaveManager.unlock_stage(d.id, 0)
