extends Node
## 场景完整性检查器：解析每个场景文件「声明了哪些节点路径」，
## 与实例化后的实际树对比 —— 缺一个节点就红。
##
## 为什么存在：手写 .tscn 时嵌套节点的 parent 路径写错（漏一层），
## 引擎只会打 WARNING 然后**静默丢弃该节点**——界面缺一块、脚本引用炸，
## 却没有任何硬错误。这个检查器把 WARNING 变成硬失败。
##
## 跑法（无头）：
##     godot --headless --path <项目根> res://tests/check_scenes.tscn
##
## 新增场景后把路径加进 SCENES。全部场景通用，不用改逻辑。

const SCENES := [
	"res://scenes/ui/hud.tscn",
	"res://scenes/ui/pause_menu.tscn",
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/damage_number.tscn",
	"res://scenes/characters/player.tscn",
	"res://scenes/enemies/walker.tscn",
	"res://scenes/enemies/dasher.tscn",
	"res://scenes/enemies/spearman.tscn",
	"res://scenes/enemies/boss.tscn",
	"res://scenes/enemies/brute.tscn",
	"res://scenes/enemies/caster.tscn",
	"res://scenes/enemies/boss2.tscn",
	"res://scenes/enemies/target_dummy.tscn",
	"res://scenes/enemies/projectile.tscn",
	"res://scenes/core/portal.tscn",
	"res://scenes/core/anvil.tscn",
	"res://scenes/core/checkpoint.tscn",
	"res://scenes/core/npc.tscn",
	"res://scenes/core/atlas_pedestal.tscn",
	"res://scenes/ui/dialogue_box.tscn",
	"res://scenes/ui/atlas.tscn",
	"res://scenes/ui/death_menu.tscn",
	"res://scenes/stages/test_room.tscn",
	"res://scenes/stages/town.tscn",
	"res://scenes/stages/lichang.tscn",
	"res://scenes/stages/level_2.tscn",
	"res://scenes/stages/level_3.tscn",
]

var _pass := 0
var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("═══ 场景完整性检查 ═══")
	for path in SCENES:
		_check_scene(path)
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


## 从 tscn 文本里解析「声明的节点绝对路径集合」（instance 覆盖节点也算）
func _declared_paths(text: String) -> Dictionary:
	var out := {}
	var root_name := ""
	var regex := RegEx.new()
	regex.compile('\\[node name="([^"]+)"(?:[^\\]]*parent="([^"]*)")?')
	for m in regex.search_all(text):
		var node_name := m.get_string(1)
		var parent := m.get_string(2)
		var at_root := parent.is_empty() or parent == "."
		if root_name.is_empty() and at_root:
			root_name = node_name
			out[node_name] = true
		elif at_root:
			out[root_name + "/" + node_name] = true
		else:
			out[root_name + "/" + parent + "/" + node_name] = true
	return out


func _collect_actual(node: Node, prefix: String, out: Dictionary) -> void:
	var path: String = String(node.name) if prefix.is_empty() else prefix + "/" + String(node.name)
	out[path] = true
	for c in node.get_children():
		_collect_actual(c, path, out)


func _check_scene(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail += 1
		print("  FAIL  %s —— 文件打不开" % path)
		return
	var declared := _declared_paths(file.get_as_text())
	var packed: PackedScene = load(path)
	if packed == null:
		_fail += 1
		print("  FAIL  %s —— 加载失败" % path)
		return
	var inst := packed.instantiate()
	add_child(inst)
	var actual := {}
	_collect_actual(inst, "", actual)
	remove_child(inst)
	inst.queue_free()


	var missing := PackedStringArray()
	for p in declared:
		if not actual.has(p):
			missing.append(p)

	if missing.is_empty():
		_pass += 1
		print("  PASS  %-52s %d 个节点全部就位" % [path.get_file(), declared.size()])
	else:
		_fail += 1
		print("  FAIL  %s —— 缺节点（tscn 声明了但实例化时被丢弃，多半是 parent 路径写错）:\n         %s" % [
			path.get_file(), ", ".join(missing)])
