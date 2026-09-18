extends Node
## 《百炼》自动验收：**Boss 相位机制**（ADR-0019 的 B 口径 · ADR-0023）。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m19.tscn
##
## ── 这一组为什么必须存在 ────────────────────────────────────────
## ADR-0019 给 Boss 定血量时用的是这个公式：
##     `hp_boss_B = 等效DPS × UPTIME(0.55) × boss_active × 目标秒数`
## 那个 `boss_active`（ch1 0.85 → ch5 0.65）**假设玩家有一段时间打不到它**。
## 在这条机制落地之前，那个假设是空的 —— 于是 Boss 会比设计早死 15%~35%，
## **而任何断言都不会红**（没有谁在测「这场仗本来该打多久」）。
##
## 所以要盯三件事：
##   · **数据与设计表对齐**：`phase_ratio() == 1 - boss_active`（1 组）
##   · **机制真的成立**：相位期间无敌、有反馈、打不断、恢复段可反击（2、3 组）
##   · **玩家有得学**：带相位的 Boss 之前，必须先出现过带相位的怪（4 组，原则 2.5）
##
## ⚠️ 「打不动」有两种，返回值都是 0，所以**只断言 0 是不够的**：
##   · 相位的硬无敌 → 必须发 `Health.blocked`（玩家得知道这一下被挡了）
##   · 受击后的无敌窗口（0.10s）→ 安静（同一次挥砍的第 2~4 帧）
## 2 组因此同时断言「返回 0」与「收到了 blocked」。

const ROOM := preload("res://scenes/stages/test_room.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/boss.tscn")
const BOSS_DATA := preload("res://data/enemies/boss.tres")

## 设计表 `enemy_scaling.csv` 的 `boss_active` 换算成「打不到的占比」。
## **这里写死是有意的**：断言必须独立于被测的东西 —— 改数据不改设计表，
## 这一组就该红（与 test_m13 #12 盯副本攻击倍率同一条道理）
const WANT_RATIO := {
	"boss": 0.15, "boss2": 0.15, "boss_luhou": 0.15,
	"boss_canjian": 0.20, "boss_xiushi": 0.20, "boss_zhongxin": 0.20,
}
## 取整带来的误差
const RATIO_TOL := 0.01

## 砺场免除「教学」这一条：它是**全游戏第一课**，玩家那时还在学「打一下、闪一下」，
## 而且它的相位是最轻的一档（占比 0.15、原地不动）。**显式列出来，不静默豁免** ——
## 以后有第三个副本漏了教学，这一组会直接报出来
const TEACH_EXEMPT := ["lichang"]

var _pass := 0
var _fail := 0
var _room: Node = null


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》Boss 相位机制自动验收 ═══")

	_t1_data_matches_design()

	_room = ROOM.instantiate()
	add_child(_room)
	_quiet(_room)
	await _pframes(2)

	await _t2_phase_shape()
	await _t3_data_driven()
	await _t4_teaching_coverage()
	await _t5_spark_premises()

	print("")
	if _fail == 0:
		print("═══ %d 通过 ／ 0 失败 ═══" % _pass)
	else:
		print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().quit()


# ── 1. 数据与设计表对齐（不看场景）────────────────────────────

func _t1_data_matches_design() -> void:
	var bad_r := []
	var missing := []
	for id in WANT_RATIO:
		var p := "res://data/enemies/%s.tres" % id
		if not ResourceLoader.exists(p):
			missing.append(id)
			continue
		var d: EnemyData = load(p)
		if d == null or not d.has_phase():
			missing.append("%s(无相位)" % id)
			continue
		if absf(d.phase_ratio() - float(WANT_RATIO[id])) > RATIO_TOL:
			bad_r.append("%s: %.3f≠%.2f" % [id, d.phase_ratio(), WANT_RATIO[id]])
	_check("1a", "6 只 Boss 的相位占比 = 1 − boss_active（ADR-0019）",
		missing.is_empty() and bad_r.is_empty(),
		"缺失: %s ／ 偏差: %s" % [
			str(missing) if not missing.is_empty() else "无",
			str(bad_r) if not bad_r.is_empty() else "无"])

	# 小怪不许有相位 —— 时长预算是按 Boss / 精英算的，
	# 给小怪加相位会毁掉「一批怪打多久」的手感（四级怪手感是 M3 验收过的）
	var trash := []
	var dir := DirAccess.open("res://data/enemies")
	if dir != null:
		for fn in dir.get_files():
			if not fn.ends_with(".tres"):
				continue
			var d: EnemyData = load("res://data/enemies/" + fn)
			if d != null and d.kind == &"trash" and d.has_phase():
				trash.append(fn)
	_check("1b", "小怪一律没有相位（时长预算只算 Boss / 精英）", trash.is_empty(),
		"有相位的小怪: %s" % (str(trash) if not trash.is_empty() else "无"))

	# 教学怪必须是「短 + 原地」：它要教的是「打不动这件事存在」，
	# 不是「怎么追后撤的 Boss」—— 后者留给 Boss 自己
	var teach_bad := []
	for id in ["walker_elite", "brute_heavy"]:
		var d: EnemyData = load("res://data/enemies/%s.tres" % id)
		if d == null or not d.has_phase():
			teach_bad.append("%s(无相位)" % id)
			continue
		if d.phase_frames > 60 or d.phase_move != EnemyData.PhaseMove.STILL:
			teach_bad.append("%s(%d 帧/位移 %d)" % [id, d.phase_frames, int(d.phase_move)])
	_check("1c", "教学精英：短相位（≤1s）+ 原地不位移", teach_bad.is_empty(),
		"异常: %s" % (str(teach_bad) if not teach_bad.is_empty() else "无"))


# ── 2. 三段形态（真跑 AI）──────────────────────────────────────

func _t2_phase_shape() -> void:
	# 测试用的参数：帧数调小才好断言，但**结构一个不少**（架势/相位/间隔/恢复）
	var d: EnemyData = BOSS_DATA.duplicate()
	d.phase_warn_frames = 8
	d.phase_frames = 30
	d.phase_interval_frames = 20
	d.phase_recover_frames = 12
	d.phase_move = EnemyData.PhaseMove.STILL

	var boss := _spawn(d, Vector2(200.0, 300.0))
	var player := _dummy_player(Vector2(330.0, 300.0))
	var h: Health = boss.get_node("Health")
	var blocked := [0]
	h.blocked.connect(func(_p: Vector2, _dir: int) -> void: blocked[0] += 1)

	# 走到「架势」那一帧：phases_started 从 0 变 1
	var warn_seen := false
	var warn_hittable := false
	var shield_rising := false
	for _i in 90:
		await get_tree().physics_frame
		if int(boss.get("phases_started")) < 1:
			continue
		if boss.call("is_phasing"):
			break
		if not warn_seen:
			warn_seen = true
			# 架势**仍然可以打**：这是给反应快的玩家的窗口，也是「读招」的物理形状
			var dealt := h.take_damage(10, Vector2.ZERO, false, 1)
			warn_hittable = dealt > 0
			shield_rising = float(boss.call("shield_ratio")) > 0.0
	_check("2a", "架势段：起手后仍然可打（不是一上来就无敌）", warn_seen and warn_hittable,
		"看到架势=%s ／ 打上去掉了 %s" % [str(warn_seen), "血" if warn_hittable else "**0（错）**"])

	# 进相位：无敌 + 护罩满
	var in_phase := false
	for _i in 90:
		if boss.call("is_phasing"):
			in_phase = true
			break
		await get_tree().physics_frame
	var inv := bool(h.invincible)
	_check("2b", "相位段：无敌（is_phasing 且 Health.invincible）", in_phase and inv,
		"is_phasing=%s ／ invincible=%s" % [str(in_phase), str(inv)])

	# 等受击无敌窗口（0.10s）过去，否则下面那次 take_damage 返回 0 是因为上一击，
	# 而不是因为无敌 —— 那正是「只断言 0 不够」的原因
	await _pframes(8)
	blocked[0] = 0
	var dealt_p := h.take_damage(10, Vector2.ZERO, false, 1)
	_check("2c", "相位段：打上去 0 伤害，且发出 blocked（不静默）",
		dealt_p == 0 and blocked[0] == 1,
		"伤害=%d ／ blocked 次数=%d（期望 1）" % [dealt_p, blocked[0]])

	# 打它不取消相位（进了 HURT 就说明被取消了）
	var still := bool(boss.call("is_phasing")) or int(boss.get("state")) == 7
	_check("2d", "相位不被打断（远程角色不能靠输出取消它）", still,
		"打完一帧后 is_phasing=%s ／ state=%d（7=恢复段）" % [
			str(boss.call("is_phasing")), int(boss.get("state"))])

	# 恢复段：无敌解除、能打出伤害（这是读招成功的奖励窗口）
	var recovered := false
	var recover_hittable := false
	for _i in 60:
		await get_tree().physics_frame
		if not bool(h.invincible) and not boss.call("is_phasing"):
			recovered = true
			await _pframes(8)          # 同样要等过受击窗口
			recover_hittable = h.take_damage(10, Vector2.ZERO, false, 1) > 0
			break
	_check("2e", "恢复段：无敌解除，且这是可反击窗口", recovered and recover_hittable,
		"进入恢复=%s ／ 能打出伤害=%s" % [str(recovered), str(recover_hittable)])

	# 循环：一轮走完要回到能再起手的状态
	var before := int(boss.get("phases_started"))
	var looped := false
	for _i in 200:
		await get_tree().physics_frame
		if int(boss.get("phases_started")) > before:
			looped = true
			break
	_check("2f", "相位会循环（不是只放一次）", looped,
		"起手次数 %d → %d" % [before, int(boss.get("phases_started"))])

	# 收尾：护罩在相位结束后要收掉 —— 留着一个永远亮着的环是「静默的错」
	for _i in 60:
		await get_tree().physics_frame
		if float(boss.call("shield_ratio")) <= 0.0:
			break
	_check("2g", "相位结束后护罩收干净（不留一个永远亮着的环）",
		float(boss.call("shield_ratio")) <= 0.0,
		"shield_ratio=%.2f" % float(boss.call("shield_ratio")))

	player.queue_free()
	boss.queue_free()


# ── 3. 数据驱动：改 .tres 就得改行为 ──────────────────────────

func _t3_data_driven() -> void:
	# 「改资源的字段，结果必须跟着变」—— 不这么写的话，代码里偷偷留一份
	# 硬编码的相位参数也照样全绿（与 test_m10 验成长曲线同一条纪律）
	var fast: EnemyData = BOSS_DATA.duplicate()
	fast.phase_warn_frames = 4
	fast.phase_frames = 10
	fast.phase_interval_frames = 4
	fast.phase_recover_frames = 6
	var slow: EnemyData = BOSS_DATA.duplicate()
	slow.phase_warn_frames = 4
	slow.phase_frames = 10
	slow.phase_interval_frames = 60   # 只把间隔拉长 15 倍
	slow.phase_recover_frames = 6

	var e1 := _spawn(fast, Vector2(200.0, 300.0))
	var e2 := _spawn(slow, Vector2(200.0, 300.0))
	_dummy_player(Vector2(330.0, 300.0))
	await _pframes(120)
	var n1 := int(e1.get("phases_started"))
	var n2 := int(e2.get("phases_started"))
	_check("3a", "改 .tres 的相位间隔 → 起手次数跟着变（数据驱动）", n1 > n2,
		"间隔 4 帧的放了 %d 次 ／ 间隔 60 帧的放了 %d 次" % [n1, n2])
	var fd: EnemyData = e1.get("data")
	_check("3b", "相位占比由 data 算出来（phase_ratio 与周期一致）",
		absf(fd.phase_ratio() - 10.0 / 18.0) < 0.001,
		"phase_ratio=%.3f（10/(4+10+4)=%.3f）" % [fd.phase_ratio(), 10.0 / 18.0])
	e1.queue_free()
	e2.queue_free()


# ── 4. 教学覆盖（原则 2.5 四步法）──────────────────────────────

func _t4_teaching_coverage() -> void:
	var report := []
	var bad := []
	for d in GameProgress.sequence():
		if str(d.id) in TEACH_EXEMPT:
			report.append("%s(豁免)" % d.id)
			continue
		if not d.is_ready():
			continue
		var lv: Node = load(d.scene_path).instantiate()
		add_child(lv)
		_quiet(lv)
		await _pframes(2)
		var screens := _screens(lv)
		# 两趟：先找 Boss 在哪一屏，再看它**之前**的屏里有没有带相位的怪。
		# 一趟做不完 —— 边走边判的话，走到 Boss 那屏时「之前」的那些已经过去了
		var boss_screen := -1
		var phased_screen := {}          # 屏号 → 这一屏有没有带相位的怪
		for i in screens.size():
			for w in _waves(screens[i]):
				for e in w.get_children():
					if not e.has_method("is_alive"):
						continue
					var ed: EnemyData = e.get("data")
					if ed == null:
						continue
					if ed.kind == &"boss":
						boss_screen = i
					if ed.has_phase():
						phased_screen[i] = true
		var taught := false
		for i in phased_screen:
			if boss_screen >= 0 and i < boss_screen:
				taught = true
		var ok := boss_screen >= 0 and taught
		if not ok:
			bad.append("%s(Boss 在第 %d 屏)" % [d.id, boss_screen + 1])
		report.append("%s:%s" % [d.id, "✅" if ok else "❌"])
		lv.queue_free()

	_check("4a", "带相位的 Boss 之前，先出现过带相位的怪（原则 2.5）", bad.is_empty(),
		"逐副本: %s" % " ".join(PackedStringArray(report)))


# ── 5. 命中火花的两条前提（截图挖出来的 bug，钉住它不许回来）──────

## 2026-09-18 截图发现：**命中火花从来没出现在命中点上**。
## 原因是两个默认值的组合拳：
##   ① `CPUParticles2D.local_coords` 默认 **false**（粒子在世界空间发射）
##   ② 调用方的顺序是「add_child → 再设 global_position」
## 而开火发生在 `_ready` —— 那一刻节点还在 (0,0)，于是整把火花打在**世界原点**，
## 在副本里就是「视野外的左上角」。**测试全绿，只有截图能看见。**
## 现在改成：局部坐标 + 等位置摆好再点着。这一组只钉这两条前提
## （粒子本身画成什么样，仍然只能靠 `shot_phase` 那张图）。
func _t5_spark_premises() -> void:
	var fx: Node2D = (preload("res://scenes/components/hit_fx.tscn") as PackedScene).instantiate()
	fx.setup(Color(1, 1, 1), 8, 120.0)
	get_tree().current_scene.add_child(fx)
	fx.global_position = Vector2(777.0, 333.0)
	var p: CPUParticles2D = fx.get_node("P")
	_check("5a", "火花用局部坐标（否则打在节点摆位之前的位置）", p.local_coords,
		"local_coords=%s（必须 true）" % str(p.local_coords))
	# 摆位那一帧还不该开火，摆好了才开
	var early := p.emitting
	await _pframes(2)
	_check("5b", "摆好位置之后才开火（不是 _ready 里立刻点着）",
		not early and p.emitting,
		"摆位当帧 emitting=%s（必须 false）／ 两帧后=%s（必须 true）" % [
			str(early), str(p.emitting)])
	fx.queue_free()


# ── 工具 ──────────────────────────────────────────────────────

func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-9s %s\n              %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-9s %s\n              %s" % [id, desc, detail])


func _spawn(data: EnemyData, at: Vector2) -> Node2D:
	var e: Node2D = BOSS_SCENE.instantiate()
	# data 必须在 add_child 之前设好 —— _ready 要拿它初始化血条与相位
	e.set("data", data)
	_room.add_child(e)
	e.global_position = at
	return e


## 假玩家：只提供「player 组 + Health」两样，够 `walker._player()` 认出人来。
## **不实例化真玩家**（它会带 HUD、技能栏、存档钩子，跑起来噪声太大）
func _dummy_player(at: Vector2) -> Node2D:
	var p := Node2D.new()
	p.name = "TestPlayer"
	var h := Health.new()
	h.name = "Health"
	p.add_child(h)
	_room.add_child(p)
	p.add_to_group("player")
	p.global_position = at
	return p


func _pframes(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## 把房里原有的怪停掉：它们会追人，跑起来让帧数断言抖
func _quiet(lv: Node) -> void:
	for e in lv.find_children("*", "CharacterBody2D", true, false):
		if e.has_method("is_alive") and e.has_method("set_dormant"):
			e.set("ai_enabled", false)


func _screens(lv: Node) -> Array[Node]:
	var out: Array[Node] = []
	for s in lv.get_children():
		if s.is_in_group("screen"):
			out.append(s)
	return out


func _waves(screen: Node) -> Array[Node]:
	var out: Array[Node] = []
	for w in screen.get_children():
		if w.is_in_group("wave"):
			out.append(w)
	return out
