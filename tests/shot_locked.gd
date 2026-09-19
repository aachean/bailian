extends Node
## 「非本职业」记号的观感截图 —— **这道斜杠在 16px 上认不认得出，只有图能答**。
##     godot --path <项目根> res://tests/shot_locked.tscn     # 输出到 build/shots/
##
## 为什么要截图：背包格与商店行的图标只有 **16×16**（`ICON_SIZE`），
## 而装备图标本身已经是「形状 = 部位、颜色 = 品质」的双重编码 ——
## 再叠一道斜杠，可能是「一眼看得见」，也可能是「糊成一团，反而看不懂原来是什么」。
## 断言只能证明 `locked` 传下去了，证明不了这件事。
##
## 顺带看第二件事：**同一屏里两种状态要能分开**。同屏放一把能用的剑和一把用不了的刀，
## 如果两者的图标看起来一样，那这个记号等于没加。

const TOWN := preload("res://scenes/stages/town.tscn")

const SWORD := "res://data/items/wp_u5251_0_u94c1u5251.tres"        # 剑客本命
const BLADE := "res://data/items/wp_u5200_0_u73afu9996u5200.tres"    # 刀 · 用不了
## 制书货架上的杖 —— **取档 3（极品）**，因为真实货架只 roll 极品/传说/至尊
## （低档不掉制书）。拿一把普通杖来摆，价格那一格会显示 0（没有这个档的定价）
const STAFF_BP := "res://data/items/wp_u6756_3_u8d64u708eu6756.tres"  # 赤炎杖 · 极品
const BOW := "res://data/items/wp_u5f13_0_u6728u5f13.tres"           # 弓 · 用不了
## 高檔的也要看一眼：传说黄 / 至尊红是最容易被斜杠糊掉的两种底色
const LEGEND_BLADE := "res://data/items/wp_u5200_4_u5043u6708u5200.tres"

var _player: Node


func _ready() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.character_id = "swordsman"
	PlayerState._character = null
	PlayerState._character_loaded_for = ""

	var town := TOWN.instantiate()
	add_child(town)
	await _frames(6)
	_player = town.get_node("Player")

	# ── ① 背包：四件武器同屏（剑能穿、三件不能），外加一把传说刀 ──
	for p in [SWORD, BLADE, STAFF_BP, BOW, LEGEND_BLADE]:
		PlayerState.add_item(p)
	var hud := _player.get_node("HUD")
	hud.call("toggle_bag")
	await _frames(4)
	# 光标压到那把刀上：详情栏那句人话要同框
	hud.set("_cursor", ItemData.SLOT_IDS.size() + 1)
	hud.call("refresh_bag")
	await _frames(3)
	await _shot("locked_1_bag.png")
	hud.call("toggle_bag")
	await _frames(3)

	# ── ② 商店：左栏两件武器（一剑一刀）+ 右栏一本杖的制书 ──
	PlayerState.gold = 20000
	var panel := _player.get_node("ShopPanel")
	panel.call("open")
	await _frames(4)
	# **货架要在 open 之后再摆** —— open 里那句 `ensure_shop_fresh()` 会在
	# 时钟到期时把货架整个换掉（上一版就这么被冲掉的，拍出来是随机货）
	PlayerState.shop_offers = [SWORD, BLADE]
	PlayerState.shop_bp_offers = [STAFF_BP]
	panel.call("refresh")
	await _frames(3)
	await _shot("locked_2_shop.png")

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
