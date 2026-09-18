extends Node
## 《百炼》M4 增量 3 自动验收：**第二个角色（远程 · 逐风）+ 新的开始选人**。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m16.tscn
##
## 这个增量是 M4 的**架构验证**：加第二个角色的成本应该只是「两份数据」，
## player 的战斗逻辑一行不为它改。断言盯三类翻车：
##   · 读表 —— 弓手真的拿到弓的连招 / 技能池 / 外观色；老档没选过人 = 回退剑客
##   · 打靶 —— 弓箭是真投射物：飞过去、命中、带全套打击反馈（声/火花/顿帧/屏震）
##   · 流程 —— 新的开始先选人再选槽；选的人进存档，读档回来还是他

const ROOM := preload("res://scenes/stages/test_room.tscn")
const MENU := preload("res://scenes/ui/main_menu.tscn")
const SaveGuard := preload("res://tests/save_guard.gd")

const ARCHER := "res://data/characters/archer.tres"

var _pass := 0
var _fail := 0
var _bak: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》第二角色 自动验收 ═══")
	_bak = SaveGuard.backup()

	await _t1_registry()
	await _t2_player_reads_character()
	await _t3_arrow_actually_flies()
	await _t4_save_roundtrip()
	await _t5_menu_character_page()
	await _t6_old_save_falls_back()
	await _t7_weapon_type_gate()

	SaveGuard.restore(_bak)
	PlayerState.character_id = ""

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


# ── 断言 ───────────────────────────────────────────────────────

## 注册表：两个角色都在，连招与技能池都指到真资源
func _t1_registry() -> void:
	var all := CharacterData.all()
	var ids := {}
	for c in all:
		ids[str(c.id)] = c
	var both: bool = ids.has("swordsman") and ids.has("archer")
	var archer := ids.get("archer") as CharacterData
	var data_ok: bool = archer != null and archer.load_combo().size() == 3 \
		and archer.load_skills().size() >= 3 \
		and (ids.get("swordsman") as CharacterData).load_combo().size() == 3
	_check("1", "角色注册：剑客 + 逐风都在，连招与技能池都指到真资源",
		both and data_ok,
		"注册 %d 个角色　逐风连招/技能 = %d/%d" % [
			all.size(),
			archer.load_combo().size() if archer != null else -1,
			archer.load_skills().size() if archer != null else -1])


## 玩家读表：选了逐风 → 技能池是弓的、连招第一段是 bow_1、外观色换绿
func _t2_player_reads_character() -> void:
	PlayerState.character_id = "archer"
	var room := (ROOM as PackedScene).instantiate()
	add_child(room)
	await _pframes(5)
	var player := room.get_node("Player")
	var pool: Array = player.call("skill_pool_paths")
	var combo: Array = player.get("attack_combo")
	var pool_is_bow: bool = pool.size() == 3 \
		and str(pool[0]).ends_with("quick_shot.tres")
	var combo_is_bow: bool = combo.size() == 3 \
		and str(combo[0].resource_path).ends_with("bow_1.tres")
	var body: ColorRect = player.get_node("Visuals/Body")
	var colored: bool = body.color.is_equal_approx((load(ARCHER) as CharacterData).body_color)
	room.queue_free()
	await _pframes(2)
	_check("2", "玩家读表：逐风 → 弓技能池 / 弓连招 / 外观换色（逻辑零特判）",
		pool_is_bow and combo_is_bow and colored,
		"池 %d 个首个=%s　连招首段=%s" % [
			pool.size(), str(pool[0]).get_file(),
			str(combo[0].resource_path).get_file() if combo.size() > 0 else "?"])


## 弓箭是真投射物：发射 → 飞 → 命中掉血，且带全套打击反馈（屏震在发射方身上）
func _t3_arrow_actually_flies() -> void:
	PlayerState.character_id = "archer"
	var room := (ROOM as PackedScene).instantiate()
	add_child(room)
	await _pframes(5)
	var player := room.get_node("Player")
	var dummy := room.get_node("TargetDummy")
	var dh: Health = dummy.get_node("Health")
	# 靶子可能被这一箭射死并回收 —— 伤害数在信号里记着，别去摸已释放的节点
	var damaged_amount := [0]
	var on_dmg := func(amount: int, _hp: int, _pt: Vector2, _hv: bool, _dr: int) -> void:
		damaged_amount[0] += amount
	dh.damaged.connect(on_dmg)

	# 玩家与靶子同排，靶在面朝方向 140px 外（超出近战判定框，只有箭够得着）
	player.global_position = Vector2(100.0, 288.0)
	dummy.global_position = Vector2(240.0, 288.0)
	var bow_1 := load("res://data/skills/bow_1.tres") as SkillData
	var projs_before := _count_projectiles(self)
	player.call("_fire_projectile", bow_1)
	await _pframes(1)
	# 投射物挂在 current_scene（测试根）上，不是 room 里 —— 数错爹就永远 0
	var fired: bool = _count_projectiles(self) > projs_before
	await _pframes(20)
	var hit_landed: bool = damaged_amount[0] > 0
	var feedback: bool = float(player.get("_trauma")) > 0.0
	room.queue_free()
	await _pframes(2)
	_check("3", "弓箭：真投射物飞 140px 命中掉血，命中反馈（顿帧/火花/屏震）齐全",
		fired and hit_landed and feedback,
		"发射=%s　命中伤害 %d　发射方屏震=%s" % [
			str(fired), damaged_amount[0], str(feedback)])


## 选的人进存档；旧档没有这字段 → 回退剑客，不崩
func _t4_save_roundtrip() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.character_id = "archer"
	var d := PlayerState.save_to()
	PlayerState.load_from(d)
	var kept: bool = PlayerState.character_id == "archer"
	# 旧档场景：进程刚启动、什么都没选过，载入一份没有 character_id 的档
	PlayerState.reset_for_new_game()
	PlayerState.load_from({"level": 3})
	var legacy: bool = PlayerState.character_id == ""
	var fallback: bool = CharacterData.default_character().id == &"swordsman"
	_check("4", "存档：character_id 进出档；旧档缺字段回退默认角色（剑客）",
		kept and legacy and fallback,
		"选逐风存读=%s　旧档空=%s　默认=%s" % [
			str(kept), str(legacy), str(CharacterData.default_character().id)])


## 新的开始：先选人页后槽位页；选人写进 _pending_character
func _t5_menu_character_page() -> void:
	var menu := (MENU as PackedScene).instantiate()
	add_child(menu)
	await _pframes(3)
	menu.call("_on_start")
	await _pframes(2)
	var page_shown: bool = menu.get_node_or_null("Slots").visible == false \
		and bool(menu._char_page.visible)
	var btns: Array[Button] = menu._char_btns
	var two_visible: bool = btns.size() >= 2 and btns[0].visible and btns[1].visible
	menu.call("_on_character", &"archer")
	await _pframes(2)
	var flow_ok: bool = not bool(menu._char_page.visible) \
		and menu.get_node("Slots").visible \
		and menu._pending_character == &"archer"
	var pending_after := str(menu._pending_character)
	menu.queue_free()
	await _pframes(2)
	_check("5", "新的开始：先选人（两颗按钮）→ 再选槽；选的人记在待选里",
		page_shown and two_visible and flow_ok,
		"选人页=%s 按钮≥2=%s 选完进槽位页=%s pending=%s" % [
			str(page_shown), str(two_visible), str(flow_ok), pending_after])


## 老档（没 character_id）进游戏 = 剑客，一行逻辑都没为它改
func _t6_old_save_falls_back() -> void:
	PlayerState.character_id = ""
	var room := (ROOM as PackedScene).instantiate()
	add_child(room)
	await _pframes(5)
	var player := room.get_node("Player")
	var pool: Array = player.call("skill_pool_paths")
	var is_sword: bool = pool.size() == 7 and str(pool[0]).ends_with("whirl.tres")
	room.queue_free()
	await _pframes(2)
	_check("6", "老档回退：没选过人 = 剑客全套（技能池 7 招从旋风斩起）",
		is_sword, "池 %d 个首个=%s" % [pool.size(), str(pool[0]).get_file()])


func _count_projectiles(room: Node) -> int:
	var n := 0
	for c in room.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("projectile.gd"):
			n += 1
	return n


## 武器类型是唯一的装备门：弓手穿剑被拒（可卖不可挥），剑客反之；本命武器畅通。
## **拒绝必须能在界面上说出来**（背包提示行），不许静默。
##
## v2 起武器有**四种**（剑 / 刀 / 弓 / 杖），所以这里除了「别人的本命武器拿不了」，
## 还盯一条新的：**刀与杖现在谁都不能穿**（刀手 / 法师还没做，是批 7）。
## 不盯的话，一把刀会变成「谁都能挥的剑」，而职业门静默失效
func _t7_weapon_type_gate() -> void:
	const SWORD := "res://data/items/wp_u5251_0_u94c1u5251.tres"      # 剑
	const BOW := "res://data/items/wp_u5f13_0_u730eu5f13.tres"        # 弓
	const BLADE := "res://data/items/wp_u5200_0_u73afu9996u5200.tres"  # 刀（无职业）
	const STAFF := "res://data/items/wp_u6756_0_u6843u6728u6756.tres"  # 杖（无职业）
	PlayerState.character_id = "archer"
	PlayerState.reset_for_new_game()
	PlayerState.character_id = "archer"
	var sword_uid := PlayerState.add_item(SWORD)
	var bow_uid := PlayerState.add_item(BOW)
	var blade_uid := PlayerState.add_item(BLADE)
	var staff_uid := PlayerState.add_item(STAFF)
	var sword_refused: bool = PlayerState.equip(sword_uid) == "" \
		and PlayerState.bag.has(sword_uid) \
		and PlayerState.equipped_uid(&"weapon") == ""
	# 注意 equip 的返回值是「被换下来的旧装备 uid」—— 原来槽是空的，成功也返回空串，
	# 别拿它判成败，判「武器栏现在是谁」
	PlayerState.equip(bow_uid)
	var bow_ok: bool = PlayerState.equipped_uid(&"weapon") == bow_uid
	# 剑客侧：逐风弓进不了手
	PlayerState.character_id = "swordsman"
	PlayerState._character = null      # 清缓存（角色切换走菜单，测试里手动模拟）
	PlayerState._character_loaded_for = ""
	var bow_on_sword: bool = not PlayerState.can_equip(PlayerState.item_of(bow_uid))
	var sword_on_sword: bool = PlayerState.can_equip(PlayerState.item_of(sword_uid))
	# 刀 / 杖：两个角色都不该能穿（对应的职业还没做）
	var blade_locked: bool = not PlayerState.can_equip(PlayerState.item_of(blade_uid))
	PlayerState.character_id = "archer"
	PlayerState._character = null
	PlayerState._character_loaded_for = ""
	var staff_locked: bool = not PlayerState.can_equip(PlayerState.item_of(staff_uid))
	PlayerState.reset_for_new_game()
	_check("7", "装备门：弓手穿不了剑（留在包里可卖）、本命弓畅通；剑客反之；刀/杖无职业穿不了",
		sword_refused and bow_ok and bow_on_sword and sword_on_sword \
			and blade_locked and staff_locked,
		"弓手+剑拒=%s　弓手+本命弓=%s　剑客+弓拒=%s　剑客+剑=%s　刀（无职业，剑客）=拒%s　杖（无职业，弓手）=拒%s" % [
			str(sword_refused), str(bow_ok), str(bow_on_sword), str(sword_on_sword),
			str(blade_locked), str(staff_locked)])
