extends Node
## 铁匠铺的观感截图。
##     godot --path <项目根> res://tests/shot_forge.tscn      # 输出到 build/shots/
##
## 为什么这件事必须靠截图：面板里全是**画出来的东西**（图标形状、光标颜色、
## 「+2/5」和一串中文挤在一行会不会串行），断言验得到文字，验不到
## 「它有没有溢出面板边界」。项目在横幅那次已经吃过一次亏（
## CanvasLayer 下的 Control 用 set_anchors_preset 不生效，框宽停在 0，
## 文字从屏幕左边溢出去 —— 只有截图看得见）。
##
## 四种状态各来一张：正常、强化成功、精铁不够、已到顶。
## 「按了没反应」和「按了告诉你为什么不行」是两种完全不同的体验，
## 后者得在画面上真的看得见。

const TOWN := preload("res://scenes/stages/town.tscn")

## v2：装备全部换新 id，这里换成对应的四件（普通剑 / 优秀剑 / 精良盔 / 普通盔）
const IRON_SWORD := "res://data/items/wp_u5251_0_u94c1u5251.tres"
const FLAME_BLADE := "res://data/items/wp_u5251_2_u7384u94c1u5251.tres"
const IRON_HELM := "res://data/items/eq_u5934u76d4_1_u7cbeu94a2u76d4.tres"
const LEATHER_CAP := "res://data/items/eq_u5934u76d4_0_u76aeu76d4.tres"


func _ready() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.shards = 12
	var town := TOWN.instantiate()
	add_child(town)
	await _frames(5)
	var player := town.get_node("Player")
	var anvil := town.get_node("Anvil")
	var panel := player.get_node("ForgePanel")

	# 身上穿一把，背包里再放三件（列表要长到能看出「已装备 / 背包」两种来源）
	PlayerState.equip(PlayerState.add_item(IRON_SWORD))
	PlayerState.add_item(FLAME_BLADE)
	PlayerState.add_item(IRON_HELM)
	PlayerState.add_item(LEATHER_CAP)
	PlayerState.equip(PlayerState.add_item(IRON_HELM))
	player.global_position = anvil.global_position + Vector2(0, -8)
	player.velocity = Vector2.ZERO
	await _frames(8)

	# ── 一、面板刚打开 ────────────────────────────────────────────
	_press("attack")
	await _frames(4)
	_release("attack")
	await _frames(3)
	await _shot("forge_panel.png")

	# ── 二、强化成功一次：看「+1/5」和那一句回话 ──────────────────
	_tap_key(KEY_J)
	await _frames(4)
	await _shot("forge_ok.png")

	# ── 三、精铁不够：必须**看得见原因**，不能只是没反应 ──────────
	PlayerState.shards = 0
	panel.call("refresh")
	await _frames(3)
	_tap_key(KEY_J)
	await _frames(4)
	await _shot("forge_poor.png")

	# ── 四、练到顶：换白装（上限 3）连着练满 ──────────────────────
	PlayerState.shards = 99
	panel.call("refresh")
	await _frames(2)
	# 光标移到白装那件（列表顺序：武器 → 头盔 → 背包四件）
	for _i in 4:
		_tap_key(KEY_DOWN)
		await _frames(2)
	for _i in 5:
		_tap_key(KEY_J)
		await _frames(3)
	await _shot("forge_maxed.png")

	# ── 五、关掉之后：角色面板上「武器强化 +N/上限」长什么样 ──────
	_tap_key(KEY_ESCAPE)
	await _frames(4)
	_press("panel")
	await _frames(4)
	_release("panel")
	await _frames(3)
	await _shot("forge_char_panel.png")

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


func _tap_key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
