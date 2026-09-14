class_name MapData
extends Resource
## 一张**地图**（Map）：一片有统一主题与敌人族群的地区，下辖若干副本。
##
## 术语以 docs/CONTEXT.md 为准：地图 → 副本 → 关卡 三层，本类是顶层。
## 第一章只有一张地图：**淬火岭** —— 山脚磨料场 → 半山断渠 → 山顶炉喉，
## 一条从山脚走到炉心的路。命名立意见 docs/adr/0009 §6。
##
## ── 为什么要有这一层，虽然现在只有一张地图 ────────────────────
## 舆图界面左边是**地图页签**。页签的内容必须来自数据，不能把「淬火岭」
## 写死在界面代码里 —— 写死的话第二章要加地图时，第一件事是回头拆界面。
## 一个 Resource 类 + 一个 .tres 的成本，换界面一次都不用改，这笔账是划算的。
##
## ── 副本之间的解锁 ───────────────────────────────────────────
## 清完一个副本 → 解锁**下一个副本**（不做首通奖励，见 docs/adr/0009 §8）。
## 「下一个是谁」由本类的 dungeons 顺序决定，所以这张表就是副本推进的顺序表。

@export_group("标识")
@export var id: StringName = &""
## 显示名的翻译 key（第一章：淬火岭）
@export var name_key: StringName = &""

@export_group("副本（按推进顺序）")
## 顺序即解锁顺序：清完第 N 个副本，第 N+1 个副本开锁
@export var dungeons: Array[DungeonData] = []


## 按 id 找副本。找不到返回 null
func find_dungeon(id: StringName) -> DungeonData:
	for d in dungeons:
		if d != null and d.id == id:
			return d
	return null


## 推进顺序上的第一个副本（开局就该开的那个）。没有副本时返回 null
func first_dungeon() -> DungeonData:
	for d in dungeons:
		if d != null:
			return d
	return null


## 副本里的第 index 个关卡（越界返回 null）
func find_stage(dungeon_id: StringName, index: int) -> StageData:
	var d := find_dungeon(dungeon_id)
	if d == null or index < 0 or index >= d.stages.size():
		return null
	return d.stages[index]


## 下一个副本。最后一个副本之后再没有（返回 null）
func dungeon_after(id: StringName) -> DungeonData:
	for i in dungeons.size():
		if dungeons[i] != null and dungeons[i].id == id:
			return dungeons[i + 1] if i + 1 < dungeons.size() else null
	return null


## 某副本在推进顺序里的第几位（0 起）。找不到返回 -1
func dungeon_order(id: StringName) -> int:
	for i in dungeons.size():
		if dungeons[i] != null and dungeons[i].id == id:
			return i
	return -1


## 关卡坐标（副本 id + 段号）的下一个关卡坐标。
## 返回 {} = 已经是这张地图的最后一关（清完它就没有下一个了）。
##
## 跨副本时**落到下一个副本的第 0 段** —— 清完一个副本的最后一关，
## 下一个副本的第一关就是「下一关」。这是 docs/adr/0009 §8 那条规则的具体形状：
## 清完一个副本，结果是下一个副本解锁（而不是凭空多出一份奖励）。
func next_stage(dungeon_id: StringName, index: int) -> Dictionary:
	var d := find_dungeon(dungeon_id)
	if d == null:
		return {}
	if index + 1 < d.stages.size():
		return {"dungeon": d.id, "index": index + 1}
	var nd := dungeon_after(d.id)
	if nd != null and not nd.stages.is_empty():
		return {"dungeon": nd.id, "index": 0}
	return {}


## 关卡总数（摆在数据里的，不含还没开工的副本）
func stage_count() -> int:
	var n := 0
	for d in dungeons:
		if d != null:
			n += d.stages.size()
	return n
