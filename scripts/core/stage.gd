extends Node2D
## 关卡根节点。三件事，按旧到新排：
##   1. **相机边界**（bounds）—— 一屏的关卡设成与视口同大，相机就不动
##   2. **收集 / 恢复世界快照** —— 「继续游戏 = 回到离开那一刻」的关卡侧实现
##   3. **清空过关**（三层结构）—— 关内敌人全部清空即过关，解锁下一段
##
## ── 收集（collect）/ 恢复（_apply_state）─────────────────────
## 收集：玩家血量位置 + 场景里每个 enemy 组节点的血量位置死活
## 恢复：按存好的值摆回去；死着的怪摆回死亡状态
## 触发点：玩家按 Esc 时由 player 调 collect 并写档；
## 进入关卡时 _ready 向 SaveManager 要一次待恢复的快照（没有就全新开局）。
##
## 加新实体类型时：让它进 enemy 组并实现 apply_saved()，这里自动覆盖；
## 非战斗实体（如靶子）也在 enemy 组里，一样被存 —— 训练靶子被打剩的血，
## 继续游戏后也是剩那些，行为统一，不做例外。
##
## ── 过关判据为什么必须是「清空」───────────────────────────────
## 逐段解锁需要一个**说得清的过关判据**，否则「解锁下一段」没有触发点
## （docs/adr/0009 §2）。单屏关卡里，没有比「怪打完了」更直白的判据。
## 体量靠波次撑（后续增量），不靠加密 —— 变的只是「分批来」。
##
## ── 死亡不在这里管 ───────────────────────────────────────────
## 那是玩家自己的状态机（player.gd）。这里的 restart() 只提供「重开本关」
## 这个动作，由 player 在死亡计时结束时调用。

const PLAYER_PATH := "Player"

## 这一关是三层结构里的哪一个（`data/stages/stage_*.tres`）。
## **留空 = 这个场景不属于三层结构** —— 测试房间、以及还没重切的 `level_2/3`
## 都是这样。留空就只做相机与快照，不做任何过关判定：
## 否则直接跑一遍 test_room（里面一个怪都没有）会被判成「开局即过关」。
@export var stage_data: StageData

## 相机活动范围（世界坐标）。单屏关卡（640×360）设成与视口同大，相机就不动；
## 多屏关卡设成关卡实际尺寸，视野跟着玩家走、到边就停。
@export var bounds: Rect2 = Rect2(0, 0, 640, 360)

## 最后一只怪倒下之后，再等这么多帧才判过关 —— 让掉落、飘字、后仰演完。
## 0.4 秒：够看清「最后一只倒了」，又不至于让人干等
const CLEAR_DELAY_FRAMES := 24
## 过关横幅停留多久（秒），然后开舆图
const BANNER_SEC := 1.3

var _cleared := false
var _enemy_total := 0
var _idle_frames := 0


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
	_enemy_total = _alive_enemies()
	# 没敌人的关卡不判过关（测试房间、剧情场景就是这种）。
	# 但**数据里本该有敌人却没有**是配置错误，要吭声 —— 静默的话，
	# 「这一关打完不解锁」会被当成玄学 bug 查半天
	if stage_data != null and _enemy_total == 0:
		push_warning("关卡「%s」里一只怪都没有：这一关永远不会被判过关。检查场景摆位"
			% str(stage_data.id))


func _physics_process(_delta: float) -> void:
	if _cleared or _enemy_total == 0 or stage_data == null:
		return
	if _alive_enemies() > 0:
		_idle_frames = 0
		return
	_idle_frames += 1
	if _idle_frames >= CLEAR_DELAY_FRAMES:
		_clear_stage()


## 本关还有几只活的怪。只数**本关卡的后代** —— 掉落物、飘字这些挂在
## current_scene 下，跨场景的组员也不该算进来
func _alive_enemies() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not is_inside_tree() or not is_ancestor_of(e):
			continue
		if e.has_method("is_alive") and not bool(e.call("is_alive")):
			continue
		n += 1
	return n


## 清空过关：记进度、给一次明确反馈、开舆图让玩家选去处。
##
## 「过关之后留在空关卡里」是死路（舆图只在安全区的舆图台前开），
## 所以这里的舆图**必须选一个去处**：J 进下一段、Esc 回安全区。
## 这条写进了 docs/design-conventions.md。
func _clear_stage() -> void:
	_cleared = true
	var pos := GameProgress.locate(stage_data.id)
	if pos.is_empty():
		push_error("关卡数据 %s 不在三层结构里 —— 无法解锁下一段" % str(stage_data.id))
		return
	var dungeon_id: StringName = pos["dungeon"]
	var index: int = pos["index"]
	var nxt := GameProgress.on_stage_cleared(dungeon_id, index)
	_show_cleared_banner(dungeon_id, index)
	# 不让舆图盖着横幅弹出来：先让玩家看清「这边打完了」
	await get_tree().create_timer(BANNER_SEC).timeout
	if not is_inside_tree():
		return                       # 这一秒里场景被切走了（回城 / 选关）
	_open_atlas(nxt)


## 过关横幅：一行字居中淡出。**一行**是有意的 ——
## 多行 Label 的行高约 19.5px，框开小了会压住下面的节点且引擎一声不吭
## （这个坑在对话框那轮踩过）。一行就不可能踩。
##
## 用的是世界坐标而不是屏幕坐标：单屏关卡相机不动，屏幕中心就是世界中心，
## 够用。真做多屏关卡时这里要改成 CanvasLayer
func _show_cleared_banner(dungeon_id: StringName, index: int) -> void:
	var m := GameProgress.map()
	var d := m.find_dungeon(dungeon_id) if m != null else null
	var place := tr(d.name_key) if d != null else ""
	var lbl := Label.new()
	lbl.z_index = 60
	lbl.text = "%s · %s　%s" % [
		place, I18n.t(&"UI_STAGE_LABEL", [index + 1]), tr("UI_STAGE_CLEARED")]
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.98, 0.87, 0.45))
	lbl.position = Vector2(bounds.position.x + bounds.size.x * 0.5 - 110.0,
		bounds.position.y + 120.0)
	add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(lbl.queue_free)


## 开舆图。舆图界面挂在玩家身上（与 HUD / 暂停菜单同一套挂法）
func _open_atlas(nxt: Dictionary) -> void:
	var atlas := get_node_or_null(PLAYER_PATH + "/Atlas")
	if atlas == null or not atlas.has_method("open_after_clear"):
		# 场景里没有舆图（测试房间、生成中的关卡）不是错误 ——
		# 但**过关了却没有任何去处**是，所以退化成一句警告
		push_warning("这个场景里没有舆图界面，过关后无处可去")
		return
	atlas.call("open_after_clear", nxt)


## 重开本关（死在本关时由 player 调用）。
##
## 「死在本关 → 重开本关」不回安全区、不掉进度（docs/adr/0009 §3）：
## 关卡是一屏，死了重来是最自然的规则，也免了「跑半张地图回去捡尸体」。
## 玩家的成长（等级 / 装备 / 精铁）住在 PlayerState，重载场景不会丢 ——
## 丢的只有这一关的世界状态，而那正是我们想重置的东西。
func restart() -> void:
	get_tree().reload_current_scene()


## 收集当前世界状态。结构：
##   player: { hp, x, y }
##   enemies: [ { node(相对路径), hp, x, y } ]   hp<=0 表示死着，恢复时走死亡态
func collect() -> Dictionary:
	var out := {"player": {}, "enemies": []}
	var player := get_node_or_null(PLAYER_PATH)
	if player != null:
		var h := player.get_node("Health") as Health
		var sp: Vector2 = player.call("spawn_point")
		out.player = {
			"hp": h.hp,
			"x": player.global_position.x,
			"y": player.global_position.y,
			# 复活点：踩过的 checkpoint 存在这里，读档后不会退回关卡开头
			"spawn_x": sp.x,
			"spawn_y": sp.y,
			"shards": int(player.get("shards")),
			"upgrade": int(player.get("upgrade_level")),
			"level": int(player.get("level")),
			"exp": int(player.get("exp_pts")),
			"mp": int(player.get("mp")),
			# 装备栏 / 背包的真相在 PlayerState（autoload），不在玩家节点上 ——
			# 这里只是把它抄进快照，读档时由 player.apply_saved 抄回去
			"equipped": PlayerState.equipped.duplicate(),
			"bag": PlayerState.bag.duplicate(),
			"skill_slots": PlayerState.skill_slots.duplicate(),
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
