extends Node
## 消耗品预载（5.6 第二条）的观感截图 —— **这三张图是断言之外的唯一把关**。
##     godot --path <项目根> res://tests/shot_potion.tscn     # 输出到 build/shots/
##
## 为什么要截图（每张各回答一个断言答不了的问题）：
##   ① 技能栏 7 格的**宽度**：236 ≤ 240 是算出来的，但「算得对」不等于
##      「看起来没盖住地面」—— 这条线当初就是神照着图说「挡视野」才有的。
##      顺带看两个消耗品格在 32px 格子里是否还认得出来、数字挤不挤。
##   ② 商店左栏 11 行：条目是固定行数的无滚动列，**密度只能看**。
##      还要确认三个消耗品行与还魂丹**不是同一个瓶子**（那是这次顺手拆开的）。
##   ③ 喝符那一下：飘字在不在、格子里数字有没有跟着掉。
##      「按了没反应」是本项目最不接受的失败，而这一条只有图能证。

const TOWN := preload("res://scenes/stages/town.tscn")

var _player: Node
var _health: Node


func _ready() -> void:
	PlayerState.reset_for_new_game()
	var town := TOWN.instantiate()
	add_child(town)
	await _frames(6)
	_player = town.get_node("Player")
	_health = _player.get_node("Health")

	# ── ① 技能栏：三种次数状态同框（3 次 / 1 次 / 0 次用不了）────────
	PlayerState.add_potion_charges(PlayerState.POTION_HP, 3)
	PlayerState.add_potion_charges(PlayerState.POTION_MP, 1)
	_player.call("_refresh_hud")
	await _frames(3)
	# **把几何打出来**：宽度红线是算出来的，但「看起来占多宽」只有像素知道 ——
	# 图上量出来的值对不上算式时，先怀疑「容器被子里撑开了」
	var bar := _player.get_node("HUD/SkillBar") as Control
	print("技能栏 pos=%s size=%s" % [str(bar.position), str(bar.size)])
	for c in bar.get_children():
		print("  %s pos=%s size=%s" % [(c as Control).name, str((c as Control).position),
			str((c as Control).size)])
	print("视口逻辑尺寸=%s" % str(get_viewport().get_visible_rect().size))
	await _shot("potion_1_hud_bar.png")

	# 0 次那一格：暗格 + 灰 0（「暗就是提示」，不弹窗）
	PlayerState.potions.clear()
	PlayerState.add_potion_charges(PlayerState.POTION_HP, 3)
	_player.call("_refresh_hud")
	await _frames(3)
	await _shot("potion_2_hud_empty.png")

	# ── ③ 按 6 喝一口：飘字 + 格子数字跟着掉 ───────────────────────
	_health.set("hp", 12)
	_player.call("_refresh_hud")
	await _frames(2)
	var hp0 := int(_health.get("hp"))
	Input.action_press("item_hp")
	await _frames(1)
	Input.action_release("item_hp")
	await _frames(2)
	print("喝符前 %d → 喝符后 %d（必须变大，否则这一张图什么都没证）"
		% [hp0, int(_health.get("hp"))])
	await _shot("potion_3_drink.png")

	# ── ② 商店左栏（11 行）────────────────────────────────────────
	PlayerState.gold = 5000
	var panel := _player.get_node("ShopPanel")
	panel.call("open")
	await _frames(4)
	# **把货架摆满 7 件**：商店状态存在全局文件里，上一次跑剩下的可能是 2 件 ——
	# 那样这张图就只拍到 6 行，「11 行的密度」等于没验
	var offers: Array = []
	for t in [ItemData.Tier.COMMON, ItemData.Tier.FINE, ItemData.Tier.UNCOMMON]:
		offers.append_array(GameProgress.drop_pool(t))
	PlayerState.shop_offers = offers.slice(0, 7)
	# 光标停在消耗品那一段（还魂丹 + 三种消耗品都在这一屏里）
	var gear: int = panel.call("_left_entries").size()
	for _i in 40:
		_tap_key(KEY_DOWN)
		await _frames(1)
	for _i in gear - 2:
		_tap_key(KEY_UP)
		await _frames(1)
	panel.call("refresh")
	await _frames(3)
	await _shot("potion_4_shop.png")

	get_tree().paused = false
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _tap_key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
