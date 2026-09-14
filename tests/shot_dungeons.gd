extends Node
## 断淬渠 / 炉喉 的观感截图（输出 `build/shots/`）。
##     godot --path <项目根> res://tests/shot_dungeons.tscn
##
## 为什么必须看图：
##   · **两个副本的配色是不同的**（断淬渠冷灰蓝 = 水渠、炉喉暖黑褐 = 炉心）——
##     这件事断言一个字都验不到，只有眼睛能判「分得出来吗」。
##   · **精英长什么样**：约定是「眼睛变红、身上加深」。红眼在 40px 的小人身上
##     到底看不看得出来，得看图。
##   · **阵型**：两只掷火者分站两处是不是真的形成「逼你来回跑」的压力，
##     还是一个屏幕里稀稀拉拉几只 —— 这是设计意图，只有画面能验。
##   · **Boss 挥招的那一下有没有前摇感**（判定框 96×64，比上一只大一圈）。
##
## 会动存档槽（要摆「已通关」的状态给舆图看）—— 先备份、跑完还回去。

const DUANCUIQU := preload("res://scenes/stages/duancuiqu.tscn")
const LUHOU := preload("res://scenes/stages/luhou.tscn")
const SaveGuard := preload("res://tests/save_guard.gd")

## 一屏多宽（stage.gd 的 SCREEN_WIDTH）
const SCREEN_W := 960.0

var _bak: Dictionary = {}


func _ready() -> void:
	_bak = SaveGuard.backup()
	SaveManager.current_slot = 3
	SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")

	await _duancuiqu()
	await _luhou()

	SaveGuard.restore(_bak)
	get_tree().paused = false
	get_tree().quit()


# ── 断淬渠 ─────────────────────────────────────────────────────

func _duancuiqu() -> void:
	var lv := DUANCUIQU.instantiate()
	add_child(lv)
	await _frames(6)
	var player := lv.get_node("Player")

	# 一、第 1 屏第 2 批：掷火者**首次出场**（站得比别的怪远，先看清它会远程）
	await _advance(lv, player, 0, 1)
	await _stand(player, 700.0)
	await _shot("duancuiqu_intro.png")

	# 二、第 3 屏：两只掷火者分站两处 + 碎地重锤（转折屏的阵型）
	await _advance(lv, player, 2, 0)
	await _stand(player, 2450.0)
	await _shot("duancuiqu_screen3.png")

	# 三、**碎地重锤真的把碎地挥出来**的那一帧。
	# 判定帧只有 6~7 帧，靠「等几帧再拍」是碰运气 —— 直接盯 Hitbox 的
	# `is_active()`，它一亮就拍。`ai_enabled = false` 时状态机整个不跑，
	# 所以要先把它叫醒（shot_levels 那次就是这么发现「举了手但不挥」的）
	var smash := _find_mob(lv, 2, 1, "brute_heavy")
	if smash != null:
		await _stand(player, 2300.0)
		smash.set("ai_enabled", true)
		await _wait_swing(smash)
		await _shot("duancuiqu_smash.png")
		smash.set("ai_enabled", false)

	# 四、第 4 屏：石甲卫 + 掷火者（考核屏）
	await _advance(lv, player, 3, 0)
	await _stand(player, 3480.0)
	await _shot("duancuiqu_boss.png")

	lv.queue_free()
	await _frames(3)


# ── 炉喉 ───────────────────────────────────────────────────────

func _luhou() -> void:
	var lv := LUHOU.instantiate()
	add_child(lv)
	await _frames(6)
	var player := lv.get_node("Player")

	# 五、第 1 屏：精英（游荡者 / 疾行者）—— 暖色地形 + 红眼看得出来吗
	await _advance(lv, player, 0, 1)
	await _stand(player, 680.0)
	await _shot("luhou_elite.png")

	# 六、第 3 屏：压力峰值（双远程 + 双精英重锤）
	await _advance(lv, player, 2, 0)
	await _stand(player, 2060.0)
	await _shot("luhou_peak.png")

	# 七、第 5 屏：炉心守卫挥招的那一下
	await _advance(lv, player, 4, 2)
	var boss := _find_mob(lv, 4, 2, "boss_luhou")
	await _stand(player, 4580.0)
	if boss != null:
		boss.set("ai_enabled", true)
		await _wait_swing(boss)
		await _shot("luhou_boss.png")
		boss.set("ai_enabled", false)
	else:
		await _shot("luhou_boss.png")

	lv.queue_free()
	await _frames(3)


# ── 工具 ───────────────────────────────────────────────────────

## 把前面的怪清掉，让第 i 屏的第 w 批出场（那一批原样留着，要拍它）。
##
## ── 为什么要**一屏一屏挪过去**，不能一次性杀光 ────────────────
## 关卡只激活「玩家当前这一屏」的批（`_follow_screen` 按玩家 x 算），
## 后面几屏的怪是**休眠**的，而休眠中的怪打不死。一次性杀光的话，
## 后面几屏的怪原封不动地留着，等玩家一挪过去就全活了 ——
## 拍出来是「一屏里塞了四屏的怪」。
##
## 所以：挪过去 → 等关卡把这一屏的批激活 → 打死 → 下一屏。
## 这也是「测试要按产品的真实流程走」的一个具体例子：绕过关卡自己那套
## 「一批全灭才出下一批」，就得自己把它再实现一遍，而且很容易实现错。
func _advance(lv: Node, player: Node, screen_i: int, wave_i: int) -> void:
	for si in screen_i + 1:
		# 先把人挪进这一屏 —— 关卡靠玩家位置决定激活哪一屏
		player.global_position = Vector2(SCREEN_W * float(si) + 200.0, 288.0)
		player.set("velocity", Vector2.ZERO)
		await _frames(10)
		var scr := lv.get_node_or_null("Screen%d" % (si + 1))
		if scr == null:
			continue
		for w in scr.get_children():
			if not w.is_in_group("wave"):
				continue
			# **先判断再打**：要拍的那一批必须留着
			# （反过来的话会把 Boss 一起打死 —— 拍出来是「已通关」横幅，
			#   还顺带触发了通关流程，跟要拍的东西正好相反）
			if si == screen_i and _wave_index(scr, w) >= wave_i:
				break
			for m in w.get_children():
				var h := m.get_node_or_null("Health")
				if h != null:
					h.call("take_damage", 99999, Vector2.ZERO, false, 1)
			# 关卡自己判「这一批清了」要等 CLEAR_DELAY(24) + 两批之间的 WAVE_GAP(45)
			# —— 等 4 帧是不够的，下一批根本还没出来
			await _frames(80)
	await _frames(8)


func _wave_index(screen: Node, wave: Node) -> int:
	var i := 0
	for w in screen.get_children():
		if not w.is_in_group("wave"):
			continue
		if w == wave:
			return i
		i += 1
	return i


func _find_mob(lv: Node, screen_i: int, wave_i: int, id: String) -> Node:
	var scr := lv.get_node("Screen%d" % (screen_i + 1))
	var w := scr.get_node_or_null("Wave%d" % (wave_i + 1))
	if w == null:
		return null
	for m in w.get_children():
		var d = m.get("data")
		if d != null and str(d.id) == id:
			return m
	return null


## 站到某个 x 上并等相机跟过去
func _stand(player: Node, x: float) -> void:
	player.global_position = Vector2(x, 288.0)
	player.set("velocity", Vector2.ZERO)
	await _frames(16)


## 等到这只怪把招式**判定帧**打出来 —— 那一下才看得出前摇与范围。
## 判定只有 6~7 帧，等固定帧数是碰运气；盯 `Hitbox.is_active()` 一亮就返回
func _wait_swing(mob: Node) -> void:
	var hb := mob.get_node_or_null("Hitbox")
	for _i in 200:
		if hb != null and bool(hb.call("is_active")):
			await RenderingServer.frame_post_draw
			return
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
