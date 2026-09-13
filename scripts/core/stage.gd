extends Node2D
## 关卡根节点：负责「离开时收集世界快照、进入时恢复」。
##
## 「继续游戏 = 回到离开那一刻」在关卡侧的实现都在这里：
##   收集（collect）：玩家血量位置 + 场景里每个 enemy 组节点的血量位置死活
##   恢复（_apply_state）：按存好的值摆回去；死着的怪摆回死亡状态等重生
## 触发点：玩家按 Esc 时由 player 调 collect 并写档；
## 进入关卡时 _ready 向 SaveManager 要一次待恢复的快照（没有就全新开局）。
##
## 加新实体类型时：让它进 enemy 组并实现 apply_saved()，这里自动覆盖；
## 非战斗实体（如靶子）也在 enemy 组里，一样被存 —— 训练靶子被打剩的血，
## 继续游戏后也是剩那些，行为统一，不做例外。

const PLAYER_PATH := "Player"

## 相机活动范围（世界坐标）。单屏关卡（如 test_room 640×360）设成与视口同大，
## 相机就不动；多屏关卡设成关卡实际尺寸，视野跟着玩家走、到边就停。
@export var bounds: Rect2 = Rect2(0, 0, 640, 360)


func _ready() -> void:
	var cam := get_node_or_null(PLAYER_PATH + "/Camera") as Camera2D
	if cam != null:
		cam.limit_left = int(bounds.position.x)
		cam.limit_top = int(bounds.position.y)
		cam.limit_right = int(bounds.end.x)
		cam.limit_bottom = int(bounds.end.y)
		cam.reset_smoothing()
	var st := SaveManager.take_pending_state()
	if not st.is_empty():
		_apply_state(st)


## 收集当前世界状态。结构：
##   player: { hp, x, y }
##   enemies: [ { node(相对路径), hp, x, y } ]   hp<=0 表示死着，恢复时走死亡态
func collect() -> Dictionary:
	var out := {"player": {}, "enemies": []}
	var player := get_node_or_null(PLAYER_PATH)
	if player != null:
		var h := player.get_node("Health") as Health
		out.player = {
			"hp": h.hp,
			"x": player.global_position.x,
			"y": player.global_position.y,
			"shards": int(player.get("shards")),
			"upgrade": int(player.get("upgrade_level")),
			"level": int(player.get("level")),
			"exp": int(player.get("exp_pts")),
			"mp": int(player.get("mp")),
			# 装备栏 / 背包的真相在 PlayerState（autoload），不在玩家节点上 ——
			# 这里只是把它抄进快照，读档时由 player.apply_saved 抄回去
			"equipped": PlayerState.equipped.duplicate(),
			"bag": PlayerState.bag.duplicate(),
		}
	var enemies: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not e.is_inside_tree():
			continue
		# 只收本关卡的怪（跨场景的组员不该进来）
		if not is_ancestor_of(e):
			continue
		var h := e.get_node("Health") as Health
		enemies.append({
			"node": str(get_path_to(e)),
			"hp": h.hp,
			"x": e.global_position.x,
			"y": e.global_position.y,
		})
	out.enemies = enemies
	return out


func _apply_state(st: Dictionary) -> void:
	var player := get_node_or_null(PLAYER_PATH)
	if player != null and st.has("player"):
		if player.has_method("apply_saved"):
			player.call("apply_saved", st.player)
	for d in st.get("enemies", []):
		var e := get_node_or_null(NodePath(str(d.get("node", ""))))
		if e != null and e.has_method("apply_saved"):
			e.call("apply_saved", d)
