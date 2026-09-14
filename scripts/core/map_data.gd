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
## 「下一个是谁」「前一个是谁」都由本类的 dungeons 顺序决定。
##
## **这里没有「关卡」这一层的方法**（2026-09-14 重定粒度之后）：
## 副本内部是按屏推进的（见 DungeonData 的注释），
## 屏不是可寻址的独立单元 —— 外面没有任何地方需要「下一屏是谁」这种查询。

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


## 下一个副本。最后一个副本之后再没有（返回 null）
func dungeon_after(id: StringName) -> DungeonData:
	for i in dungeons.size():
		if dungeons[i] != null and dungeons[i].id == id:
			return dungeons[i + 1] if i + 1 < dungeons.size() else null
	return null


## 上一个副本。第一个副本之前没有（返回 null）。
## 「这个副本开了没有」= 上一个副本通关了没有（第一个副本天生就开）
func dungeon_before(id: StringName) -> DungeonData:
	for i in dungeons.size():
		if dungeons[i] != null and dungeons[i].id == id:
			return dungeons[i - 1] if i > 0 else null
	return null


## 某副本在推进顺序里的第几位（0 起）。找不到返回 -1
func dungeon_order(id: StringName) -> int:
	for i in dungeons.size():
		if dungeons[i] != null and dungeons[i].id == id:
			return i
	return -1


## 所有副本的屏数合计（「这一章有多少东西可打」的一个粗刻度）
func total_screens() -> int:
	var n := 0
	for d in dungeons:
		if d != null:
			n += d.screen_count
	return n
