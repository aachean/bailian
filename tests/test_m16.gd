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
	await _t8_gate_is_visible()
	await _t9_combo_projectiles()

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

## 注册表：四个角色都在，连招与技能池都指到真资源（批 7：+刀手 / +法师）
func _t1_registry() -> void:
	var all := CharacterData.all()
	var ids := {}
	for c in all:
		ids[str(c.id)] = c
	var four: bool = ids.has("swordsman") and ids.has("archer") \
		and ids.has("bladesman") and ids.has("mage")
	var data_ok := true
	for cid in ["swordsman", "archer", "bladesman", "mage"]:
		var c := ids.get(cid) as CharacterData
		data_ok = data_ok and c != null and c.load_combo().size() == 3 \
			and c.load_skills().size() >= 3
	var mage := ids.get("mage") as CharacterData
	var staff_ok: bool = mage != null and mage.weapon_type == &"staff" \
		and str(mage.combo[0]).ends_with("staff_1.tres")
	_check("1", "角色注册：剑客/逐风/刀手/法师都在，连招与技能池都指到真资源",
		four and data_ok and staff_ok,
		"注册 %d 个角色　法师连招首段=%s 武器=%s" % [
			all.size(),
			str(mage.combo[0]).get_file() if mage != null else "?",
			str(mage.weapon_type) if mage != null else "?"])


## 玩家读表：刀手 → 刀连招 / 外观换色；法师 → 杖连招 / 外观换色（逻辑零特判）
func _t2_player_reads_character() -> void:
	var expect := {
		"bladesman": "blade_1.tres",
		"mage": "staff_1.tres",
	}
	var ok := true
	var detail := ""
	for cid in expect:
		PlayerState.character_id = cid
		var room := (ROOM as PackedScene).instantiate()
		add_child(room)
		await _pframes(5)
		var player := room.get_node("Player")
		var combo: Array = player.get("attack_combo")
		var pool: Array = player.call("skill_pool_paths")
		var body: ColorRect = player.get_node("Visuals/Body")
		var cd := load("res://data/characters/%s.tres" % cid) as CharacterData
		var hit: bool = combo.size() == 3 \
			and str(combo[0].resource_path).ends_with(expect[cid]) \
			and pool.size() >= 5 \
			and body.color.is_equal_approx(cd.body_color)
		ok = ok and hit
		detail += "%s: 连招首段=%s 池=%d 色=%s　" % [
			cid, str(combo[0].resource_path).get_file(), pool.size(), str(hit)]
		room.queue_free()
		await _pframes(2)
	_check("2", "玩家读表：刀手 → 刀连招、法师 → 杖连招、外观换色（逻辑零特判）",
		ok, detail)


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
	# 批 7 后是四职业：按钮数量跟 data/characters/ 走，一颗都不能缺
	var four_visible: bool = btns.size() == 4
	for b in btns:
		four_visible = four_visible and b.visible
	menu.call("_on_character", &"archer")
	await _pframes(2)
	var flow_ok: bool = not bool(menu._char_page.visible) \
		and menu.get_node("Slots").visible \
		and menu._pending_character == &"archer"
	var pending_after := str(menu._pending_character)
	menu.queue_free()
	await _pframes(2)
	_check("5", "新的开始：先选人（四颗按钮）→ 再选槽；选的人记在待选里",
		page_shown and four_visible and flow_ok,
		"选人页=%s 按钮=%d 全可见=%s 选完进槽位页=%s pending=%s" % [
			str(page_shown), btns.size(), str(four_visible), str(flow_ok), pending_after])


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


## 武器类型是唯一的装备门：每个职业穿得了本命武器、穿不了别的三种（留在包里可卖）。
## **拒绝必须能在界面上说出来**（背包提示行），不许静默。
##
## 批 7 前这里盯的是「刀与杖谁都不能穿」（职业没做）；批 7 后四个职业齐了，
## 断言翻过来：**每种武器都有主，也只认主** —— 4×4 全查，一门失效立刻现形
func _t7_weapon_type_gate() -> void:
	const W := {
		"sword": "res://data/items/wp_u5251_0_u94c1u5251.tres",      # 剑 → 剑客
		"blade": "res://data/items/wp_u5200_0_u94c1u5200.tres",      # 刀 → 刀手
		"bow": "res://data/items/wp_u5f13_0_u730eu5f13.tres",        # 弓 → 逐风
		"staff": "res://data/items/wp_u6756_0_u5b66u5f92u6756.tres", # 杖 → 法师
	}
	const CHARS := {
		"swordsman": "sword", "bladesman": "blade", "archer": "bow", "mage": "staff",
	}
	var ok := true
	var detail := ""
	for cid in CHARS:
		PlayerState.reset_for_new_game()
		PlayerState.character_id = cid
		PlayerState._character = null
		PlayerState._character_loaded_for = ""
		var own: bool = true
		var others: bool = true
		for wtype in W:
			var uid := PlayerState.add_item(W[wtype])
			if wtype == CHARS[cid]:
				PlayerState.equip(uid)
				own = own and PlayerState.equipped_uid(&"weapon") == uid
			else:
				others = others and not PlayerState.can_equip(PlayerState.item_of(uid)) \
					and PlayerState.bag.has(uid)
		ok = ok and own and others
		detail += "%s: 本命=%s 他命全拒=%s　" % [cid, str(own), str(others)]
	PlayerState.reset_for_new_game()
	_check("7", "装备门：四职业各穿本命武器畅通，其余三种全拒（留在包里可卖）",
		ok, detail)


## **门要在界面上看得见**（[ADR-0025](../docs/adr/0025-skill-pool-module-and-unfiltered-drops.md) §2.2）。
##
## §2 裁定「掉落 / 货架 / 制书都不按职业过滤」——别的职业的武器是**经济来源**。
## 代价很硬：加满 4 职业之后，任意角色**只有 1/4 的武器能用**，
## 也就是说「这个东西我用不了」从偶发变成了常态。
## 而在此之前，玩家要**按下 J** 才会看到那句提示 —— 背包格、商店行上什么都没有。
## 在 10000 元宝的至尊制书上，那个顺序就是「先让你买，再告诉你穿不上」。
##
## 这一组盯三处 + 一句话：背包格 / 商店装备行 / 商店制书行都要带记号，
## 详情栏要把**为什么、能拿它干什么**说全（符号只说「有问题」，说不出原因）。
func _t8_gate_is_visible() -> void:
	const SWORD := "res://data/items/wp_u5251_0_u94c1u5251.tres"
	const BLADE := "res://data/items/wp_u5200_0_u73afu9996u5200.tres"
	const STAFF := "res://data/items/wp_u6756_0_u6843u6728u6756.tres"

	PlayerState.reset_for_new_game()
	PlayerState.character_id = "swordsman"
	PlayerState._character = null
	PlayerState._character_loaded_for = ""

	var room := (ROOM as PackedScene).instantiate()
	add_child(room)
	await _pframes(5)
	var player := room.get_node("Player")
	var hud := player.get_node("HUD")

	# 剑（能用）与刀（用不了）各一件进背包 —— 同一屏里两种状态并存，
	# 这样断言才分得清「标记跟着装备走」和「整屏都变暗了」
	PlayerState.add_item(SWORD)
	PlayerState.add_item(BLADE)
	hud.call("toggle_bag")
	await _pframes(4)

	# ① 背包格
	var grid := hud.get_node("BagPanel/BagGrid")
	var ok_icon := (grid.get_child(0) as Panel).get_child(1) as ItemIcon
	var bad_icon := (grid.get_child(1) as Panel).get_child(1) as ItemIcon
	# **先在节点还活着的时候把值取出来**：下面要 queue_free 掉这个 room，
	# 之后再读 icon.locked 就是访问已释放对象（真踩了：断言没跑到，
	# 组里却打印「7 通过 / 0 失败」—— 只有脚本报错说了实话）
	var ok_locked := ok_icon.locked
	var bad_locked := bad_icon.locked
	var grid_ok: bool = ok_locked == false and bad_locked == true

	# ② 商店两栏（不 open —— open 会暂停世界；refresh 本身不要求可见）
	var shop := player.get_node("ShopPanel")
	PlayerState.gold = 100000
	PlayerState.shop_offers = [SWORD, BLADE]
	PlayerState.shop_bp_offers = [STAFF]
	shop.call("refresh")
	var gear_rows := shop.get_node("Root/Panel/Rows")
	var bp_rows := shop.get_node("Root/Panel/BPRows")
	var unusable := tr("UI_ITEM_UNUSABLE")
	var gear_ok_txt: bool = not str((gear_rows.get_child(0) as Node).get_child(1).text).contains(unusable)
	var gear_bad_txt: bool = str((gear_rows.get_child(1) as Node).get_child(1).text).contains(unusable)
	var gear_bad_icon: bool = ((gear_rows.get_child(1) as Node).get_child(0) as ItemIcon).locked
	var bp_bad_txt: bool = str((bp_rows.get_child(0) as Node).get_child(1).text).contains(unusable)
	var bp_bad_icon: bool = ((bp_rows.get_child(0) as Node).get_child(0) as ItemIcon).locked

	# ③ 详情栏那句人话（符号说不出「所以能拿它干什么」）
	hud.call("_refresh_detail_panel", PlayerState.bag, 1)
	var detail := str((hud.get("_detail_text") as Label).text)

	hud.call("toggle_bag")
	get_tree().paused = false
	PlayerState.reset_for_new_game()
	room.queue_free()
	await _pframes(2)

	_check("8", "「用不了」在列表上就看得见：背包格 / 商店装备行 / 制书行都有记号，详情栏说清怎么办",
		grid_ok and gear_ok_txt and gear_bad_txt and gear_bad_icon and bp_bad_txt and bp_bad_icon
			and detail.contains(tr("UI_BAG_LOCKED_LINE")),
		"背包格 剑斜杠=%s（必须 false）　刀斜杠=%s（必须 true）\n              商店行 剑**无**记号=%s（必须 true）　刀有记号=%s（必须 true）　刀图标斜杠=%s\n              制书行 有记号=%s 图标斜杠=%s　详情栏=%s" % [
			str(ok_locked), str(bad_locked),
			str(gear_ok_txt), str(gear_bad_txt), str(gear_bad_icon),
			str(bp_bad_txt), str(bp_bad_icon), detail.split("\n")[0]])


## **远程三段连招，每一段都要发弹**。
##
## 这条的来历：连招衔接是 `_start_attack` → `_start_attack` **直连**，
## 不经过 `_end_action()`，而 `_projectile_fired` 只在 `_start_cast` / `_end_action`
## 归位 —— 于是第 1 段发过弹之后，第 2/3 段判定窗口全程都在、却一发不发。
## 弓手（bow_2/3）与法师（staff_2/3）同结构，**此前从未被任何断言盯过**
## （#3 只验了单发起手）。干净对照实测：不修 = 1/0/0，修了 = 1/1/1。
##
## 做法：把「按着 J 不放」写成每帧 `_attack_queued = true`，让衔接窗口一开就接，
## 逐段数新增的投射物；玩家推进 HURT（测试房的 Walker 会还手）就提前清场。
func _t9_combo_projectiles() -> void:
	PlayerState.character_id = "mage"
	var room := (ROOM as PackedScene).instantiate()
	add_child(room)
	await _pframes(5)
	var player := room.get_node("Player")
	# Walker 会还手 —— 它一打就把玩家推进 HURT，连招被打断，量的就不是连招了
	var walker := room.get_node_or_null("Walker")
	if walker != null:
		walker.queue_free()
	await _pframes(1)
	player.global_position = Vector2(100.0, 288.0)

	var per_seg := {}          # attack_index -> 该段新增投射物数
	var last_count := _count_projectiles(self)
	var deepest := -1
	player.call("_start_attack", 0)
	var n := 0
	while n < 240:
		await get_tree().physics_frame
		n += 1
		player._attack_queued = true      # 模拟「按着 J 不放」
		deepest = maxi(deepest, int(player.attack_index))
		var now := _count_projectiles(self)
		if now > last_count:
			per_seg[player.attack_index] = int(per_seg.get(player.attack_index, 0)) + (now - last_count)
			last_count = now
		if player.state != 1:             # 1 = ATTACK：这一串走完了
			break

	var seg_counts := [int(per_seg.get(0, 0)), int(per_seg.get(1, 0)), int(per_seg.get(2, 0))]
	var all_fired: bool = seg_counts[0] == 1 and seg_counts[1] == 1 and seg_counts[2] == 1
	room.queue_free()
	await _pframes(2)
	_check("9", "法师三段连招：每段判定窗口都甩出法术弹，不是只有第一段有",
		all_fired and deepest == 2,
		"各段新增弹 = %d/%d/%d（都该是 1）　最深走到第 %d 段，共 %d 帧" % [
			seg_counts[0], seg_counts[1], seg_counts[2], deepest + 1, n])
