class_name Stage
extends Node2D
## 关卡根节点：**一个副本 = 一条多屏的路**。它负责五件事：
##   1. **相机边界**（bounds）—— 设成场景实际宽度，视野跟着玩家平滑滚动
##   2. **分段推进** —— 这一屏的怪没清完，右边**过不去**
##   3. **分批出怪（波次）** —— 一屏分几批，打完一批才来下一批
##   4. **副本通关** —— 最后一屏清空 → 记进度 → 弹舆图
##   5. **收集 / 恢复世界快照** —— 「继续游戏 = 回到离开那一刻」的关卡侧实现
##
## ── 粒度（2026-09-14 神两轮反馈后**重定**）──────────────────
## 第一版：一屏一个独立关卡，进一次打一屏，清完弹舆图选下一屏。
## 神玩完否掉：「一关一屏不够，点进出频繁」「每段两只怪不够打」。
## 第二版：副本 = 一条三屏的路，清一屏开一道**暗红闸门**。
## 神又否掉三条（原话记在 docs/adr/0009 §1）：
##   · 「每一屏幕长度不够长」          → 屏宽 640 → **960**（相机跟着走）
##   · 「不同屏之间过渡太生硬，不需要闸门去隔离」
##        → **删掉可见闸门**，改成关卡根节点动态建的**看不见的挡墙**：
##          一屏没清完，走到最右侧就是走不过去（造梦西游的做法）。
##          撞上去才给一句提示 —— 不静默。
##   · 「一屏 3 只不够，要分批次出：打死一批接着来第二批」
##        → **波次**：屏下挂 `wave` 分组的容器，一批全灭才出下一批。
##
## ── 屏、波、挡墙，各自靠什么判定 ────────────────────────────
##   屏   = `screen` 组里的节点（按 x 排序），一屏的波挂在它下面
##   波   = 某一屏下 `wave` 组的子节点（**按声明顺序** = 出场顺序）
##   挡墙 = 本节点**动态建**的，第 i 道在屏 i 的右边界（所以比屏少一道）
##   清一波 = 这一波里活着的怪为 0（休眠中的不算 —— 它们还没出场）
##   清一屏 = 这一屏的最后一波也清了
##   通关   = 最后一屏清空
##
## **没有屏分组的场景不判推进**（测试房间、还没重切的 `level_2/3` 都是这样）：
## 它们只走相机与快照那两条老路。

const PLAYER_PATH := "Player"

## 「一屏」有多宽。
## 它比视口宽（640）—— 这是**刻意的**：一屏 = 一个半视口，玩家在一屏里
## 能真的"走一段路"，相机跟着滚，屏与屏之间是连续的滚动而不是瞬移。
const SCREEN_WIDTH := 960.0

## 挡墙：宽 8px 的竖片，高得能封死整屏（含浮台与跳跃高度）
const BARRIER_W := 8.0
const BARRIER_H := 480.0
## 玩家离挡墙多近才算"撞上了"（用来出提示）
const BARRIER_HINT_DIST := 20.0
## 撞墙提示的最小间隔（帧）：贴在墙上不动也不会刷屏
const HINT_COOLDOWN_FRAMES := 150

## 这一关属于哪个副本（`data/stages/dungeon_*.tres`）。
## **留空 = 这个场景不属于三层结构** —— 测试房间、还没重切的 `level_2/3`。
@export var dungeon_data: DungeonData

## 相机活动范围（世界坐标）。设成场景实际尺寸，视野跟着玩家走、到边就停。
@export var bounds: Rect2 = Rect2(0, 0, 960, 360)

@export_group("观感")
## 背景主题（手写场景用：城镇 = town）。副本走 dungeon_data.backdrop，优先于这里
@export var backdrop_theme: StringName = &""

## 一波里最后一只倒之后，再等这么多帧才判「这一波清了」——
## 让掉落、飘字、后仰演完
const CLEAR_DELAY_FRAMES := 24
## 两波之间的间隔帧数。**太短会让人以为是同一波**，太长会让房间空着没人知道下一步。
## 0.75 秒：够看清"这批没了"，下一批刚好淡入
const WAVE_GAP_FRAMES := 45
## 新一波出场时怪淡入的时长（秒）
const SPAWN_FADE_SEC := 0.28
## 通关横幅停留多久（秒），然后弹舆图
const BANNER_SEC := 1.4

## 按 x 排序的屏分组
var _screens: Array[Node2D] = []
## 第 i 屏的波次容器，按声明顺序
var _waves: Array[Array] = []
## 第 i 屏的挡墙（最后一道是 null —— 最后一屏右边没有下一屏）
var _barriers: Array[Node2D] = []

## 第 i 屏的怪出场了没有（玩家走到过那一屏）
var _started: Array[bool] = []
## 第 i 屏清空了没有
var _done: Array[bool] = []
## 第 i 屏已经清掉几波
var _waves_done: Array[int] = []
## 第 i 屏当前挂着的是第几波（-1 = 没有在场上的波）
var _active: Array[int] = []
## 第 i 屏「这一波最后一只倒下」之后的等待帧数
var _idle: Array[int] = []
## 第 i 屏两波之间的间隔倒计时
var _gap: Array[int] = []

## 玩家现在在第几屏（0 起）。HUD 上显示的屏号 = 这个 +1
var _current := 0
## 整个副本通关了没有（只触发一次）
var _cleared := false
## 撞墙提示的冷却
var _hint_cooldown := 0

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
	_build_backdrop()
	_collect_screens()
	_build_barriers()
	# 进图登记（还魂丹的「进图补给 / 每图限购」以此为准）。
	# 只在真副本里发 —— 测试房间没有 dungeon_data，不该动补给账
	if dungeon_data != null:
		GameProgress.enter_dungeon(dungeon_data.id)
	_build_banner()
	_sleep_all()
	if dungeon_data != null and _screens.is_empty():
		push_warning("副本「%s」的场景里没有 `screen` 分组：这一关永远不会推进、也不会通关"
			% str(dungeon_data.id))
	# 快照恢复**必须在屏与波都建好之后** —— 它要把某一屏的某一波摆出来
	var st := SaveManager.take_pending_state()
	if not st.is_empty():
		_apply_state(st)


## 收集屏分组，并按 x 排好；每屏再把它的波收进来（保持声明顺序）。
## **只收本场景的后代** —— 组是全局的，别的场景的成员不该混进来
func _collect_screens() -> void:
	var scr: Array[Node2D] = []
	for n in get_tree().get_nodes_in_group("screen"):
		if is_instance_valid(n) and n is Node2D and is_ancestor_of(n):
			scr.append(n as Node2D)
	scr.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.x < b.global_position.x)
	_screens = scr

	_waves.clear()
	for s in _screens:
		var ws: Array = []
		# 按**子节点顺序**收，不用 get_nodes_in_group —— 组的顺序不保证，
		# 而波次的出场顺序正是声明顺序，乱掉就是"第三批先出来"
		for child in s.get_children():
			if child.is_in_group("wave"):
				ws.append(child)
		_waves.append(ws)

	var n := _screens.size()
	_started.resize(n)
	_done.resize(n)
	_waves_done.resize(n)
	_active.resize(n)
	_idle.resize(n)
	_gap.resize(n)
	for i in n:
		_started[i] = false
		_done[i] = false
		_waves_done[i] = 0
		_active[i] = -1
		_idle[i] = 0
		_gap[i] = 0


## 屏与屏之间那道**看不见的**墙。
##
## 为什么不摆进场景：一是位置必须跟着 SCREEN_WIDTH 走（改一次屏宽要重摆所有墙，
## 迟早对不上），二是**它能被误当成装饰**。这里动态建，位置永远只有一个来源。
##
## 层取地形层（4）：玩家与怪都撞得到 —— 怪也出不去，它本来就该待在这一屏里。
## 背景：天空 + 远景 + 中景（两层视差）。副本按数据、手写场景按 backdrop_theme
func _build_backdrop() -> void:
	var theme_name: StringName = &""
	if dungeon_data != null:
		theme_name = dungeon_data.backdrop
	if String(theme_name).is_empty():
		theme_name = backdrop_theme
	if String(theme_name).is_empty():
		return
	if not ResourceLoader.exists("res://assets/backgrounds/%s/sky.png" % theme_name):
		push_warning("背景主题「%s」没有资源，跳过" % theme_name)
		return
	var bd: Node2D = preload("res://scripts/core/backdrop.gd").new()
	bd.name = "Backdrop"
	bd.theme = theme_name
	add_child(bd)
	move_child(bd, 0)


func _build_barriers() -> void:
	_barriers.clear()
	for i in range(maxi(_screens.size() - 1, 0)):
		var b := StaticBody2D.new()
		b.name = "Barrier%d" % (i + 1)
		b.collision_layer = 4
		b.collision_mask = 0
		var cs := CollisionShape2D.new()
		# **名字要显式给**：`CollisionShape2D.new()` 加进树时 Godot 会自动起
		# `@CollisionShape2D@N` 这种名字，`get_node_or_null("CollisionShape2D")` 找不到它。
		# 这一条踩过：断言拿不到碰撞体，于是"实心"判成了 false，而人其实被挡在那儿
		cs.name = "CollisionShape2D"
		var sh := RectangleShape2D.new()
		sh.size = Vector2(BARRIER_W, BARRIER_H)
		cs.shape = sh
		b.add_child(cs)
		b.position = Vector2(float(i + 1) * SCREEN_WIDTH, bounds.position.y + bounds.size.y * 0.5)
		add_child(b)
		_barriers.append(b)

	

# ── 推进 ───────────────────────────────────────────────────────

## 开场：**所有怪先睡下**，谁出场由推进状态决定。
##
## 不先睡一遍的话，场景加载的那一帧三十几只怪全醒着 —— 它们会在自己的屏里
## 巡逻、隔着一整个屏幕"看见"玩家、然后集体走过来。玩家开局的第一个画面
## 就是被一整个副本的怪围住
func _sleep_all() -> void:
	for s in _screens:
		for e in s.get_children():
			if e.has_method("set_dormant"):
				e.call("set_dormant", true)
	for ws in _waves:
		for w in ws:
			for e in (w as Node).get_children():
				if e.has_method("set_dormant"):
					e.call("set_dormant", true)


func _physics_process(_delta: float) -> void:
	_follow_screen()
	if _hint_cooldown > 0:
		_hint_cooldown -= 1
	_check_barrier_hint()
	if _cleared or _screens.is_empty():
		return
	for i in _screens.size():
		_step_screen(i)


## 屏号跟着玩家走：往右推进就 +1，往回走也会退回来（他确实在那儿）。
## 顺便把「走到过的屏」标成已开场 —— 怪从这一刻起才存在
func _follow_screen() -> void:
	if _screens.is_empty():
		return
	var p := get_node_or_null(PLAYER_PATH) as Node2D
	if p == null:
		return
	_current = clampi(int(p.global_position.x / SCREEN_WIDTH), 0, _screens.size() - 1)
	for i in range(mini(_current + 1, _screens.size())):
		_started[i] = true


## 一屏的状态机：出下一波 → 等它被清空 → 再出下一波 → … → 这一屏清了。
## 拆成单独一个函数是为了让"一屏"的内部节奏一眼看得完
func _step_screen(i: int) -> void:
	if not _started[i] or _done[i]:
		return
	if _gap[i] > 0:
		_gap[i] -= 1
		return
	var waves: Array = _waves[i]
	if _active[i] < 0:
		if _waves_done[i] >= waves.size():
			_screen_cleared(i)
			return
		_activate_wave(i, _waves_done[i])
		return
	if _alive_in_wave(i, _active[i]) > 0:
		_idle[i] = 0
		return
	_idle[i] += 1
	if _idle[i] >= CLEAR_DELAY_FRAMES:
		_waves_done[i] = _active[i] + 1
		_active[i] = -1
		_idle[i] = 0
		_gap[i] = WAVE_GAP_FRAMES


## 把第 i 屏的第 w 波放出来。休眠中的怪在这里"活过来"：
## 恢复处理 / 碰撞 / 回到 enemy 组，再淡入 —— 一批怪凭空出现要有过程，
## 直接闪出来会让人以为是卡了一帧
func _activate_wave(i: int, w: int) -> void:
	if i < 0 or i >= _waves.size() or w < 0 or w >= _waves[i].size():
		return
	var node: Node = _waves[i][w]
	for e in node.get_children():
		if e.has_method("set_dormant"):
			e.call("set_dormant", false)
		if e is CanvasItem:
			var ci := e as CanvasItem
			ci.modulate.a = 0.0
			var tw := ci.create_tween()
			tw.tween_property(ci, "modulate:a", 1.0, SPAWN_FADE_SEC)
	_active[i] = w
	_idle[i] = 0


## 这一波还有几只活的。**按容器归属算，不按当前位置** ——
## 怪被引着跑到隔壁去，不该把这一波判成"清了"。
## 休眠中的怪已经退出 `enemy` 组，所以这里天然数不到它们
func _alive_in_wave(i: int, w: int) -> int:
	if i < 0 or i >= _waves.size() or w < 0 or w >= _waves[i].size():
		return 0
	var node: Node = _waves[i][w]
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not node.is_ancestor_of(e):
			continue
		if e.has_method("is_alive") and not bool(e.call("is_alive")):
			continue
		n += 1
	return n


## 第 i 屏清空了。**最后一屏 = 副本通关**；其余只是放行，不回舆图
func _screen_cleared(i: int) -> void:
	_done[i] = true
	if i >= _screens.size() - 1:
		_on_dungeon_cleared()
		return
	_open_barrier(i)
	_banner("%s　%s" % [I18n.t(&"UI_SCREEN_CLEARED", [i + 1]), tr("UI_SCREEN_ADVANCE")])


## 拆掉第 i 道挡墙。**它本来就是看不见的**，所以只有关碰撞这一件事可做 ——
## 忘掉这一步就是"撞上一堵看不见的墙"，最坏的一种静默失败
func _open_barrier(i: int) -> void:
	if i < 0 or i >= _barriers.size():
		return
	var b := _barriers[i]
	if b == null:
		return
	for c in b.get_children():
		if c is CollisionShape2D:
			(c as CollisionShape2D).disabled = true
	b.collision_layer = 0


## 撞上还没拆的挡墙时给一句人话。
## 挡墙是看不见的 —— 不给提示，玩家只会觉得"这里卡住了"（机器不报错，人就只能猜）
func _check_barrier_hint() -> void:
	if _hint_cooldown > 0 or _barriers.is_empty():
		return
	var p := get_node_or_null(PLAYER_PATH) as Node2D
	if p == null:
		return
	for i in _barriers.size():
		var b := _barriers[i]
		if b == null or b.collision_layer == 0:
			continue
		if absf(p.global_position.x - b.global_position.x) < BARRIER_HINT_DIST:
			_banner(tr("UI_SCREEN_BLOCKED"))
			_hint_cooldown = HINT_COOLDOWN_FRAMES
			return


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
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.modulate.a = 0.0
	lbl.position = Vector2(0.0, 86.0)
	cl.add_child(lbl)
	# 宽度**跟着视口**（而不是写死屏宽）：屏比视口宽，写 SCREEN_WIDTH 会让字
	# 居中到屏幕外。
	# **别改成锚点**（set_anchors_preset）：父节点是 CanvasLayer，不是 Control，
	# 锚点在这条路径上不生效 —— 实测框宽会停在 0，字从左边溢出屏幕（拍出来了才看见）
	# 提示条走统一面板样式（原先是一行裸字，和面板不是一套语言）
	lbl.add_theme_stylebox_override("normal", load("res://assets/ui/banner_style.tres"))
	lbl.size = Vector2(get_viewport().get_visible_rect().size.x, 34.0)
	_banner_label = lbl


## 一行字，停一下再淡出。**一行**是有意的 ——
## 多行 Label 的行高约 19.5px，框开小了会压住下面的节点且引擎一声不吭
func _banner(text: String) -> void:
	if _banner_label == null:
		return
	# 每写一次就校一次宽度：窗口大小与拉伸模式都可能变，"居中的那行字"
	# 一旦框宽不对就会跑到屏幕外，而且不报错
	_banner_label.size = Vector2(get_viewport().get_visible_rect().size.x, 34.0)   # 面板样式要 34 高
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
	return i >= 0 and i < _done.size() and _done[i]


## 第 i 屏有几波
func screen_wave_count(i: int) -> int:
	if i < 0 or i >= _waves.size():
		return 0
	return _waves[i].size()


## 第 i 屏已经清掉几波
func waves_done(i: int) -> int:
	if i < 0 or i >= _waves_done.size():
		return 0
	return _waves_done[i]


## 第 i 屏场上挂着的是第几波（-1 = 没有）。0 起
func active_wave(i: int) -> int:
	if i < 0 or i >= _active.size():
		return -1
	return _active[i]


## 第 i 道挡墙拆了没有
func barrier_open(i: int) -> bool:
	if i < 0 or i >= _barriers.size():
		return true
	var b := _barriers[i]
	return b == null or b.collision_layer == 0


## 第 i 道挡墙的节点（断言要拿它的位置）
func barrier_node(i: int) -> Node2D:
	if i < 0 or i >= _barriers.size():
		return null
	return _barriers[i]


## 整个副本通关了没有
func is_dungeon_cleared() -> bool:
	return _cleared


# ── 重开 / 快照 ────────────────────────────────────────────────

## 重开本副本（死亡界面的「重新开始」调它）。
##
## 「死在副本里 → 重开副本」不回安全区、不掉进度（docs/adr/0009 §3）：
## 玩家的成长（等级 / 装备 / 精铁）住在 PlayerState，重载场景不会丢 ——
## 丢的只有这一趟的路（清空的屏、走过的位置），而那正是要重置的东西。
func restart() -> void:
	get_tree().reload_current_scene()


## 收集当前世界状态。结构：
##   player:  { hp, x, y, … }
##   enemies: [ { node(相对路径), hp, x, y } ]   只含**当前在场**的那一波
##   screens: { started, waves_done, done }      推进到哪了
## 休眠中的怪不进 enemies —— 它们还没出场，读档时由 screens 决定该出现哪一波
func collect() -> Dictionary:
	var out := {"player": {}, "enemies": [], "screens": {}}
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
			"shards": PlayerState.shards,
			"gold": PlayerState.gold,
		"character_id": PlayerState.character_id,
			"level": int(player.get("level")),
			"exp": int(player.get("exp_pts")),
			"mp": int(player.get("mp")),
			# 装备栏 / 背包 / 强化表的真相在 PlayerState（autoload），不在玩家节点上 ——
			# 这里只是把它抄进快照，读档时由 player.apply_saved 抄回去
			"equipped": PlayerState.equipped.duplicate(),
			"bag": PlayerState.bag.duplicate(),
			"forge": PlayerState.forge.duplicate(),
			"next_uid": PlayerState.next_uid,
			"skill_slots": PlayerState.skill_slots.duplicate(),
		}
	out.screens = {
		"started": _started.duplicate(),
		"waves_done": _waves_done.duplicate(),
		"done": _done.duplicate(),
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
	var scr := st.get("screens", {}) as Dictionary
	if not scr.is_empty():
		_restore_screens(scr)
	var player := get_node_or_null(PLAYER_PATH)
	if player != null and st.has("player"):
		if player.has_method("apply_saved"):
			player.call("apply_saved", st.player)
	# 血量放在波次之后恢复：先让该出场的那一波站好，再按快照摆它们的血量位置
	for d in st.get("enemies", []):
		var e := get_node_or_null(NodePath(str(d.get("node", ""))))
		if e != null and e.has_method("apply_saved"):
			e.call("apply_saved", d)


## 某个节点所在副本的**敌人攻击倍率**（`DungeonData.enemy_atk_scale`）。
##
## ── 为什么由敌人反查，而不是关卡主动注入 ─────────────────────
## 敌人的 `_ready` **早于**关卡根节点的 `_ready`（Godot 里子节点先 ready），
## 注入会晚一步；而 `dungeon_data` 是场景里已经反序列化好的 `@export` 值，
## 向上找随时都读得到。**取不到就返回 1.0** —— 测试房间、独立场景、
## 还没重切的场景本来就没有副本语境，那里不该按别的副本的倍率打人
static func atk_scale_for(node: Node) -> float:
	var n: Node = node.get_parent()
	while n != null:
		if n is Stage:
			var d := (n as Stage).dungeon_data
			return 1.0 if d == null else d.enemy_atk_scale
		n = n.get_parent()
	return 1.0
func _restore_screens(scr: Dictionary) -> void:
	var started: Array = scr.get("started", [])
	var done: Array = scr.get("done", [])
	var wdone: Array = scr.get("waves_done", [])
	for i in _screens.size():
		_started[i] = bool(started[i]) if i < started.size() else false
		_done[i] = bool(done[i]) if i < done.size() else false
		_waves_done[i] = int(wdone[i]) if i < wdone.size() else 0
		_active[i] = -1
		_idle[i] = 0
		_gap[i] = 0
		if _done[i]:
			_open_barrier(i)          # 已经清掉的屏：路本来就是通的
			continue
		if not _started[i]:
			continue
		if _waves_done[i] < _waves[i].size():
			_activate_wave(i, _waves_done[i])
