extends Node2D
## 关卡根节点：**一个副本 = 一条多屏的路**。四件事：
##   1. **相机边界**（bounds）—— 多屏场景设成场景实际宽度，视野跟着玩家走
##   2. **收集 / 恢复世界快照** —— 「继续游戏 = 回到离开那一刻」的关卡侧实现
##   3. **分段推进** —— 清空当前屏的怪才开下一屏的闸门
##   4. **副本通关** —— 最后一屏清空 → 记进度 → 弹舆图
##
## ── 粒度（2026-09-14 神反馈后**重定**）──────────────────────
## 副本 = 一条 3~4 屏的路，**进一次从头打到尾**。屏是**场景里按 x 划出来的段**
## （`screen` 组里的 `Screen1`/`Screen2`/… 节点），不是独立场景。
##
## 第一版做成「一屏一个独立关卡、清完弹舆图选下一屏」，神玩完给了两条反馈：
##   · 「一关一屏不够，点进出频繁」
##   · 「每段两只怪不够打」
## 这一版是对那两条的回应：**一屏清空了只开闸门，不回舆图**；
## **整个副本打完（最后一屏清空）才弹舆图**。怪的密度也上去了，
## 因为一屏清空之前玩家只会面对这一屏的怪。
##
## ── 屏、闸门、通关，各自靠什么判定 ──────────────────────────
##   屏   = `screen` 组里的节点（按 x 排序），一屏的怪挂在它下面
##   闸门 = `screen_gate` 组里的节点（按 x 排序），第 i 道在屏 i 的右边界
##   清空 = 这一屏的分组下**活着**的怪为 0（按出生分组算，不按当前位置 ——
##          怪被引着跑到下一屏去，不该把上一屏判成"清了"）
##   通关 = 最后一屏清空
##
## **没有屏分组的场景不判推进**（测试房间、还没重切的 `level_2/3` 都是这样）：
## 它们只走相机与快照那两条老路。

const PLAYER_PATH := "Player"

## 「一屏」有多宽 = 视口宽。屏与闸门的 x 位置都按这个推
const SCREEN_WIDTH := 640.0

## 这一关属于哪个副本（`data/stages/dungeon_*.tres`）。
## **留空 = 这个场景不属于三层结构** —— 测试房间、还没重切的 `level_2/3`。
## 留空就只做相机与快照，不做任何推进或通关判定
@export var dungeon_data: DungeonData

## 相机活动范围（世界坐标）。多屏场景设成场景实际尺寸，视野跟着玩家走、到边就停。
@export var bounds: Rect2 = Rect2(0, 0, 640, 360)

## 最后一只怪倒下之后，再等这么多帧才判「这一屏清空了」——
## 让掉落、飘字、后仰演完。0.4 秒：够看清「最后一只倒了」，又不至于让人干等
const CLEAR_DELAY_FRAMES := 24
## 通关横幅停留多久（秒），然后弹舆图
const BANNER_SEC := 1.4

## 按 x 排序的屏分组
var _screens: Array[Node2D] = []
## 按 x 排序的闸门。第 i 道在屏 i 的右边界（所以比屏少一道）
var _gates: Array[Node2D] = []
## 第 i 屏清空了没有
var _open: Array[bool] = []
## 第 i 屏「最后一只倒下」之后的等待帧数
var _idle: Array[int] = []
## 玩家现在在第几屏（0 起）。HUD 上显示的屏号 = 这个 +1
var _current := 0
## 整个副本通关了没有（只触发一次）
var _cleared := false

var _banner_label: Label = null
var _banner_tween: Tween = null


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
	_collect_screens()
	_build_banner()
	if dungeon_data != null and _screens.is_empty():
		push_warning("副本「%s」的场景里没有 `screen` 分组：这一关永远不会推进、也不会通关"
			% str(dungeon_data.id))


## 收集屏分组与闸门，都按 x 排好。**只收本场景的后代** ——
## 组是全局的，别的场景的成员不该混进来
func _collect_screens() -> void:
	var scr: Array[Node2D] = []
	for n in get_tree().get_nodes_in_group("screen"):
		if is_instance_valid(n) and n is Node2D and is_ancestor_of(n):
			scr.append(n as Node2D)
	scr.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.x < b.global_position.x)
	_screens = scr

	var gs: Array[Node2D] = []
	for n in get_tree().get_nodes_in_group("screen_gate"):
		if is_instance_valid(n) and n is Node2D and is_ancestor_of(n):
			gs.append(n as Node2D)
	gs.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.x < b.global_position.x)
	_gates = gs

	_open.resize(_screens.size())
	_idle.resize(_screens.size())
	for i in _screens.size():
		_open[i] = false
		_idle[i] = 0


# ── 分段推进 ───────────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	_follow_screen()
	if _cleared or _screens.is_empty():
		return
	for i in _screens.size():
		if _open[i]:
			continue
		if _alive_in_screen(i) > 0:
			_idle[i] = 0
			continue
		_idle[i] += 1
		if _idle[i] >= CLEAR_DELAY_FRAMES:
			_screen_cleared(i)


## 屏号跟着玩家走：往右推进就 +1，往回走也会退回来（他确实在那儿）
func _follow_screen() -> void:
	if _screens.is_empty():
		return
	var p := get_node_or_null(PLAYER_PATH) as Node2D
	if p == null:
		return
	_current = clampi(int(p.global_position.x / SCREEN_WIDTH), 0, _screens.size() - 1)


## 这一屏还有几只活的怪。按**出生分组**算 —— 怪被引着跑到下一屏去，
## 不该把上一屏判成「已经清了」（按当前位置算就会出这个错）
func _alive_in_screen(i: int) -> int:
	if i < 0 or i >= _screens.size():
		return 0
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not _screens[i].is_ancestor_of(e):
			continue
		if e.has_method("is_alive") and not bool(e.call("is_alive")):
			continue
		n += 1
	return n


## 第 i 屏清空了。**最后一屏 = 副本通关**；其余只是开闸门放行，不回舆图
func _screen_cleared(i: int) -> void:
	_open[i] = true
	if i >= _screens.size() - 1:
		_on_dungeon_cleared()
		return
	_open_gate(i)
	_banner("%s　%s" % [
		I18n.t(&"UI_SCREEN_CLEARED", [i + 1]), tr("UI_SCREEN_ADVANCE")])


## 开第 i 道闸门：关掉碰撞 + 淡出视觉。
## **不能只淡出视觉** —— 玩家会一头撞上看不见的墙，那是最坏的一种静默失败
func _open_gate(i: int) -> void:
	if i < 0 or i >= _gates.size():
		return
	var g := _gates[i]
	var shape := g.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.disabled = true
	else:
		g.collision_layer = 0
	var vis := g.get_node_or_null("Visual") as CanvasItem
	if vis != null:
		var tw := vis.create_tween()
		tw.tween_property(vis, "modulate:a", 0.0, 0.45)
		tw.tween_callback(func() -> void: vis.visible = false)


## 副本通关：记进度（并拿到因此解锁的下一个副本）、给一句反馈、弹舆图
func _on_dungeon_cleared() -> void:
	_cleared = true
	var d := GameProgress.dungeon(dungeon_data.id)
	var place := tr(d.name_key) if d != null else ""
	var next_d := GameProgress.on_dungeon_cleared(dungeon_data.id)
	_banner("%s　%s" % [place, tr("UI_ATLAS_CLEARED")])
	# 不让舆图盖着横幅弹出来：先让玩家看清「这边打完了」
	await get_tree().create_timer(BANNER_SEC).timeout
	if not is_inside_tree():
		return                       # 这一秒里场景被切走了（回城 / 选关）
	_open_atlas(next_d)


## 开舆图。舆图界面挂在玩家身上（与 HUD / 暂停菜单同一套挂法）。
## 传进去的是**因此解锁的下一个副本**（没有就传 null），舆图会高亮它
func _open_atlas(next_d: DungeonData) -> void:
	var atlas := get_node_or_null(PLAYER_PATH + "/Atlas")
	if atlas == null or not atlas.has_method("open_after_clear"):
		# 场景里没有舆图（测试房间、生成中的关卡）不是错误 ——
		# 但**通关了却没有任何去处**是，所以退化成一句警告
		push_warning("这个场景里没有舆图界面，通关后无处可去")
		return
	atlas.call("open_after_clear", next_d)


# ── 横幅（屏幕坐标，不随相机跑）────────────────────────────────

## 横幅挂在 CanvasLayer 上而不是场景里 —— 多屏之后世界坐标会跟着相机跑，
## 一屏时代那种「把 Label 摆在世界中央」的写法在这里会飘到屏幕外
func _build_banner() -> void:
	if _banner_label != null:
		return
	var cl := CanvasLayer.new()
	cl.layer = 40
	add_child(cl)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.98, 0.87, 0.45))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(0.0, 92.0)
	lbl.size = Vector2(SCREEN_WIDTH, 26.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.modulate.a = 0.0
	cl.add_child(lbl)
	_banner_label = lbl


## 一行字，停一下再淡出。**一行**是有意的 ——
## 多行 Label 的行高约 19.5px，框开小了会压住下面的节点且引擎一声不吭
func _banner(text: String) -> void:
	if _banner_label == null:
		return
	_banner_label.text = text
	_banner_label.modulate.a = 1.0
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = _banner_label.create_tween()
	_banner_tween.tween_interval(1.1)
	_banner_tween.tween_property(_banner_label, "modulate:a", 0.0, 0.5)


# ── 给外面看的（HUD / 断言）────────────────────────────────────

## 当前屏号（**1 起**，给人看的）
func current_screen() -> int:
	return _current + 1


## 共几屏（以场景里实际摆的为准）
func screen_count() -> int:
	return _screens.size()


## 第 i 屏（0 起）放行了没有
func is_screen_cleared(i: int) -> bool:
	return i >= 0 and i < _open.size() and _open[i]


## 整个副本通关了没有
func is_dungeon_cleared() -> bool:
	return _cleared


# ── 重开 / 快照 ────────────────────────────────────────────────

## 重开本副本（死在里面时由 player 调用）。
##
## 「死在副本里 → 重开副本」不回安全区、不掉进度（docs/adr/0009 §3）：
## 玩家的成长（等级 / 装备 / 精铁）住在 PlayerState，重载场景不会丢 ——
## 丢的只有这一趟的路（清空的屏、走过的位置），而那正是要重置的东西。
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
