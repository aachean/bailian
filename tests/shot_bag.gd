extends Node
## 装备系统截图：地上的装备掉落物 / 背包面板 / 角色面板（含装备概览）。
##     godot --path <项目根> res://tests/shot_bag.tscn
## 窗口模式跑，会弹窗；图落在 build/shots/。

const ROOM := preload("res://scenes/stages/test_room.tscn")
const PICKUP := preload("res://scenes/components/pickup.tscn")

const DROPS := [
	"res://data/items/leather_cap.tres",     # 普通
	"res://data/items/iron_sword.tres",      # 精良
	"res://data/items/flame_blade.tres",     # 稀有
]
const WEAR := [
	"res://data/items/iron_sword.tres",
	"res://data/items/iron_helm.tres",
	"res://data/items/iron_armor.tres",
]
const IN_BAG := [
	"res://data/items/wood_charm.tres",
	"res://data/items/cloth_robe.tres",
	"res://data/items/leather_cap.tres",
]


func _ready() -> void:
	var room := ROOM.instantiate()
	add_child(room)
	await _frames(5)
	var player := room.get_node("Player")
	room.get_node("Walker").ai_enabled = false
	room.get_node("Hint").visible = false
	player.global_position = Vector2(320.0, 288.0)
	PlayerState.set_equipment({}, [])

	# ── 一、地上的装备掉落物（三种品质颜色不同） ──────────────
	for i in DROPS.size():
		var p: Node2D = PICKUP.instantiate()
		p.set("item_path", DROPS[i])
		add_child(p)
		p.global_position = Vector2(430.0 + 46.0 * float(i), 300.0)
	await _frames(6)
	await _shot("bag_drop.png")
	for c in get_children():
		if c.get("item_path") != null and str(c.get("item_path")) != "":
			c.queue_free()
	await _frames(3)

	# ── 二、背包面板（四个槽穿三件，背包里三件待选） ──────────
	for path in WEAR:
		PlayerState.add_item(path)
		PlayerState.equip(path)
	for path in IN_BAG:
		PlayerState.add_item(path)
	await _frames(2)
	var hud := player.get_node("HUD")
	hud.call("toggle_bag")
	await _frames(4)
	await _shot("bag_panel.png")
	hud.call("toggle_bag")
	await _frames(3)

	# ── 三、角色面板（属性 + 装备概览） ────────────────────────
	var ev := InputEventAction.new()
	ev.action = "panel"
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)
	await _frames(4)
	await _shot("char_panel.png")
	player.get_node("HUD/CharPanel").visible = false   # 截图脚本直接关，不走输入去重
	await _frames(3)

	# ── 四、手里的刀：装上稀有武器挥一刀，光刃按武器品质变色 ──
	PlayerState.set_equipment({}, [])
	PlayerState.add_item("res://data/items/flame_blade.tres")
	PlayerState.equip("res://data/items/flame_blade.tres")
	player.global_position = Vector2(430.0, 288.0)
	# 等真落地再出招：普攻要求站在地上，悬空按 J 什么都不发生（截图会空）
	var n := 0
	while not player.is_on_floor() and n < 60:
		await get_tree().physics_frame
		n += 1
	await _frames(3)
	var atk := InputEventAction.new()
	atk.action = "attack"
	atk.pressed = true
	atk.strength = 1.0
	# 窗口模式下 process 帧与 physics 帧不同步，单次注入可能正好落进帧缝里被漏掉
	# （实测 attacks_started 一直是 0）。截图脚本只求画面，循环重试到真的出招为止
	var before: int = player.attacks_started
	var tries := 0
	while player.attacks_started == before and tries < 30:
		Input.action_press("attack")
		await _frames(1)
		Input.action_release("attack")
		await _frames(1)
		tries += 1
	await _frames(6)                     # 前摇 6 帧
	# 等到光刃真的亮起来（判定帧）再截，不靠数帧数——
	# 窗口模式下的帧数和无头不一样，数帧会数偏
	var blade := player.get_node("Visuals/Blade") as ColorRect
	var waited := 0
	while blade.modulate.a < 0.5 and waited < 30:
		await get_tree().physics_frame
		waited += 1
	await _shot("blade_weapon.png")
	get_tree().quit()


func _shot(name: String) -> void:
	# 等这一帧真的画完再取图 —— 否则截到的是上一帧，
	# 只在判定帧亮 4 帧的光刃会整个漏掉（这就是为什么之前那张图里没有刀）
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
