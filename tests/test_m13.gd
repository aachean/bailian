extends Node
## 《百炼》M3 增量 11 自动验收：**断淬渠（4 屏）与炉喉（5 屏）**。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m13.tscn
##
## 前情：砺场那版形态已被神定为模板（2026-09-14「可以当模板了」），
## 这两个副本是照它切的。**形状那一层由砺场的既有断言盯着**（test_m9），
## 这里只盯切的过程中新做进去的三件事：
##
##   · **四步法**（设计原则 2.5）：新敌人先在低威胁的一批里单独出场，
##     Boss 的招式**在它之前就出现过** —— 「Boss 前的 1~2 屏是这个 Boss 的教学屏」
##   · **锯齿**（2.6）：每副本至少一处喘息（一批只有两只小怪），不是一路越来越难
##   · **4.3**：敌人变强靠**配置**（发现得早/追得紧/出手密/更抗打），
##     不是把血条拉长 —— 这条断言盯着「变体到底动了什么」
##
## 另外三条是**重切时最容易静默漏掉**的：
##   · 变体场景里 `data` 忘了换（复制一份场景改个颜色就当成新怪 —— 数值还是原来那只）
##   · 小怪带 `revive_delay > 0` 重生（副本永远打不完，见 ADR-0009 §2）
##   · 旧机制（门封印 / 复活点）顺着旧关卡抄进新副本

const DUANCUIQU := preload("res://scenes/stages/duancuiqu.tscn")
const LUHOU := preload("res://scenes/stages/luhou.tscn")
## 砺场也一起验坐标系 —— 它是模板，模板歪了整章都歪
const LICHANG := preload("res://scenes/stages/lichang.tscn")

const SCREEN_W := 960.0
## 相邻台面的抬升上限。超了就是「看得见但上不去」的台子，而且不报错
const MAX_RISE := 60.0

## 精英变体的对照表：变体 id → 它照着谁做的。
## **变体必须在「行为」上比原型凶**，否则「靠配置变强」就是句空话
const ELITE_OF := {
	"walker_elite": "walker",
	"dasher_elite": "dasher",
	"brute_elite": "brute",
}

var _pass := 0
var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》断淬渠 / 炉喉 自动验收 ═══")

	await _t1_shape()
	await _t2_terrain_budget()
	await _t3_four_step()
	await _t4_sawtooth()
	await _t5_elite_is_config_not_hp()
	await _t6_elite_scene_uses_elite_data()
	await _t7_boss_in_last_wave()
	await _t8_no_farming_loops()
	await _t9_old_mechanisms_are_gone()
	await _t10_unlock_chain()
	await _t11_mobs_inside_their_screen()
	await _t12_dungeon_attack_scale()

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().paused = false          # 安全网：绝不能带着暂停退出
	get_tree().quit(0 if _fail == 0 else 1)


# ── 工具 ───────────────────────────────────────────────────────

## 副本 id → [推荐等级, 攻击倍率]。与 `tools/apply_enemy_scaling.py` 落地的值对表 ——
## **倍率的来历是「玩家承受力之比」**（血量(rec)/血量(章锚点)），改曲线或改 rec_level
## 都要重跑那个脚本；这里的数字就是那次的快照，两边对不上 = 有人动了其中一边
const DUNGEON_SCALE := {
	&"lichang": [1, 0.233], &"duancuiqu": [12, 0.73], &"luhou": [25, 1.138],
	&"canjianlin": [30, 0.85], &"xiushi": [42, 1.0], &"zhongxin": [55, 1.111],
}

## 同一只 walker 同时摆在砺场（lv1）和炉喉（lv25），靠 `DungeonData.enemy_atk_scale`
## 才有两种强度。这条是「伤害按副本等级缩放」的守门人 —— **没有它的话这种错测不出来**：
## 落地脚本自检只对锚点（lv20 的 30 点对表正确），全组测试也绿（没人断言砺场有多疼），
## lv20 的伤害打在 lv1 玩家（100 血）身上就是四下一命，只有玩的人会撞上。所以两头卡：
## 数据侧六个副本的倍率都对表；运行时侧挂进关卡的敌人反查得到倍率、孤儿节点回落 1.0
func _t12_dungeon_attack_scale() -> void:
	var out: Array[String] = []
	var data_ok := true
	for id in DUNGEON_SCALE:
		var want: Array = DUNGEON_SCALE[id]
		var d := GameProgress.dungeon(id)
		if d == null:
			data_ok = false
			out.append("%s 不在副本序列里" % id)
			continue
		if d.rec_level != int(want[0]) or not is_equal_approx(d.enemy_atk_scale, float(want[1])):
			data_ok = false
			out.append("%s rec=%d scale=%.3f（期望 %d / %.3f）" % [
				id, d.rec_level, d.enemy_atk_scale, int(want[0]), float(want[1])])

	# 运行时反查：挂在关卡根下的节点拿得到倍率；没有关卡语境（测试房间）回落 1.0
	var stage := Stage.new()
	var probe := Node2D.new()
	stage.add_child(probe)
	stage.dungeon_data = GameProgress.dungeon(&"lichang")
	add_child(stage)
	var in_stage := Stage.atk_scale_for(probe)
	var orphan := Node2D.new()
	add_child(orphan)
	var no_stage := Stage.atk_scale_for(orphan)
	stage.queue_free()
	orphan.queue_free()
	await _pframes(2)

	var runtime_ok := is_equal_approx(in_stage, 0.233) and is_equal_approx(no_stage, 1.0)
	_check("12", "副本攻击倍率：砺场≈0.23 炉喉≈1.14（对表）；敌人反查拿得到、孤儿节点回落 1.0",
		data_ok and runtime_ok,
		"　".join(out) + "　运行时：砺场下 %.3f / 无关卡 %.2f" % [in_stage, no_stage])


func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-3s %s\n              %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-3s %s\n              %s" % [id, desc, detail])


func _pframes(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## 把怪停掉再量尺寸 —— 怪会追人，量地形时它们到处跑会让断言抖（第一遍过第二遍挂）
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


## 一波里的怪，按声明顺序
func _mobs(wave: Node) -> Array[Node]:
	var out: Array[Node] = []
	for m in wave.get_children():
		if m.has_method("is_alive"):
			out.append(m)
	return out


## 这只怪的 EnemyData.id（不是节点名 —— 节点名是给场景看的）
func _mob_id(m: Node) -> String:
	var d = m.get("data")
	return "" if d == null else str(d.id)


## 某一屏里出现过的所有敌人 id（按出现顺序，含重复）
func _ids_in_screen(lv: Node, i: int) -> Array[String]:
	var out: Array[String] = []
	for w in _waves(_screens(lv)[i]):
		for m in _mobs(w):
			out.append(_mob_id(m))
	return out


## 相邻台面的最大抬升（只算横着的台面；竖着的挡墙不是给人踩的）
func _max_rise(lv: Node) -> float:
	var rects: Array[Rect2] = []
	for c in lv.get_children():
		if not (c is StaticBody2D):
			continue
		var cs := c.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs == null or not (cs.shape is RectangleShape2D):
			continue
		var sh := cs.shape as RectangleShape2D
		if sh.size.x <= sh.size.y:
			continue
		rects.append(Rect2((c as Node2D).global_position - sh.size * 0.5, sh.size))
	rects.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	var worst := 0.0
	for i in range(1, rects.size()):
		var rise: float = rects[i - 1].position.y - rects[i].position.y
		if rise > worst:
			worst = rise
	return worst


# ── 1. 形状 ────────────────────────────────────────────────────

func _t1_shape() -> void:
	var out: Array[String] = []
	var ok := true
	for entry in [[DUANCUIQU, "断淬渠", 4], [LUHOU, "炉喉", 5]]:
		var lv: Node = (entry[0] as PackedScene).instantiate()
		add_child(lv)
		await _pframes(4)
		var screens: int = lv.call("screen_count")
		var want: int = entry[2]
		var b: Rect2 = lv.get("bounds")
		# 每屏 3 批 —— 砺场模板定下的节奏，切的时候容易少摆一批
		var wave_counts: Array[int] = []
		for s in _screens(lv):
			wave_counts.append(_waves(s).size())
		var all_three := true
		for c in wave_counts:
			if c != 3:
				all_three = false
		var total := 0
		for s in _screens(lv):
			for w in _waves(s):
				total += _mobs(w).size()
		var width_ok := absf(b.size.x - SCREEN_W * float(want)) <= 1.0
		out.append("%s %d 屏（每屏 %s 批）共 %d 只，宽 %.0f" % [
			entry[1], screens, str(wave_counts), total, b.size.x])
		if screens != want or not all_three or not width_ok:
			ok = false
		lv.queue_free()
		await _pframes(3)
	_check("1", "两个副本的屏数 / 每屏 3 批 / 全宽都对（照砺场模板切的）",
		ok,
		"　".join(out))


# ── 2. 地形预算 ────────────────────────────────────────────────

func _t2_terrain_budget() -> void:
	var out: Array[String] = []
	var ok := true
	for entry in [[DUANCUIQU, "断淬渠"], [LUHOU, "炉喉"]]:
		var lv: Node = (entry[0] as PackedScene).instantiate()
		add_child(lv)
		await _pframes(4)
		_quiet(lv)
		var worst := _max_rise(lv)
		out.append("%s 最大抬升 %.0fpx" % [entry[1], worst])
		if worst > MAX_RISE:
			ok = false
		lv.queue_free()
		await _pframes(3)
	_check("2", "相邻台面的抬升都在跳跃高度之内（超了就是看得见但上不去的台子，且不报错）",
		ok,
		"%s（上限 %.0fpx，跳跃上限约 73px）" % ["　".join(out), MAX_RISE])


# ── 3. 四步法 ──────────────────────────────────────────────────

## 2.5 的判据有两条，**两条都要**：
##   ① 新敌人第一次出现时是「低威胁」的（那批里只有它一个新面孔）
##   ② **Boss 的招式在 Boss 之前的屏里出现过** —— 否则 Boss 一上来就用
##      玩家没见过的招式，那不是难度，是背板
func _t3_four_step() -> void:
	var lv: Node = DUANCUIQU.instantiate()
	add_child(lv)
	await _pframes(4)

	var first: Dictionary = {}            # 敌人 id → 第一次出现在第几屏
	## 「碎地」（Boss 的招式）在第几屏出现过。**这一条才是四步法的硬判据** ——
	## 只要新敌人单独出场而不教 Boss 的招式，玩家到了 Boss 面前还是第一次见
	var smash_screens: Array[int] = []
	var screens := _screens(lv)
	for i in screens.size():
		for w in _waves(screens[i]):
			for m in _mobs(w):
				var id := _mob_id(m)
				if not first.has(id):
					first[id] = i + 1
				var d = m.get("data")
				if d != null and d.attack_skill != null \
						and str(d.attack_skill.id) == "boss2_smash" \
						and not smash_screens.has(i + 1):
					smash_screens.append(i + 1)

	var caster_at: int = int(first.get("caster", -1))
	var brute_at: int = int(first.get("brute", -1))
	var boss2_at: int = int(first.get("boss2", -1))
	# **掷火者第一次出场的那一批里只有它一只** —— 「引入」要的是
	## 「玩家在零惩罚的环境里认识这个机制」，所以它得单独站一会儿。
	## 口径是**首批**而不是「整屏」：屏 1 后面那批再混编正是「练习」那一步
	var first_caster_screen := -1
	var casters_in_first_wave := 0
	for i in screens.size():
		for w in _waves(screens[i]):
			var n := 0
			for m in _mobs(w):
				if _mob_id(m) == "caster":
					n += 1
			if n > 0 and first_caster_screen < 0:
				first_caster_screen = i + 1
				casters_in_first_wave = n

	lv.queue_free()
	await _pframes(3)

	var taught_before_boss: bool = not smash_screens.is_empty() \
		and int(smash_screens[0]) < boss2_at
	_check("3", "四步法：新敌人先单独出场；**Boss 的招式在 Boss 之前就已经出现过**",
		caster_at == 1 and casters_in_first_wave == 1 and brute_at == 2
			and boss2_at == 4 and taught_before_boss,
		"掷火者首见于第 %d 屏，**那一批里只有 %d 只它**　重锤兵首见于第 %d 屏　石甲卫在第 %d 屏（考核）　碎地招式在第 %s 屏就已出现" % [
			caster_at, casters_in_first_wave, brute_at, boss2_at, str(smash_screens)])


# ── 4. 锯齿难度 ────────────────────────────────────────────────

## 2.6：**每个副本至少留一处喘息点**。
## 判据取「至少有一批只有 2 只怪」，且那一批**不在最后一屏**
## （最后一屏是考核，本来就该紧）。一路越来越难 = 玩家体会不到自己变强
func _t4_sawtooth() -> void:
	var out: Array[String] = []
	var ok := true
	for entry in [[DUANCUIQU, "断淬渠"], [LUHOU, "炉喉"]]:
		var lv: Node = (entry[0] as PackedScene).instantiate()
		add_child(lv)
		await _pframes(4)
		var screens := _screens(lv)
		var breath := 0
		var peak := 0
		var breath_screen := 0
		for i in screens.size():
			for w in _waves(screens[i]):
				var n := _mobs(w).size()
				peak = maxi(peak, n)
				# 喘息 = 一小批（≤2 只）且不在最后一屏
				if n <= 2 and i < screens.size() - 1:
					breath += 1
					breath_screen = i + 1
		out.append("%s 喘息 %d 处（第 %d 屏），单批最多 %d 只" % [
			entry[1], breath, breath_screen, peak])
		if breath < 1:
			ok = false
		lv.queue_free()
		await _pframes(3)
	_check("4", "锯齿难度：每个副本都留了喘息点（一小批怪），不是一路越来越难",
		ok,
		"　".join(out))


# ── 5~6. 4.3：变体动的是配置 ──────────────────────────────────

## **这条是 4.3 的守门人。**
## 「敌人变强靠配置不靠堆血量」—— 堆血量只是把同一场战斗拖长两分钟，
## 打法一点没变，玩家会无聊而不是被挑战。
##
## ── v2 改了判据的形状（2026-09-18，见 design-principles 4.3 的 v2 注）──
## 旧判据是「AI 参数至少三项变凶 **且血量没翻倍**」。v2 给了精英明确的**时长预算**
## （`elite_s` 12 秒），血量是按那个预算反推出来的 —— 「血量没翻倍」这条数字门槛
## 与设计决策正面冲突了，硬守着它只会挡住重做。
## 现在守的是**意图**：精英必须 ① AI 参数至少三项更凶 ② **带上护甲压力**（def 变高）
## ③ 打得更疼（单发变高）。三条一起，「属性全调高、只有血条变长」照样过不了。
## 血量比仍然打出来，是给人看的（它现在是预算的结果，不是随手拍的数）。
func _t5_elite_is_config_not_hp() -> void:
	var out: Array[String] = []
	var ok := true
	for elite_id in ELITE_OF:
		var base := load("res://data/enemies/%s.tres" % ELITE_OF[elite_id]) as EnemyData
		var elite := load("res://data/enemies/%s.tres" % elite_id) as EnemyData
		if base == null or elite == null:
			ok = false
			out.append("%s 加载失败" % elite_id)
			continue
		var sharper := 0
		var names: Array[String] = []
		if elite.aggro_range > base.aggro_range:
			sharper += 1
			names.append("发现 %.0f→%.0f" % [base.aggro_range, elite.aggro_range])
		if elite.chase_speed > base.chase_speed:
			sharper += 1
			names.append("追击 %.0f→%.0f" % [base.chase_speed, elite.chase_speed])
		if elite.attack_cooldown_frames < base.attack_cooldown_frames:
			sharper += 1
			names.append("出手间隔 %d→%d" % [
				base.attack_cooldown_frames, elite.attack_cooldown_frames])
		if elite.hurt_stun_frames < base.hurt_stun_frames:
			sharper += 1
			names.append("硬直 %d→%d" % [base.hurt_stun_frames, elite.hurt_stun_frames])
		var armored := elite.defense > base.defense
		var hits_harder := elite.attack_power() > base.attack_power()
		if armored:
			names.append("防御 %d→%d" % [base.defense, elite.defense])
		if hits_harder:
			names.append("单发 %d→%d" % [base.attack_power(), elite.attack_power()])
		var hp_ratio := float(elite.max_hp) / float(base.max_hp)
		out.append("%s：%s，血量 ×%.2f" % [
			elite_id, "、".join(names) if not names.is_empty() else "（没有一项变凶）", hp_ratio])
		if sharper < 3 or not armored or not hits_harder:
			ok = false
	_check("5", "4.3：精英变强靠「更凶 + 护甲 + 打得更疼」，不是只把血条拉长",
		ok,
		"　".join(out))


## 变体场景最容易静默漏的一步：**复制一份场景、改了颜色、忘了换 `data`**。
## 那样界面上是一只红眼睛的精英，数值却还是原型那只 —— 看不出任何异常。
func _t6_elite_scene_uses_elite_data() -> void:
	var out: Array[String] = []
	var ok := true
	var pairs := {
		"res://scenes/enemies/walker_elite.tscn": "walker_elite",
		"res://scenes/enemies/dasher_elite.tscn": "dasher_elite",
		"res://scenes/enemies/brute_elite.tscn": "brute_elite",
		"res://scenes/enemies/boss_luhou.tscn": "boss_luhou",
	}
	for path in pairs:
		var node: Node = (load(path) as PackedScene).instantiate()
		var got := _mob_id(node)
		out.append("%s → %s" % [path.get_file(), got if not got.is_empty() else "（没接上 data！）"])
		if got != pairs[path]:
			ok = false
		node.free()
	_check("6", "精英/Boss 场景真的换了 data（复制场景忘了换 = 长得像精英、数值还是原型）",
		ok,
		"　".join(out))


# ── 7~9. 通关与不静默 ─────────────────────────────────────────

func _t7_boss_in_last_wave() -> void:
	var out: Array[String] = []
	var ok := true
	for entry in [[DUANCUIQU, "断淬渠", "boss2"], [LUHOU, "炉喉", "boss_luhou"]]:
		var lv: Node = (entry[0] as PackedScene).instantiate()
		add_child(lv)
		await _pframes(4)
		var screens := _screens(lv)
		var last_waves := _waves(screens[screens.size() - 1])
		var ids: Array[String] = []
		for m in _mobs(last_waves[last_waves.size() - 1]):
			ids.append(_mob_id(m))
		out.append("%s 最后一波：%s" % [entry[1], ", ".join(ids)])
		if not ids.has(entry[2]):
			ok = false
		lv.queue_free()
		await _pframes(3)
	_check("7", "每个副本的最后一屏最后一波里都有 Boss（通关 = 清空最后一屏）",
		ok,
		"　".join(out))


## 小怪重生 = 副本永远打不完（过关判据是「清空关内敌人」，见 ADR-0009 §2）。
## 这条在切关卡时特别容易漏：主菜单那批 `.tres` 是共用的，
## 谁把某一只的 `revive_delay` 调回正数，表现是「这一屏怎么清都清不完」
func _t8_no_farming_loops() -> void:
	var bad := PackedStringArray()
	for entry in [[DUANCUIQU, "断淬渠"], [LUHOU, "炉喉"]]:
		var lv: Node = (entry[0] as PackedScene).instantiate()
		add_child(lv)
		await _pframes(4)
		for e in lv.find_children("*", "CharacterBody2D", true, false):
			var d = e.get("data")
			if d == null:
				continue
			if float(d.revive_delay) > 0.0:
				bad.append("%s：%s（%.1fs）" % [entry[1], str(d.id), float(d.revive_delay)])
		lv.queue_free()
		await _pframes(3)
	_check("8", "两个副本里没有会重生的怪（会重生 = 这一屏永远清不完）",
		bad.is_empty(),
		"重生的怪：%s" % ("无" if bad.is_empty() else ", ".join(bad)))


## 门封印与复活点是**被否掉的版本**（ADR-0008 已废止、ADR-0009 淘汰）。
## 代码按工作协议「保留不删」，但**新副本里不许再摆** ——
## 抄旧关卡时最容易把这两样一起抄过来
func _t9_old_mechanisms_are_gone() -> void:
	var found := PackedStringArray()
	for entry in [[DUANCUIQU, "断淬渠"], [LUHOU, "炉喉"]]:
		var lv: Node = (entry[0] as PackedScene).instantiate()
		add_child(lv)
		await _pframes(4)
		for c in lv.find_children("*", "Node", true, false):
			var scr: Script = c.get_script() as Script
			var p: String = "" if scr == null else str(scr.resource_path)
			if p.ends_with("portal.gd") or p.ends_with("checkpoint.gd"):
				found.append("%s：%s" % [entry[1], c.name])
		lv.queue_free()
		await _pframes(3)
	_check("9", "新副本里没有门封印 / 复活点（那两项机制已退役，只是代码保留着）",
		found.is_empty(),
		"找到的旧机制节点：%s" % ("无" if found.is_empty() else ", ".join(found)))


# ── 10. 解锁链 ─────────────────────────────────────────────────

## 三个副本连成一条链：砺场 → 断淬渠 → 炉喉。
## 规则是「上一个通关了就开」，明确不做首通奖励（ADR-0009 §8）
func _t10_unlock_chain() -> void:
	var path := SaveManager.slot_path(SaveManager.current_slot)
	var had := FileAccess.file_exists(path)
	var before := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()

	GameProgress.reset_progress()
	var open_after_reset: bool = GameProgress.is_dungeon_unlocked(&"lichang") \
		and not GameProgress.is_dungeon_unlocked(&"duancuiqu") \
		and not GameProgress.is_dungeon_unlocked(&"luhou")

	GameProgress.on_dungeon_cleared(&"lichang")
	var after_lichang: bool = GameProgress.is_dungeon_unlocked(&"duancuiqu") \
		and not GameProgress.is_dungeon_unlocked(&"luhou")

	var nxt := GameProgress.on_dungeon_cleared(&"duancuiqu")
	var after_duan: bool = GameProgress.is_dungeon_unlocked(&"luhou") \
		and nxt != null and nxt.id == &"luhou"

	# 还回去（这是玩家真正在玩的那份存档）
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(before)
			f.close()
	GameProgress.reset_progress()

	# 数据里三个副本都指到真场景了没有（填错就是「点进去一片黑」）
	var scenes_ok := true
	for id in [&"lichang", &"duancuiqu", &"luhou"]:
		var d := GameProgress.dungeon(id)
		if d == null or d.scene_path.is_empty() or not ResourceLoader.exists(d.scene_path):
			scenes_ok = false

	_check("10", "解锁链：砺场 →（通关）断淬渠 →（通关）炉喉；三个副本都指向真场景",
		open_after_reset and after_lichang and after_duan and scenes_ok,
		"新档只开砺场=%s　通关砺场后开断淬渠=%s　通关断淬渠后开炉喉=%s　场景路径都有效=%s" % [
			str(open_after_reset), str(after_lichang), str(after_duan), str(scenes_ok)])


# ── 11. 坐标系 ─────────────────────────────────────────────────

## 每只怪都长在**自己那一屏**里。
##
## 这条是**截图**抓出来的：断淬渠第一版把第 2/3 屏的怪按「屏内相对坐标」写成了
## 绝对坐标（而这边的 Screen 节点本身就带 x 偏移），两套坐标叠起来 ——
## 那几屏的怪全被推到了后面几屏去。
##
## 而 #1 那些「按分组数怪」的断言**完全看不出来**：分组是对的、数量是对的、
## 每屏 3 批也是对的。表现却很难看：玩家站在这屏，怪在别处追不上来，
## 屏清不掉 → 挡墙不放行 → 只能往回走。
func _t11_mobs_inside_their_screen() -> void:
	var bad := PackedStringArray()
	for entry in [[DUANCUIQU, "断淬渠"], [LUHOU, "炉喉"], [LICHANG, "砺场"]]:
		var lv: Node = (entry[0] as PackedScene).instantiate()
		add_child(lv)
		await _pframes(4)
		var screens := _screens(lv)
		for i in screens.size():
			var scr := screens[i] as Node2D
			var lo := scr.global_position.x
			var hi := lo + SCREEN_W
			# 屏本身也得排在自己的格子上（第 i 屏从 i×960 开始）
			if absf(lo - SCREEN_W * float(i)) > 1.0:
				bad.append("%s：Screen%d 摆在 x=%.0f（应在 %.0f）" % [
					entry[1], i + 1, lo, SCREEN_W * float(i)])
			for w in _waves(scr):
				for m in _mobs(w):
					var gx: float = (m as Node2D).global_position.x
					if gx < lo or gx >= hi:
						bad.append("%s：第%d屏的 %s 在 x=%.0f（应在 %.0f~%.0f）" % [
							entry[1], i + 1, m.name, gx, lo, hi])
		lv.queue_free()
		await _pframes(3)
	_check("11", "屏排在自己的格子上，且每只怪都在**自己那一屏**的 x 区间里",
		bad.is_empty(),
		"越界的：%s" % ("无" if bad.is_empty() else "　".join(bad)))
