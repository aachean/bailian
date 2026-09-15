extends Node
## 《百炼》M4 增量 1 自动验收：**打击感**（屏震 / 命中火花 / 死亡爆点）。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m15.tscn
##
## 前情：顿帧（hitstop_frames）与音效四声已有，那是 M1/M3 的账。
## 这一增量补的是 M4 计划里「打击感」的另外两样：**屏震**与**粒子**：
##   · 屏震走 trauma 模型：0..1 的震动预算，偏移 = 上限 × trauma²，
##     平方让小震真的小、大震才放得开；衰减在顿帧早退之后 —— 世界冻住震动也冻住
##   · 招式多重震多狠写在 SkillData.shake_gain（数字只有一个家），重击再乘一档
##   · 命中火花：金的 = 普通命中，橙的 = 重击，红的 = 挨打；死亡也有一把碎屑
##
## 断言盯的是「反馈真的发生了」与「份量真的分了级」，不是具体手感数值 ——
## 手感归神的黑盒验收，这里只盯结构不撒谎。

const ROOM := preload("res://scenes/stages/test_room.tscn")
const HIT_FX := preload("res://scenes/components/hit_fx.tscn")

var _pass := 0
var _fail := 0
var _room: Node
var _player: Node
var _dummy: Node


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》打击感 自动验收 ═══")

	_room = ROOM.instantiate()
	add_child(_room)
	for _i in 5:
		await get_tree().physics_frame
	_player = _room.get_node("Player")
	_dummy = _room.get_node("TargetDummy")

	await _t1_shake_appears_and_decays()
	await _t2_hit_spawns_sparks()
	await _t3_shake_gain_is_per_skill()
	await _t4_hurt_shakes_harder()
	await _t5_death_burst()
	await _t6_fx_cleans_up()

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().paused = false
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


func _count_fx() -> int:
	var n := 0
	for c in get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("hit_fx.gd"):
			n += 1
	return n


# ── 断言 ───────────────────────────────────────────────────────

## 震动出现（相机真的动了），并且会自己平静下来
func _t1_shake_appears_and_decays() -> void:
	var cam: Camera2D = _player.get_node("Camera")
	_player.call("add_shake", 1.0)
	await _pframes(1)
	var shaken: bool = cam.offset != Vector2.ZERO
	await _pframes(150)
	var settled: bool = cam.offset == Vector2.ZERO \
		and float(_player.get("_trauma")) == 0.0
	_check("1", "屏震：命中后相机真的偏移，约两秒内自己回正",
		shaken and settled,
		"加震后 offset≠0=%s　150 帧后归零=%s" % [str(shaken), str(settled)])


## 打中 → 命中点撒火花（场景里出现 hit_fx 节点）
func _t2_hit_spawns_sparks() -> void:
	var before := _count_fx()
	_player.call("_on_hit_landed", _dummy, 10, _dummy.global_position, false)
	await _pframes(2)
	var after := _count_fx()
	_check("2", "命中火花：命中反馈里撒了一把粒子",
		after > before,
		"特效节点 %d → %d" % [before, after])


## 份量分级写在数据里：重招比轻招震得狠，不砸人的招式为 0
func _t3_shake_gain_is_per_skill() -> void:
	var a1 := load("res://data/skills/attack_1.tres") as SkillData
	var a3 := load("res://data/skills/attack_3.tres") as SkillData
	var quake := load("res://data/skills/quake.tres") as SkillData
	var guard := load("res://data/skills/ironwall.tres") as SkillData
	var ok: bool = a1.shake_gain > 0.0 and a3.shake_gain > a1.shake_gain \
		and quake.shake_gain > a3.shake_gain \
		and guard.shake_gain == 0.0
	_check("3", "屏震份量分级：轻招 < 三段 < 大招；格挡不砸人为 0",
		ok,
		"一段 %.2f　三段 %.2f　崩山击 %.2f　铁壁 %.2f" % [
			a1.shake_gain, a3.shake_gain, quake.shake_gain, guard.shake_gain])


## 挨打震得比命中狠；重击挨打最狠 —— 负反馈必须比正反馈响
func _t4_hurt_shakes_harder() -> void:
	var point: Vector2 = _player.global_position
	_player.set("_trauma", 0.0)
	_player.call("_on_damaged", 5, 10, point, false, 1)
	var light: float = float(_player.get("_trauma"))
	_player.set("_trauma", 0.0)
	_player.call("_on_damaged", 5, 10, point, true, 1)
	var heavy: float = float(_player.get("_trauma"))
	_player.set("_trauma", 0.0)
	_check("4", "挨打屏震：普通 > 命中档，重击 > 普通（第一版太夸张，整体已降档）",
		light >= 0.4 and heavy > light,
		"普通挨打 trauma=%.2f　重击挨打 trauma=%.2f" % [light, heavy])


## 怪死有存在感：尸体位置撒碎屑（顺带给玩家一笔轻震）
func _t5_death_burst() -> void:
	var before := _count_fx()
	var walker := _room.get_node_or_null("Walker")
	if walker == null:
		_check("5", "死亡爆点", false, "测试房里没有 Walker")
		return
	walker.call("_death_burst")
	# 轻震只有 0.12 的预算，衰减每帧 0.06 —— 立刻读，等两帧就被扣光了
	var shaken: bool = float(_player.get("_trauma")) > 0.0
	_player.set("_trauma", 0.0)
	await _pframes(2)
	var after := _count_fx()
	_check("5", "死亡爆点：尸体撒碎屑 + 玩家相机轻震",
		after > before and shaken,
		"特效节点 %d → %d　轻震=%s" % [before, after, str(shaken)])


## 特效是一次性场景，放完连节点一起回收 —— 不留垃圾
func _t6_fx_cleans_up() -> void:
	_player.call("_spawn_hit_fx", _player.global_position + Vector2(40, 0),
		Color(1, 0.9, 0.5), 6, 100.0)
	await _pframes(2)
	var spawned := _count_fx()
	await _pframes(50)               # 寿命 0.38s + 缓冲 0.2s ≈ 35 帧
	var cleaned := _count_fx()
	_check("6", "特效回收：放完连节点一起消失",
		spawned > 0 and cleaned == 0,
		"生成 %d → 50 帧后剩 %d" % [spawned, cleaned])
