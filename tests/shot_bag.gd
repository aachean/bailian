extends Node
## 装备系统截图：地上的装备掉落物 / 背包面板 / 角色面板（含装备概览）。
##     godot --path <项目根> res://tests/shot_bag.tscn
## 窗口模式跑，会弹窗；图落在 build/shots/。

const ROOM := preload("res://scenes/stages/test_room.tscn")
const PICKUP := preload("res://scenes/components/pickup.tscn")

## 六件正好覆盖六档 —— 这张图就是「六档颜色两两可辨」的验收。
## 注意 v2 里「铁剑」是**普通**档（v1 是精良），名字一样但档位不一样了
const DROPS := [
	"res://data/items/eq_u5934u76d4_0_u76aeu76d4.tres",   # 皮盔 · 普通（白）
	"res://data/items/wp_u5251_1_u7cbeu94a2u5251.tres",   # 精钢剑 · 精良（绿）
	"res://data/items/wp_u5251_2_u7384u94c1u5251.tres",   # 玄铁剑 · 优秀（蓝）
	"res://data/items/wp_u5251_3_u5bd2u6708u5251.tres",   # 寒月剑 · 极品（紫）
	"res://data/items/wp_u5251_4_u9f99u6e0au5251.tres",   # 龙渊剑 · 传说（橙）
	"res://data/items/wp_u5251_5_u8f69u8f95u5251.tres",   # 轩辕剑 · 至尊（红）
]
## 八槽各穿一件 —— 这张图就是「8 行装备塞不塞得下」的唯一验收
const WEAR := [
	"res://data/items/wp_u5251_0_u94c1u5251.tres",        # 武器
	"res://data/items/eq_u5934u76d4_0_u94c1u76d4.tres",   # 头盔
	"res://data/items/eq_u80f8u7532_1_u94c1u7532.tres",   # 胸甲
	"res://data/items/eq_u62a4u817f_0_u76aeu62a4u817f.tres",  # 护腿
	"res://data/items/eq_u9774u5b50_0_u5e03u978b.tres",   # 靴子
	"res://data/items/eq_u6212u6307_0_u94c1u6212.tres",   # 戒指
	"res://data/items/eq_u9879u94fe_0_u9ebbu7ef3u9879u94fe.tres",  # 项链
	"res://data/items/eq_u624bu956f_0_u6728u956f.tres",   # 手镯
]
## 背包里的三件顺便验四种武器图标的另外三种（刀 / 弓 / 杖）
const IN_BAG := [
	"res://data/items/wp_u5200_2_u7384u94c1u5200.tres",   # 玄铁刀
	"res://data/items/wp_u5f13_0_u730eu5f13.tres",        # 猎弓
	"res://data/items/wp_u6756_0_u6843u6728u6756.tres",   # 桃木杖
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
		p.global_position = Vector2(420.0 + 34.0 * float(i), 300.0)
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

	# ── 三、手里的刀：装上稀有武器挥一刀，光刃按武器品质变色 ──
	PlayerState.set_equipment({}, [])
	PlayerState.add_item("res://data/items/wp_u5251_4_u9f99u6e0au5251.tres")
	PlayerState.equip("res://data/items/wp_u5251_4_u9f99u6e0au5251.tres")
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
