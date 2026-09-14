extends SceneTree
## 资源构建脚本：生成 data/stages/ 下的「地图 → 副本 → 关卡」三层数据。
##
## 跑法（无头，不开窗口）：
##     godot --headless --path <项目根> --script res://tools/gen_stage_data.gd
##
## ── 为什么不手写 .tres ────────────────────────────────────────
## 手写要自己拼 `Array[StageData]([ExtResource(...)])` 这种带类型的数组字面量，
## 类型名写错一个字，Godot 只会静默当成空数组（界面上一段都不显示，且不报错）。
## 让引擎自己序列化，格式天然正确。
##
## 分层落盘（stage_*.tres ← dungeon_*.tres ← map_*.tres 用引用串起来，不内联）：
## 每层单独一个文件，改一段只动那一个文件，git diff 也读得出来。
## **保存后要 load 回来再交给父层** —— 新建的实例身上没有路径，
## 父层保存时会被当成「内联的子资源」写进同一份文件，那样每个关卡就有两份真相。
##
## **改内容改这里**：加关卡 / 调推荐值都改本文件再跑一次，
## 别手改 .tres 又只改一半 —— 下次跑会被冲掉，这是刻意的（单一事实来源）。
##
## 本脚本不参与游戏运行，tools/ 目录下的一切都是如此。

const OUT_DIR := "res://data/stages/"

## 砺场三段的推荐值。**软压力，不是门票**（见 docs/adr/0009 §5）：
## 第 1 段是开局就能进的门口；第 3 段有 200 血的磨刀石守卫，给一点准备量
const LICHANG_1 := {"id": &"lichang_1", "path": "res://scenes/stages/lichang_1.tscn",
	"level": 1, "weapon": 0}
const LICHANG_2 := {"id": &"lichang_2", "path": "res://scenes/stages/lichang_2.tscn",
	"level": 2, "weapon": 0}
const LICHANG_3 := {"id": &"lichang_3", "path": "res://scenes/stages/lichang_3.tscn",
	"level": 3, "weapon": 1}


func _initialize() -> void:
	print("生成 data/stages/ 三层结构数据")
	var ok := _write_all()
	print("")
	print("生成完毕：%s" % ("全部成功" if ok else "**有失败，见上**"))
	quit(0 if ok else 1)


## 第一章唯一地图：淬火岭。三个副本是一条从山脚走到炉心的路。
##
## 砺场（山脚磨料场）的内容来自线性时代的 `level_1.tscn` —— **只重切，不重做**：
## 怪的种类与数量、猎人 NPC、关底 Boss「磨刀石守卫」原样搬进来，
## 变的只是「一条连续的路」被切成了三个各自独立的一屏。
func _write_all() -> bool:
	var lichang := _dungeon(&"lichang", &"DUNGEON_LICHANG",
		[_stage(LICHANG_1), _stage(LICHANG_2), _stage(LICHANG_3)])
	# 断淬渠 / 炉喉：**还没开工**。stages 留空是有意的 ——
	# 舆图会照实把它们标成「未开放」，而不是把空副本画成一张空列表。
	# 步 2 把 level_2 / level_3 重切进来时，这里各加几个 _stage() 就行
	var duancuiqu := _dungeon(&"duancuiqu", &"DUNGEON_DUANCUIQU", [])
	var luhou := _dungeon(&"luhou", &"DUNGEON_LUHOU", [])

	var map := MapData.new()
	map.id = &"quench_ridge"
	map.name_key = &"MAP_QUENCH_RIDGE"
	var ds: Array[DungeonData] = []
	ds.append(lichang)
	ds.append(duancuiqu)
	ds.append(luhou)
	map.dungeons = ds
	return _save(map, OUT_DIR + "map_quench_ridge.tres")


# ── 小工具 ─────────────────────────────────────────────────────

func _stage(d: Dictionary) -> StageData:
	var path := OUT_DIR + "stage_%s.tres" % String(d["id"])
	var s := StageData.new()
	s.id = d["id"]
	s.scene_path = d["path"]
	s.rec_level = d["level"]
	s.rec_weapon = d["weapon"]
	_save(s, path)
	return load(path) as StageData


func _dungeon(id: StringName, name_key: StringName, stages: Array) -> DungeonData:
	var path := OUT_DIR + "dungeon_%s.tres" % String(id)
	var d := DungeonData.new()
	d.id = id
	d.name_key = name_key
	var typed: Array[StageData] = []
	for s in stages:
		typed.append(s as StageData)
	d.stages = typed
	_save(d, path)
	return load(path) as DungeonData


## 保存后资源的 resource_path 会被引擎设成这个路径，
## 于是父层引用它时会写成 ExtResource（分层落盘的前提）
func _save(res: Resource, path: String) -> bool:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("保存失败 %s err=%d" % [path, err])
		return false
	print("  %s" % path)
	return true
