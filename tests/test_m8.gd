extends Node
## 《百炼》M3 增量 5 自动验收：第 2/3 关 / 第二个 Boss / 关卡门封印 / 中途复活点
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m8.tscn
##
## 前情：m1..m7 全绿。
##
## 本组盯的是「关卡连起来之后才会发生」的问题 —— 单关卡时代根本遇不到：
##   · 门被 Boss 封着时，玩家会不会以为卡了 bug（静默失败）
##   · 关底 Boss 打死之后**必须**不再重生，否则「通关」这件事不成立
##   · 读档复现一具 Boss 尸体时会不会重掉一次装备（不重生 = 可以反复读档刷）
##   · 关卡从 3 屏变 5 屏之后，死在关底要不要重走整关（复活点）

const LEVEL2 := preload("res://scenes/stages/level_2.tscn")
const LEVEL3 := preload("res://scenes/stages/level_3.tscn")
const TOWN := preload("res://scenes/stages/town.tscn")
## 测试会写存档槽（门的解锁进度）—— 而 user:// 就是玩家真正在玩的目录
const SaveGuard := preload("res://tests/save_guard.gd")

const BRUTE_PATH := "res://data/enemies/brute.tres"
const CASTER_PATH := "res://data/enemies/caster.tres"
const WALKER_PATH := "res://data/enemies/walker.tres"
const BOSS2_PATH := "res://data/enemies/boss2.tres"
const L3_PATH := "res://scenes/stages/level_3.tscn"

var _pass := 0
var _fail := 0
var _bak: Dictionary = {}
var _slot_before := 1


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》M3 增量 5 自动验收：第 2、3 关 ═══")
	_bak = SaveGuard.backup()
	_slot_before = SaveManager.current_slot
	SaveManager.current_slot = 1
	SaveManager.start_new_game(1, "res://scenes/stages/town.tscn")
	await _t1_level2_wired()
	await _t2_gate_locked()
	await _t3_gate_refuses_entry()
	await _t4_boss_death_unlocks()
	await _t5_boss_never_revives()
	await _t6_reload_does_not_redo_drops()
	await _t7_new_enemy_stats()
	await _t8_caster_shoots_from_range()
	await _t9_checkpoint_moves_spawn()
	await _t10_checkpoint_in_snapshot()
	await _t11_level3_wired()
	await _t12_town_entry_is_atlas()
	await _t13_gate_hint_not_a_key()
	await _t14_gap_is_jumpable()
	SaveManager.current_slot = _slot_before
	SaveGuard.restore(_bak)

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ── 工具 ───────────────────────────────────────────────────────

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


## 关掉整关的怪 AI。这组用例只关心结构、门、复活点 ——
## 让一群怪围上来打玩家只会让断言随机会红（M1 用 ai_enabled 隔离是同一个理由）
func _quiet(lv: Node) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and lv.is_ancestor_of(e):
			e.set("ai_enabled", false)


## 地上的装备掉落物数量。掉落物挂在 `current_scene` 下（不是关卡下），
## 所以测试里要数测试根节点的孩子
func _ground_drops() -> int:
	var n := 0
	for c in get_tree().current_scene.get_children():
		var p = c.get("item_path")
		if p != null and str(p) != "":
			n += 1
	return n


func _clear_drops() -> void:
	for c in get_tree().current_scene.get_children():
		if c.get("item_path") != null:
			c.queue_free()


## 场景里所有怪的 id 与总数（按**数据表**分种类，不按脚本 —— 新怪全是数据差异）
func _enemy_census(lv: Node) -> Array:
	var kinds: Dictionary = {}
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and lv.is_ancestor_of(e):
			n += 1
			kinds[str(e.get("data").id)] = true
	var names := PackedStringArray()
	for k in kinds.keys():
		names.append(str(k))
	return [n, names]


# ── 用例 ───────────────────────────────────────────────────────

## 第 2 关结构齐全：两种新怪 + 第二个 Boss + 通往下关的门 + 中途复活点
func _t1_level2_wired() -> void:
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _pframes(3)
	var census := _enemy_census(lv)
	var n: int = census[0]
	var kinds: PackedStringArray = census[1]
	var gate := lv.get_node_or_null("Gate2")
	var bound: Rect2 = lv.get("bounds")
	var cps := 0
	for c in lv.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("checkpoint.gd"):
			cps += 1
	var target: String = "" if gate == null else str(gate.get("target_scene"))
	_check("1", "第 2 关摆得出来：两种新怪 + 第二个 Boss + 通往第 3 关的门 + 两个复活点",
		n >= 9 and kinds.has("brute") and kinds.has("caster") and kinds.has("boss2") \
			and gate != null and target.contains("level_3") and bound.size.x >= 2560.0 and cps >= 2,
		"怪 %d 只（%s）　门→%s　关宽 %.0f　复活点 %d 个" % [
			n, ", ".join(kinds), target.get_file(), bound.size.x, cps])
	lv.queue_free()
	await _pframes(2)


## 门被 Boss 封着：它活着，门就是锁的
func _t2_gate_locked() -> void:
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var gate := lv.get_node("Gate2")
	var h := lv.get_node("Boss2/Health") as Health
	var locked: bool = bool(gate.call("is_locked"))
	var data := load(BOSS2_PATH) as EnemyData
	_check("2", "通往下关的门被 Boss 封着：它活着，门就是锁的",
		locked and not h.is_dead and data.max_hp >= 200 and data.revive_delay <= 0.0,
		"Boss「%s」血 %d／%d　重生 %.1f 秒（0 = 不重生）　门锁着=%s" % [
			data.display_name, h.hp, h.max_hp, data.revive_delay, str(locked)])
	lv.queue_free()
	await _pframes(2)


## 门锁着时走进去不传送，只弹一句「封锁中」
func _t3_gate_refuses_entry() -> void:
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var gate := lv.get_node("Gate2") as Area2D
	# 安全闸：门要是开着，下面那步「走进门」会把测试场景整个换掉，后面全挂。
	# 这是本组唯一一条会真触发场景切换的路径，必须先确认它锁着
	if not bool(gate.call("is_locked")):
		_check("3", "门锁着时走进去不传送，只弹一句「封锁中」", false,
			"门居然是开的 —— 「走进门」会换掉整个测试场景，跳过这条")
		lv.queue_free()
		return

	var player := lv.get_node("Player")
	# 门的「武装」要走过一遍才算：**先进去**（没武装 → 不触发），**再出来**（武装），
	# 再进去才试放行。少走一步就测不出东西 —— 这正是防穿回设计
	player.global_position = gate.global_position
	await _pframes(5)
	var armed_before_leave: bool = bool(gate.get("_armed"))
	player.global_position = gate.global_position - Vector2(90.0, 0.0)
	await _pframes(5)
	var armed: bool = bool(gate.get("_armed"))
	player.global_position = gate.global_position
	await _pframes(8)
	var hint := gate.get_node("Hint") as Label
	# 真传送会把 _armed 清掉。它还在 = 门确实没放行
	var still_armed: bool = bool(gate.get("_armed"))
	_check("3", "门锁着时走进去不传送，只弹一句「封锁中」",
		(not armed_before_leave) and armed and still_armed and not hint.text.is_empty() \
			and hint.text == tr("UI_GATE_LOCKED") and hint.modulate.a > 0.2,
		"门里待着时武装=%s（应为 false）　出去后武装=%s\n              再进门后仍武装=%s（真传送会清掉它）　提示「%s」不透明度 %.2f" % [
			str(armed_before_leave), str(armed), str(still_armed),
			hint.text, hint.modulate.a])
	lv.queue_free()
	await _pframes(2)


## 打倒 Boss → 门解锁 + 记下「已解锁到第 3 关」
func _t4_boss_death_unlocks() -> void:
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var gate := lv.get_node("Gate2")
	(lv.get_node("Boss2/Health") as Health).take_damage(9999, Vector2.ZERO, true, 1)
	await _pframes(4)
	var unlocked: bool = not bool(gate.call("is_locked"))
	var furthest: String = SaveManager.furthest_level()
	_check("4", "打倒 Boss 后门自动解锁，并把「已解锁到第 3 关」写进存档",
		unlocked and furthest == L3_PATH,
		"门解锁=%s　存档里解锁到「%s」" % [str(unlocked), furthest.get_file()])
	lv.queue_free()
	await _pframes(2)


## 关底 Boss 打死就没了 —— 这条不成立的话「通关」本身就不成立
##
## 三层结构之后**小怪也不重生了**（revive_delay 一律 0）：过关判据是
## 「清空关内敌人」，会重生的怪会让关卡永远打不完（docs/adr/0009 §2）。
## 这条断言于是从「Boss 与普通怪不同」变成「谁都不重生」——
## 防的是有人顺手把 2.0 抄回去
func _t5_boss_never_revives() -> void:
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var h := lv.get_node("Boss2/Health") as Health
	h.take_damage(9999, Vector2.ZERO, true, 1)
	await _pframes(4)
	var died: bool = h.is_dead
	await _pframes(360)                    # 6 秒，远超任何重生计时
	var still_dead: bool = h.is_dead and h.hp <= 0
	var walker := load(WALKER_PATH) as EnemyData
	_check("5", "关底 Boss 打死就没了：6 秒后仍不重生（三层结构之后小怪也不重生）",
		died and still_dead and walker.revive_delay <= 0.0,
		"Boss 死后 6 秒：is_dead=%s　hp=%d　（游荡者的重生间隔 %.1f 秒，0 = 不重生）" % [
			str(still_dead), h.hp, walker.revive_delay])
	lv.queue_free()
	await _pframes(2)


## 读档复现尸体不重掉装备、不重给经验
func _t6_reload_does_not_redo_drops() -> void:
	_clear_drops()
	await _pframes(2)
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var boss := lv.get_node("Boss2")
	(boss.get_node("Health") as Health).take_damage(9999, Vector2.ZERO, true, 1)
	await _pframes(5)
	var drops_killed := _ground_drops()
	var exp_killed: int = PlayerState.exp

	# 读档：把 Boss 摆回「已经死了」那一瞬间的样子
	boss.call("apply_saved", {
		"hp": 0, "x": boss.global_position.x, "y": boss.global_position.y,
	})
	await _pframes(5)
	var drops_loaded := _ground_drops()
	var exp_loaded: int = PlayerState.exp
	_check("6", "读档复现尸体**不**重掉装备、不重给经验（否则可反复读档刷 Boss 掉落）",
		drops_killed >= 1 and drops_loaded == drops_killed and exp_loaded == exp_killed,
		"打死瞬间：地上 %d 件 / 经验 %d　读档后：%d 件 / 经验 %d" % [
			drops_killed, exp_killed, drops_loaded, exp_loaded])
	lv.queue_free()
	await _pframes(2)


## 两种新怪各有分工（全在数据里，没有一行新代码）
func _t7_new_enemy_stats() -> void:
	var b := load(BRUTE_PATH) as EnemyData
	var c := load(CASTER_PATH) as EnemyData
	var w := load(WALKER_PATH) as EnemyData
	var bs := load(BOSS2_PATH) as EnemyData
	var heavy: bool = b.attack_skill != null and b.attack_skill.heavy \
		and b.attack_skill.damage > w.attack_skill.damage
	var tanky: bool = b.max_hp >= w.max_hp * 2 and b.hurt_stun_frames < w.hurt_stun_frames
	var ranged: bool = c.projectile_damage >= w.attack_skill.damage \
		and c.aggro_range > w.aggro_range
	_check("7", "两种新怪分工明确：重锤兵又硬又重、不轻易被打断；掷火者射得远、单发更痛",
		heavy and tanky and ranged and bs.max_hp > b.max_hp,
		"重锤兵：血 %d（游荡者 %d）硬直 %d 帧（%d）锤 %d 伤害 heavy=%s\n              掷火者：索敌 %d（游荡者 %d）火球 %d 伤害　Boss2 血 %d" % [
			b.max_hp, w.max_hp, b.hurt_stun_frames, w.hurt_stun_frames,
			b.attack_skill.damage, str(b.attack_skill.heavy),
			int(c.aggro_range), int(w.aggro_range), c.projectile_damage, bs.max_hp])


## 掷火者真的隔着距离开火，火球真的打得到人
func _t8_caster_shoots_from_range() -> void:
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var caster := lv.get_node("Caster1")
	caster.global_position = Vector2(1000.0, 300.0)
	lv.get_node("Dasher1").global_position = Vector2(1600.0, 300.0)
	var player := lv.get_node("Player")
	player.global_position = Vector2(1240.0, 296.0)
	await _pframes(20)
	var gap: float = absf(player.global_position.x - caster.global_position.x)
	# 只放开这一只：它得隔着 200 多像素开火，近战怪没有任何手段够得着
	caster.set("ai_enabled", true)
	var hp0: int = int(player.get_node("Health").hp)
	var threw_at := -1
	for i in 300:
		await get_tree().physics_frame
		if int(caster.get("throws_started")) >= 1:
			threw_at = i
			break
	await _pframes(90)                      # 让火球飞完
	var hp1: int = int(player.get_node("Health").hp)
	var cd := int(caster.get("data").attack_cooldown_frames)
	_check("8", "掷火者隔着 200+ 像素就开火，火球真的打得到人",
		threw_at >= 0 and gap > 150.0 and hp1 < hp0 and cd >= 150,
		"距离 %.0f px　第 %d 帧开火（近战怪够不到）　玩家血 %d → %d　射速冷却 %d 帧" % [
			gap, threw_at, hp0, hp1, cd])
	lv.queue_free()
	await _pframes(2)


## 踩过复活点，重生点就挪过去
func _t9_checkpoint_moves_spawn() -> void:
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var player := lv.get_node("Player")
	var cp := lv.get_node("Checkpoint1")
	var before: Vector2 = player.call("spawn_point")
	var lit_before: Color = (cp.get_node("Visual") as ColorRect).color
	player.global_position = cp.global_position
	await _pframes(6)
	var after: Vector2 = player.call("spawn_point")
	var lit_after: Color = (cp.get_node("Visual") as ColorRect).color
	_check("9", "踩过中途复活点，死后的重生点就挪过去（而且看得见「这里记下了」）",
		absf(after.x - cp.global_position.x) < 2.0 \
			and absf(before.x - after.x) > 100.0 and lit_after != lit_before,
		"复活点 x %.0f → %.0f（台阶在 %.0f）　灯色 %s → %s" % [
			before.x, after.x, cp.global_position.x, str(lit_before), str(lit_after)])
	lv.queue_free()
	await _pframes(2)


## 复活点进存档快照，读档后不会退回关卡开头
func _t10_checkpoint_in_snapshot() -> void:
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var player := lv.get_node("Player")
	var cp := lv.get_node("Checkpoint2")
	player.global_position = cp.global_position
	await _pframes(6)
	var snap: Dictionary = lv.call("collect")
	var pd: Dictionary = snap.get("player", {})
	var has_spawn: bool = pd.has("spawn_x") and pd.has("spawn_y")
	var saved_x := float(pd.get("spawn_x", 0.0))
	player.call("set_spawn_point", Vector2(150.0, 296.0))
	player.call("apply_saved", pd)
	var back: Vector2 = player.call("spawn_point")
	_check("10", "复活点也进存档快照 —— 读档后死在关底，不会退回关卡开头",
		has_spawn and absf(saved_x - cp.global_position.x) < 2.0 \
			and absf(back.x - cp.global_position.x) < 2.0,
		"快照里的复活点 x=%.0f（台阶在 %.0f）　读档后 x=%.0f" % [
			saved_x, cp.global_position.x, back.x])
	lv.queue_free()
	await _pframes(2)


## 第 3 关：更长更难，顶上有猎人收尾，门回城镇
func _t11_level3_wired() -> void:
	var lv := LEVEL3.instantiate()
	add_child(lv)
	await _pframes(3)
	var census := _enemy_census(lv)
	var n: int = census[0]
	var kinds: PackedStringArray = census[1]
	var bound: Rect2 = lv.get("bounds")
	var hunter := lv.get_node_or_null("Hunter")
	var gate := lv.get_node_or_null("Gate3")
	var gate_target: String = "" if gate == null else str(gate.get("target_scene"))
	var cps := 0
	for c in lv.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("checkpoint.gd"):
			cps += 1
	_check("11", "第 3 关更长更难：怪比第 2 关多、混编、顶上有猎人收尾、门回城镇",
		n >= 12 and bound.size.x > 2880.0 and kinds.has("brute") and kinds.has("caster") \
			and hunter != null and gate != null and gate_target.contains("town") and cps >= 2,
		"怪 %d 只（%s）　关宽 %.0f　猎人=%s　门→%s　复活点 %d 个" % [
			n, ", ".join(kinds), bound.size.x, str(hunter != null),
			gate_target.get_file(), cps])
	lv.queue_free()
	await _pframes(2)


## 城镇的入口设施：舆图台，不是传送门
##
## 原来是「城镇的门直接送到已解锁的最远关卡」。三层结构之后进副本改走舆图
## （docs/adr/0009 §4），这条断言于是改成盯「城镇里到底是哪件设施在管入口」——
## 防的是有人把传送门加回来，或者把舆图台删了
func _t12_town_entry_is_atlas() -> void:
	var town := TOWN.instantiate()
	add_child(town)
	await _pframes(3)
	var pedestal := town.get_node_or_null("AtlasPedestal")
	var zone: CollisionShape2D = null
	if pedestal != null:
		zone = pedestal.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var no_portal: bool = town.get_node_or_null("ExitPortal") == null
	var atlas := town.get_node_or_null("Player/Atlas")
	_check("12", "城镇的入口是舆图台（走近出提示、按 P 开舆图），传送门已经退役",
		pedestal != null and zone != null and no_portal and atlas != null,
		"舆图台=%s（碰撞区=%s）　传送门=%s　玩家身上带舆图=%s" % [
			str(pedestal != null), str(zone != null),
			"已拆" if no_portal else "**还在**", str(atlas != null)])
	town.queue_free()
	await _pframes(2)


## 门上的提示是译好的真话，不是翻译 key 本身
func _t13_gate_hint_not_a_key() -> void:
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var gate := lv.get_node("Gate2")
	gate.call("_flash_hint")
	await _pframes(2)
	var text := (gate.get_node("Hint") as Label).text
	var re := RegEx.new()
	re.compile("(UI|PANEL|HUD|ITEM|SLOT|STAT|DLG|NPC)_[A-Z0-9_]+")
	var leaks := PackedStringArray()
	for m in re.search_all(text):
		leaks.append(m.get_string())
	_check("13", "门上的「封锁中」是译好的真话，不是翻译 key 本身",
		leaks.is_empty() and not text.is_empty() and text != "UI_GATE_LOCKED",
		"提示「%s」　泄漏：%s" % [text, "无" if leaks.is_empty() else ", ".join(leaks)])
	lv.queue_free()
	await _pframes(2)


## 第 2 关的断口**助跑跳**得过去（不是瞬移过去），且全关抬升都在跳跃高度之内。
##
## 这条是专门防「瞬移测不出玩法」那个老坑的：把角色挪到对岸只能证明那边有地面，
## 证明不了玩家跳得到。所以这里走完整操作链：站定 → 按右助跑 → 起跳 → 落点判定。
func _t14_gap_is_jumpable() -> void:
	var lv := LEVEL2.instantiate()
	add_child(lv)
	await _pframes(3)
	_quiet(lv)
	var player := lv.get_node("Player")
	player.global_position = Vector2(820.0, 296.0)
	await _pframes(24)                       # 落到地面上站稳
	var start_x: float = player.global_position.x
	_press("move_right")
	await _pframes(22)                       # 助跑，速度拉满（accel_time 只有 5 帧）
	var edge_x: float = player.global_position.x
	_press("jump")
	await _pframes(4)
	_release("jump")
	await _pframes(70)                       # 滞空 + 落地
	_release("move_right")
	await _pframes(4)
	var landed_x: float = player.global_position.x
	var landed: bool = player.is_on_floor()
	var worst_rise := _max_rise(lv)
	_check("14", "第 2 关的断口助跑跳得过去；全关最大抬升都在跳跃高度之内",
		landed and landed_x > 962.0 and worst_rise <= 60.0,
		"助跑 %.0f→%.0f 起跳，落点 x=%.0f（断口 888~952）　落地站稳=%s\n              全关最大抬升 %.0fpx（跳跃上限约 73px）" % [
			start_x, edge_x, landed_x, str(landed), worst_rise])
	lv.queue_free()
	await _pframes(2)


# ── 输入注入与几何预算 ─────────────────────────────────────────

func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)


func _release(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	ev.strength = 0.0
	Input.parse_input_event(ev)


## 相邻平台之间最大的一次「抬升」（像素）。
## 玩家跳跃高度 ≈ 420²/(2×1200) ≈ 73px —— 抬升超过它，那个台子**根本上不去**，
## 而且上不去这件事不会报错，只会让人以为「这个跳台是装饰」。
func _max_rise(lv: Node) -> float:
	var rects: Array[Rect2] = []
	for c in lv.get_children():
		if not (c is StaticBody2D):
			continue
		var cs := c.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if cs == null or not (cs.shape is RectangleShape2D):
			continue
		var sz: Vector2 = (cs.shape as RectangleShape2D).size
		rects.append(Rect2((c as Node2D).global_position - sz * 0.5, sz))
	rects.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	var worst := 0.0
	for i in range(1, rects.size()):
		var rise: float = rects[i - 1].position.y - rects[i].position.y
		if rise > worst:
			worst = rise
	return worst
