extends Node
## 节奏探针：把**能自动量的部分**量出来，好让「够不够长 / 够不够打」只留手感给人判。
##     godot --headless --fixed-fps 60 --path <项目根> res://tools/probe_pacing.tscn
##
## **必须走场景，不能用 `--script`** —— `--script` 模式不加载 autoload，
## 而这里要用 `PlayerState` / `Health`：直接跑会是一屏
## `Identifier not found: PlayerState` 的编译错误。
##
## 为什么要有这个：砺场那个形态（一屏 960 / 每屏 3 批 / 一批全灭才出下一批）
## 已经问了三轮「够不够长、够不够打」—— 而这两句话里有**一半是可以算的**：
## 一屏多长、一屏多少血、玩家每秒打多少血、走过去要几秒。
## 算出来之后，人只需要判「这个节奏对不对」，不用对着空气想象。
##
## ⚠️ 「DPS」是**无头实测**来的，不是从数值表推的：真的按住 J 打假人 10 秒，
## 量掉的血。含顿帧、含连招衔接、含空挥 —— 三样都会实打实地拖慢它。

const ROOM := preload("res://scenes/stages/test_room.tscn")
const LICHANG := preload("res://scenes/stages/lichang.tscn")
const IRON_SWORD := "res://data/items/iron_sword.tres"
const DUMMY_X := 590.0
const ATTACK_X := 540.0
## 量多久（帧）。10 秒够长到把连招衔接的波动抹平
const MEASURE_FRAMES := 600


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("══════════ 《百炼》节奏探针 ══════════")
	await _print_level_shape()
	await _measure_dps("刚进砺场（Lv.1 + 老铁匠那把铁剑）", 1, 0)
	await _measure_dps("刷了一阵（Lv.10 + 铁剑 +2）", 10, 2)
	await _print_walk_speed()
	print("")
	print("══════════════════════════════════════")
	get_tree().quit()


# ── 副本的形状：屏 / 批 / 血 ───────────────────────────────────

func _print_level_shape() -> void:
	var lv := LICHANG.instantiate()
	add_child(lv)
	await _frames(4)

	var screens: Array = []
	for s in lv.get_children():
		if s.is_in_group("screen"):
			screens.append(s)
	print("[形状] 砺场：%d 屏" % screens.size())

	var per_screen: Array[int] = []
	var grand := 0
	for i in screens.size():
		var total := 0
		var waves := 0
		var parts: Array[String] = []
		for w in (screens[i] as Node).get_children():
			if not w.is_in_group("wave"):
				continue
			waves += 1
			var wsum := 0
			var n := 0
			for e in (w as Node).get_children():
				var h := e.get_node_or_null("Health") as Health
				if h == null:
					continue
				wsum += h.max_hp
				n += 1
			total += wsum
			parts.append("第%d批 %d只/%d血" % [waves, n, wsum])
		per_screen.append(total)
		grand += total
		print("        第 %d 屏：%d 批，合计 %d 血　（%s）" % [
			i + 1, waves, total, "　".join(parts)])
	print("        全副本合计 %d 血" % grand)

	lv.queue_free()
	await _frames(3)
	_shapes = per_screen
	_grand_hp = grand


var _shapes: Array[int] = []
var _grand_hp := 0


# ── 实测 DPS ───────────────────────────────────────────────────

func _measure_dps(label: String, level: int, forge: int) -> void:
	var room := ROOM.instantiate()
	add_child(room)
	await _frames(6)
	var player: Node = room.get_node("Player")
	var dummy: Node = room.get_node("TargetDummy")
	(room.get_node("Walker") as Node).set("ai_enabled", false)

	# 摆出那一档的装备与等级
	PlayerState.reset_for_new_game()
	PlayerState.level = level
	var uid: String = PlayerState.add_item(IRON_SWORD)
	for _i in forge:
		PlayerState.shards += 999
		PlayerState.forge_once(uid)
	PlayerState.equip(uid)
	player.call("_apply_upgrade")
	player.set("level", level)
	player.call("_apply_upgrade")
	await _frames(2)

	# 假人拉成血牛：它死掉就量不到后面那 9 秒了
	var h: Health = dummy.get_node("Health")
	h.max_hp = 10_000_000
	h.hp = h.max_hp

	# 站定、落地（技能的 `is_on_floor()` 前置不满足会静默出不了招）
	player.global_position = Vector2(ATTACK_X, 288.0)
	player.set("velocity", Vector2.ZERO)
	await _frames(2)
	var guard := 0
	while not player.is_on_floor() and guard < 60:
		await get_tree().physics_frame
		guard += 1
	await _frames(4)

	var start_hp: int = h.hp
	var start_attacks: int = int(player.get("attacks_started"))
	# **连打**：连招要靠再次按 J 接上（按住只出第一段），所以每 3 帧点一下
	for i in MEASURE_FRAMES:
		if i % 3 == 0:
			_press("attack")
		elif i % 3 == 1:
			_release("attack")
		await get_tree().physics_frame
	_release("attack")
	await _frames(4)

	var dealt := start_hp - h.hp
	var swings := int(player.get("attacks_started")) - start_attacks
	var seconds := float(MEASURE_FRAMES) / 60.0
	var dps := float(dealt) / seconds
	var scale: float = player.get_node("Hitbox").get("damage_scale")

	print("[DPS ] %s" % label)
	print("        攻击倍率 ×%.3f　%d 秒打出 %d 伤害、出了 %d 招 → **%.1f 伤害/秒**" % [
		scale, int(seconds), dealt, swings, dps])
	if not _shapes.is_empty():
		var parts: Array[String] = []
		var total_time := 0.0
		for i in _shapes.size():
			# 清一屏 ≈ 总血 / DPS，再加两段 0.75s 的出批间隔
			var clear := float(_shapes[i]) / maxf(dps, 1.0) + 0.75 * 2.0
			total_time += clear
			parts.append("第%d屏 %.1fs" % [i + 1, clear])
		print("        按这个手速推：%s　→ 全副本清怪约 **%.0f 秒**（不含走位与挨打）" % [
			"　".join(parts), total_time])
	_dps_by_level[level] = dps
	room.queue_free()
	await _frames(3)


var _dps_by_level: Dictionary = {}


# ── 走位 ───────────────────────────────────────────────────────

func _print_walk_speed() -> void:
	# 一屏宽与玩家最高速都是确定值，直接算 —— 不用进游戏跑一遍
	var screen_w := 960.0
	var speed := 180.0
	var room := ROOM.instantiate()
	add_child(room)
	await _frames(4)
	speed = float((room.get_node("Player") as Node).get("max_speed"))
	room.queue_free()
	await _frames(2)
	print("[走位] 一屏 %.0fpx ÷ 移速 %.0fpx/s = **%.1f 秒**跑过去（视口宽 640）" % [
		screen_w, speed, screen_w / speed])


# ── 工具 ───────────────────────────────────────────────────────

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


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
	Input.parse_input_event(ev)
