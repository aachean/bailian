extends SceneTree
## 资源构建脚本：生成 data/stages/ 下的「地图 → 副本」数据。
##
## 跑法（无头，不开窗口）：
##     godot --headless --path <项目根> --script res://tools/gen_stage_data.gd
##
## ── 粒度：副本 = 一条 3~4 屏的路 ──────────────────────────────
## 副本内部按**屏**推进（打完一屏往右走下一屏，最后一屏出 Boss）。
## **屏不是数据** —— 它是关卡根节点在场景里按 x 分出来的段（`ScreenN` 分组）。
## 所以这里只到「副本」这一层：几个副本、各自哪个场景、几屏、推荐实力多少。
##
## ── 为什么不手写 .tres ────────────────────────────────────────
## 手写要自己拼 `Array[DungeonData]([ExtResource(...)])` 这种带类型的数组字面量，
## 类型名写错一个字，Godot 只会静默当成空数组（舆图上一个副本都不显示，且不报错）。
## 让引擎自己序列化，格式天然正确。
##
## 保存后要 **load 回来再交给父层** —— 新建的实例身上没有路径，
## 父层保存时会被当成「内联的子资源」写进同一份文件，那样每个副本就有两份真相。
##
## **改内容改这里**，别手改 .tres 又只改一半（下次跑会被冲掉，这是刻意的）。

const OUT_DIR := "res://data/stages/"


func _initialize() -> void:
	print("生成 data/stages/ 的副本数据")
	var ok := _write_all()
	print("")
	print("生成完毕：%s" % ("全部成功" if ok else "**有失败，见上**"))
	quit(0 if ok else 1)


## 第一章唯一地图：淬火岭。三个副本是一条从山脚走到炉心的路。
func _write_all() -> bool:
	# 砺场（山脚磨料场）：3 屏，最后一屏是磨刀石守卫。
	# 内容来自线性时代的 `level_1.tscn` —— **只重切，不重做**
	var lichang := _dungeon(&"lichang", &"DUNGEON_LICHANG",
		"res://scenes/stages/lichang.tscn", 3, 1, 0)
	# 断淬渠（渠底）：4 屏。新内容 = 掷火者（远程）与重锤兵；
	# 屏 1 就让掷火者单独出场，屏 3 让重锤兵改用石甲卫的碎地（Boss 招式的预告）
	var duancuiqu := _dungeon(&"duancuiqu", &"DUNGEON_DUANCUIQU",
		"res://scenes/stages/duancuiqu.tscn", 4, 12, 2)
	# 炉喉（炉心）：5 屏，第一章的终点。全类型 + **精英变体**（4.3）：
	# 同一套 AI、更早发现、追得更紧、出手更密 —— 难度长在行为上而不是血条上
	var luhou := _dungeon(&"luhou", &"DUNGEON_LUHOU",
		"res://scenes/stages/luhou.tscn", 5, 25, 4)

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

func _dungeon(id: StringName, name_key: StringName, scene_path: String,
		screens: int, rec_level: int, rec_weapon: int) -> DungeonData:
	var path := OUT_DIR + "dungeon_%s.tres" % String(id)
	var d := DungeonData.new()
	d.id = id
	d.name_key = name_key
	d.scene_path = scene_path
	d.screen_count = screens
	d.rec_level = rec_level
	d.rec_weapon = rec_weapon
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
