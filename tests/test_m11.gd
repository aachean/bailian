extends Node
## 《百炼》音效自动验收：**空挥 / 命中 / 受击 / 拾取** 四声。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m11.tscn
##
## 为什么这几声值得单独一组：设计原则 6.1 是条 **[硬]** 规则
## 「有效命中至少给两项反馈」，而在此之前整个游戏**只有顿帧一项、且全程静音**。
##
## 「空挥」是 2026-09-14 神补的一条：**空砍一刀是静音的**，
## 而那是玩家做得最多的动作（「少了在没有打到怪之前，普攻原本的音效」）。
##
## 断言分两层，**第二层才是关键**：
##   · 波形层 —— 三个流真的生成了、时长在合理区间（换素材时这层要重写）
##   · 触发层 —— 真的打中 / 挨打 / 拾取时，对应那一声**被要求播了**
##
## 「音效文件存在」和「打中会响」是两件完全不同的事 ——
## 只验前者的话，触发点根本没接上时断言照样全绿（这个项目在「漏翻」上吃过同款亏）。

const ROOM := preload("res://scenes/stages/test_room.tscn")
const PICKUP := preload("res://scenes/components/pickup.tscn")

## 假人在 x=590（test_room 里写死的），站到它左边 50px 就够得着
const DUMMY_X := 590.0
const ATTACK_X := 540.0

var _pass := 0
var _fail := 0
var _room: Node2D
var _player: Node
var _dummy: Node


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》音效自动验收：空挥 / 命中 / 受击 / 拾取 ═══")

	await _t1_waveforms()

	_room = ROOM.instantiate()
	add_child(_room)
	await _pframes(6)
	_player = _room.get_node("Player")
	_dummy = _room.get_node("TargetDummy")
	(_room.get_node("Walker") as Node).set("ai_enabled", false)

	await _t2_hit_sound()
	await _t3_hurt_sound()
	await _t4_pickup_sound()
	await _t5_unknown_name_is_harmless()
	await _t6_swing_when_missing()
	await _t7_swing_then_hit()

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])

	# 收尾：先停音频再退出。
	# 不收的话，正在播的那几声会在引擎清理时留下
	# 「Leaked instance: AudioStreamWAV / AudioStreamPlaybackWAV」——
	# 那不是功能问题（只在退出时报一句 WARNING），但**每次都挂一行噪音**，
	# 久了就没人再看 WARNING 了，真问题也就混过去了
	Audio.stop_all()
	_room.queue_free()
	await _pframes(2)

	get_tree().paused = false          # 安全网：绝不能带着暂停退出
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


## 站到某个 x 上并**等真的落地** —— 技能要求站地上，
## 悬空的最后几帧会让出招静默失败（这一条在 test_m4 里踩过）
func _place(x: float) -> void:
	_player.global_position = Vector2(x, 288.0)
	_player.set("velocity", Vector2.ZERO)
	await _pframes(2)
	var n := 0
	while not _player.is_on_floor() and n < 60:
		await get_tree().physics_frame
		n += 1
	await _pframes(2)


# ── 1. 波形层 ──────────────────────────────────────────────────

func _t1_waveforms() -> void:
	var names: Array[StringName] = [&"swing", &"hit", &"hurt", &"pickup"]
	var parts: Array[String] = []
	var all_ok := true
	for n in names:
		var d := Audio.duration_of(n)
		parts.append("%s %.3fs" % [n, d])
		if d <= 0.02 or d > 0.5:
			all_ok = false                 # 太短听不见、太长会拖尾糊成一团

	# 响度要**按「响得多频繁」排**：越频繁的越轻，否则连招一打起来全是兵器声，
	# 最该听见的那声（挨打）反而被淹没。
	# 「空挥 < 命中」这一条尤其要紧：打中时两声是叠着放的，
	# 空挥要是压过命中，就变成「打中了听起来跟空挥一样」
	var v := Audio.VOLUME_DB
	var ordered: bool = float(v[&"swing"]) < float(v[&"hit"]) \
		and float(v[&"hit"]) < float(v[&"pickup"]) \
		and float(v[&"pickup"]) < float(v[&"hurt"])
	_check("1", "四声都生成了、时长在 0.02~0.5 秒；响度按「响得多频繁」排（空挥最轻、挨打最响）",
		all_ok and ordered,
		"%s　音量：空挥 %.0f ＜ 命中 %.0f ＜ 拾取 %.0f ＜ 受击 %.0f dB" % [
			"　".join(parts),
			float(v[&"swing"]), float(v[&"hit"]), float(v[&"pickup"]), float(v[&"hurt"])])


# ── 2~4. 触发层（真做那个动作，看那一声响没响）────────────────────

## 打中敌人 → 「命中」。
## **同时断言真的打掉了血** —— 只验计数器的话，「有人手滑调了一下 play()」
## 也能让它绿，而真正要防的是「打中时会不会响」
func _t2_hit_sound() -> void:
	await _place(ATTACK_X)
	_dummy.health.heal_full()
	Audio.reset_counts()
	_press("attack")
	await _pframes(24)
	_release("attack")
	await _pframes(6)
	var hp_lost: int = _dummy.health.max_hp - _dummy.health.hp
	var n := Audio.play_count(&"hit")
	_check("2", "打中敌人：血掉了，并且响了「命中」",
		hp_lost > 0 and n >= 1,
		"假人掉血 %d　命中音被要求播 %d 次" % [hp_lost, n])


## 挨打 → 「受击」
func _t3_hurt_sound() -> void:
	var h := _player.get_node("Health") as Health
	h.heal_full()
	await _pframes(2)
	Audio.reset_counts()
	var dealt := h.take_damage(7)
	await _pframes(4)
	var n := Audio.play_count(&"hurt")
	_check("3", "挨打：血掉了，并且响了「受击」",
		dealt > 0 and n == 1,
		"实际掉血 %d　受击音被要求播 %d 次（期望 1）" % [dealt, n])


## 走近精铁 → 「拾取」
func _t4_pickup_sound() -> void:
	await _place(320.0)
	Audio.reset_counts()
	var before: int = PlayerState.shards
	var p: Node2D = PICKUP.instantiate()          # item_path 留空 = 精铁碎片
	_room.add_child(p)
	p.global_position = _player.global_position + Vector2(6.0, 0.0)
	await _pframes(8)
	var gained: int = PlayerState.shards - before
	var n := Audio.play_count(&"pickup")
	_check("4", "拾取精铁：进账了，并且响了「拾取」",
		gained == 1 and n >= 1,
		"精铁 +%d　拾取音被要求播 %d 次" % [gained, n])


## 名字写错不该让游戏崩 —— 调用点只有三个，但拼错名字是编码期常有的事。
## 顺带盯住「计数在节流之前」这条：计数要是放在节流后面，
## 上面 #2~#4 三条断言就会被节流骗过去（明明触发了、计数却不涨）
func _t5_unknown_name_is_harmless() -> void:
	Audio.reset_counts()
	Audio.play(&"definitely_not_a_sound")
	var n := Audio.play_count(&"definitely_not_a_sound")
	_check("5", "未知音名：不崩、也不会计数",
		n == 0,
		"未知音名的计数 = %d（期望 0，说明它被挡在门外了）" % n)


# ── 6~7. 空挥（2026-09-14 补的一层）──────────────────────────────

## **空 A 也得有声** —— 没打到任何东西的那一刀，以前是完全静音的。
##
## 两头卡：真的出了一招（`attacks_started` 涨）**并且**响的是「空挥」不是「命中」。
## 只验「出了招」的话，触发点没接上也照样绿（这个项目在「漏翻」上吃过同款亏）。
## 「命中响 0 次」这一头同样重要 —— 它把「离这么远也响了命中」这种串音挡在门外
func _t6_swing_when_missing() -> void:
	await _place(200.0)                 # 假人在 590，这一刀绝对够不着
	Audio.reset_counts()
	var before: int = int(_player.get("attacks_started"))
	_press("attack")
	await _pframes(20)
	_release("attack")
	await _pframes(6)
	var attacks: int = int(_player.get("attacks_started")) - before
	var swing := Audio.play_count(&"swing")
	var hit := Audio.play_count(&"hit")
	_check("6", "空 A：砍空也响「空挥」，且不会错响成「命中」",
		attacks >= 1 and swing >= 1 and hit == 0,
		"出了 %d 招　空挥响 %d 次　命中响 %d 次（期望 0 —— 这一刀够不着假人）" % [
			attacks, swing, hit])


## 打中时**两层叠在一起**：出招那一声「空挥」+ 判定那一声「命中」。
## 于是玩家不看飘字也分得出「砍空了」和「砍到了」——
## 这正是设计原则 6.1 要的第二项反馈（在此之前打中只有顿帧一项）
func _t7_swing_then_hit() -> void:
	await _place(ATTACK_X)
	_dummy.health.heal_full()
	Audio.reset_counts()
	_press("attack")
	await _pframes(24)
	_release("attack")
	await _pframes(6)
	var hp_lost: int = _dummy.health.max_hp - _dummy.health.hp
	var swing := Audio.play_count(&"swing")
	var hit := Audio.play_count(&"hit")
	_check("7", "打中时两层都在：先「空挥」、叠上「命中」",
		hp_lost > 0 and swing >= 1 and hit >= 1,
		"假人掉血 %d　空挥响 %d 次　命中响 %d 次" % [hp_lost, swing, hit])
