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

## 地图数据所在目录。**扫目录，不写死路径** —— 加一章 = 丢一个 map_*.tres 进来，
## 这一层一个字都不用改（第二章落地时就是改这里：从常量路径变成目录扫描）
const MAP_DIR := "res://data/stages"
const ITEM_DIR := "res://data/items"

var _maps: Array[MapData] = []
var _seq: Array[DungeonData] = []
## 装备掉落索引：tier → 路径数组。懒加载（第一次掉落才扫目录），进程内缓存一份
var _drop_index: Dictionary = {}


## 全部地图，按文件名排序（顺序稳定 —— 页签不会跳）。
##
## 目录扫描走 ResDir：**导出包里列出来的是 `map_x.tres.remap`**，
## 直接 ends_with(".tres") 匹配会在导出后一张地图都找不到（见 res_dir.gd）
func maps() -> Array[MapData]:
	if _maps.is_empty():
		var names := []
		for f in ResDir.files(MAP_DIR):
			if f.begins_with("map_") and f.ends_with(".tres"):
				names.append(f)
		names.sort()
		for f in names:
			var m := load("%s/%s" % [MAP_DIR, f]) as MapData
			if m != null:
				_maps.append(m)
		if _maps.is_empty():
			push_error("GameProgress: 一张地图都没加载到（%s）" % MAP_DIR)
	return _maps


## 第一张地图。单地图时代的调用点仍走这里（舆图等等）
func map() -> MapData:
	var ms := maps()
	return ms[0] if not ms.is_empty() else null


## 全局副本序列：**各张地图的副本首尾相连**。
## 跨地图解锁全靠它 —— 剑冢的第一个副本，它的前一个就是淬火岭的最后一个副本。
## 不这么串的话，每张地图的第一个副本都会「天生就开」，第二章一开局就能跳关
func sequence() -> Array[DungeonData]:
	if _seq.is_empty():
		for m in maps():
			for d in m.dungeons:
				if d != null:
					_seq.append(d)
	return _seq


## 按 id 取副本：**跨所有地图**找（单地图时代的 find_dungeon 只看一张图）
func dungeon(id: StringName) -> DungeonData:
	for d in sequence():
		if d.id == id:
			return d
	return null


## 某个档次的全部装备路径。**扫目录、不写死清单**（同 maps() 的态度）：
## 加一件装备 = 往 `data/items/` 丢一个 .tres，这里和掉落池自动跟上，
## 不改任何代码。 tier 必须是 `ItemData.Tier` 的枚举值；查不到 = 空数组
func drop_pool(tier: int) -> Array[String]:
	if _drop_index.is_empty():
		for f in ResDir.files(ITEM_DIR):
			if not f.ends_with(".tres"):
				continue
			var it := load("%s/%s" % [ITEM_DIR, f]) as ItemData
			if it == null:
				continue
			var arr: Array = _drop_index.get(it.tier, [])
			arr.append("%s/%s" % [ITEM_DIR, f])
			_drop_index[it.tier] = arr
		if _drop_index.is_empty():
			push_error("GameProgress: 一件装备都没索引到（%s）" % ITEM_DIR)
	var out: Array[String] = []
	for p in _drop_index.get(tier, []):
		out.append(str(p))
	return out


## 从副本档次池里掷一件装备的路径。**调用方自己决定掉不掉**（概率留在怪身上）；
## 池为空 / 某档一件装备都索引不到时返回空串 —— **不静默装作掉过**，调用方
## 拿到空串就跳过这次掉落（数字都不存在，硬掉一个 null 会在拾取时炸）
func roll_drop(tiers: Array[int]) -> String:
	var pool: Array[String] = []
	while pool.is_empty() and not tiers.is_empty():
		pool = drop_pool(tiers.pick_random())
	return "" if pool.is_empty() else pool.pick_random()


## 这个副本开了没有。规则：**序列里的上一个副本通关了就开**，第一个天生就开。
## 明确不做首通奖励（docs/adr/0009 §8）—— 清完一个副本的结果只是下一个副本解锁。
##
## id 根本不在数据里时返回 false（当成「没这个东西」），不是「开放」
func is_dungeon_unlocked(id: StringName) -> bool:
	var seq := sequence()
	var idx := -1
	for i in seq.size():
		if seq[i].id == id:
			idx = i
			break
	if idx < 0:
		return false
	if idx == 0:
		return true
	return SaveManager.is_cleared(seq[idx - 1].id)


## 通关一个副本：记一笔，并返回**因此解锁的下一个副本**（没有下一个时返回 null）。
## 调用方（关卡根节点）拿它决定过关界面上高亮谁
func on_dungeon_cleared(id: StringName) -> DungeonData:
	var seq := sequence()
	for i in seq.size():
		if seq[i].id == id:
			SaveManager.mark_cleared(id)
			return seq[i + 1] if i + 1 < seq.size() else null
	push_error("GameProgress: 认不出的副本 id %s" % str(id))
	return null

## 新游戏：清空副本通关记录。**不需要解锁任何东西** ——
## 第一个副本天生就开（见 is_dungeon_unlocked），其余靠一关一关打出来
func reset_progress() -> void:
	SaveManager.clear_progress()
