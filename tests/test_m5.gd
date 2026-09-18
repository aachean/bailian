extends Node
## 《百炼》M3 增量 2 自动验收：装备系统（掉落 / 穿戴 / 词条 / 存档 / 界面）
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m5.tscn
##
## 纪律：能自动判定的绝不留给用户回答。这里测的是「行为」，不是「实现」——
## 断言的是装备穿上去以后伤害倍率 / 血上限 / 挨打掉血的变化量，
## 不是「某个字段被赋值了」。

const ROOM := preload("res://scenes/stages/test_room.tscn")
const PICKUP := preload("res://scenes/components/pickup.tscn")
const BOSS := preload("res://scenes/enemies/boss.tscn")

## v2（2026-09-18）装备全部换新 id、词条改平铺 —— 这四条常量跟着换。
## 括号里是**区间**，实例取到的具体值由 uid 哈希决定（PlayerState.stat_of），
## 所以断言一律读 `PlayerState.stat_of(uid)`，不写死数字
const IRON_SWORD := "res://data/items/wp_u5251_0_u94c1u5251.tres"        # 武器·普通｜攻 1-3
const FLAME_BLADE := "res://data/items/wp_u5251_2_u7384u94c1u5251.tres"  # 武器·优秀｜攻 8-13
const IRON_HELM := "res://data/items/eq_u5934u76d4_1_u7cbeu94a2u76d4.tres"  # 头盔·精良｜血 8-13 防 3-5
const IRON_ARMOR := "res://data/items/eq_u80f8u7532_1_u94c1u7532.tres"   # 胸甲·精良｜血 12-19 防 6-9

var _pass := 0
var _fail := 0
var _room: Node2D
var _player: Node
var _walker: Node


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》M3 增量 2 自动验收 · 装备系统 ═══")
	_room = ROOM.instantiate()
	add_child(_room)
	for i in 5:
		await get_tree().physics_frame
	_player = _room.get_node("Player")
	_walker = _room.get_node("Walker")
	_walker.ai_enabled = false
	_reset_stats()

	await _t1_boss_drops_item()
	await _t2_walk_over_pickup()
	await _t3_equip_raises_attack()
	await _t4_same_slot_replaces()
	await _t5_unequip_returns_to_bag()
	await _t6_hp_bonus_raises_max_hp()
	await _t7_def_bonus_reduces_damage()
	await _t8_equipment_survives_snapshot()
	await _t9_bag_key_pauses_and_shows()
	await _t10_cursor_and_equip_by_key()
	await _t11_panel_shows_names_and_stats()
	await _t12_empty_bag_state()
	await _t13_no_translation_key_leak()
	await _t14_item_icons()
	await _t15_blade_takes_weapon_color()

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().paused = false          # 安全网：绝不能带着暂停退出
	get_tree().quit(0 if _fail == 0 else 1)


## 捡一件并立刻穿上，返回实例 uid。
## **装备走实例 uid**（强化等级挂在实例上），路径只是「型号」——
## 测试里也不能拿路径当装备的凭据，否则会穿上一件、背包里留一件
func _wear(path: String) -> String:
	var uid: String = PlayerState.add_item(path)
	PlayerState.equip(uid)
	return uid


## 包里有没有这个**型号**的装备。
## 直接写 bag.has(路径) 会永远为假（背包里存的是 uid#序号），
## 断言于是静默变成「永远不通过」——这类假绿比真红更难查
func _in_bag(path: String) -> bool:
	for u in PlayerState.bag:
		if PlayerState.path_of(str(u)) == path:
			return true
	return false


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


## 发一个真实按键事件 —— 背包界面读的是 keycode，不是 InputMap 动作
func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)


## 把成长值钉在基线：等级 1、无强化、无装备 —— 否则倍率断言算不准
func _reset_stats() -> void:
	PlayerState.set_equipment({}, [])
	PlayerState.level = 1
	PlayerState.exp = 0
	_player.set("level", 1)
	_player.set("exp_pts", 0)
	PlayerState.set_equipment(PlayerState.equipped, PlayerState.bag, {})   # 强化钉回基线（逐件之后没有全局等级了）
	PlayerState.shards = 0
	_player.call("_apply_upgrade")
	_player.get_node("Health").heal_full()


func _scale() -> float:
	return float(_player.get_node("Hitbox").damage_scale)


## 装备贡献的**平铺攻击点数**（v2 起攻击分两半：点数在 attack_flat、百分比在 damage_scale）
func _flat() -> int:
	return int(_player.get_node("Hitbox").attack_flat)


## 装备贡献的**平铺防御点数**（走 Health 的护甲曲线换成减伤）
func _defense() -> int:
	return int((_player.get_node("Health") as Health).defense)


## 图标指着哪一件 —— 比**资源路径**而不是 id：v2 换掉了全部装备 id，
## 断言里写死 id 会逼着每次重做装备都改测试，而漏改就是静默假绿。
## 路径是「这一件是什么」在测试里唯一稳定的说法
func _icon_path(icon: ItemIcon) -> String:
	if icon == null or icon.item() == null:
		return ""
	return icon.item().resource_path


func _max_hp() -> int:
	return int((_player.get_node("Health") as Health).max_hp)


func _place(x: float) -> void:
	_player.global_position = Vector2(x, 288.0)
	_player.velocity = Vector2.ZERO
	await _pframes(2)
	var n := 0
	while not _player.is_on_floor() and n < 60:
		await get_tree().physics_frame
		n += 1
	await _pframes(2)


## 地上还没被捡走的装备掉落物数量。
## 注意：掉落物挂到 get_tree().current_scene 下（怪在真实关卡里就是这么做的），
## 测试环境里 current_scene 是测试根，不是 _room —— 遍历 _room 会永远数到 0
func _item_pickups() -> int:
	var host := get_tree().current_scene
	if host == null:
		return 0
	var n := 0
	for c in host.get_children():
		var p = c.get("item_path")
		if p != null and str(p) != "":
			n += 1
	return n


## 杀掉关卡尽头的 Boss，必掉一件装备（掉落池 100% 触发）
func _t1_boss_drops_item() -> void:
	await _place(320.0)
	var boss := BOSS.instantiate()
	_room.add_child(boss)
	boss.global_position = Vector2(90.0, 288.0)     # 离玩家远点，别一掉就被吸走
	await _pframes(3)
	var before := _item_pickups()
	boss.get_node("Health").take_damage(9999, Vector2.ZERO, true, 1)
	await _pframes(3)
	var after := _item_pickups()
	boss.queue_free()
	await _pframes(2)
	_check("1", "打死 Boss 必掉一件装备（地上多出一个装备掉落物）",
		after > before,
		"地上装备掉落物 %d → %d（Boss 掉落率 100%%）" % [before, after])


## 走近掉落物自动吸附拾取，进背包
func _t2_walk_over_pickup() -> void:
	await _place(320.0)
	var before: int = PlayerState.bag.size()
	var p: Node2D = PICKUP.instantiate()
	p.set("item_path", IRON_SWORD)
	_room.add_child(p)
	p.global_position = _player.global_position + Vector2(6.0, 0.0)
	await _pframes(5)
	var gained: int = PlayerState.bag.size() - before
	var on_ground := _item_pickups()
	_check("2", "走到装备上自动拾取，进背包（地上不再留着）",
		gained == 1 and _in_bag(IRON_SWORD),
		"背包 %d → %d（+%d）　地上剩余装备掉落物 %d" % [
			before, PlayerState.bag.size(), gained, on_ground])


## 穿上武器：平铺攻击加上去，**倍率不动**（v2 起装备攻击是点数，不是百分比）
func _t3_equip_raises_attack() -> void:
	await _place(320.0)
	# 前面打 Boss 给了 60 经验，等级已经变了 —— 断言要先把成长值钉回基线
	_reset_stats()
	var flat_before := _flat()
	var scale_before := _scale()
	var uid := _wear(IRON_SWORD)
	await _pframes(2)
	var flat_after := _flat()
	var gained := int(PlayerState.stat_of(uid).get("atk", 0))
	_check("3", "穿上铁剑：平铺攻击 += 这一件 roll 到的点数，倍率不变",
		flat_after - flat_before == gained and flat_before == 0 and gained > 0 \
			and is_equal_approx(_scale(), scale_before),
		"平铺攻击 %d → %d（+%d）　倍率 %.2f（应不变）" % [
			flat_before, flat_after, gained, _scale()])


## 同部位再穿一件：旧的自动回背包，不丢东西，点数换成新件的
func _t4_same_slot_replaces() -> void:
	var bag_before: int = PlayerState.bag.size()
	var uid := _wear(FLAME_BLADE)
	await _pframes(2)
	var wearing := PlayerState.item_at(&"weapon")
	var back_in_bag := _in_bag(IRON_SWORD)
	var flat_now := _flat()
	var want := int(PlayerState.stat_of(uid).get("atk", 0))
	_check("4", "换同部位装备：旧的自动回背包，新件的点数生效",
		wearing != null and wearing.resource_path == FLAME_BLADE and back_in_bag \
			and flat_now == want and want >= 8 and want <= 13,
		"槽里=%s　铁剑回背包=%s　平铺攻击 %d（期望 %d，优秀档 8-13）　背包 %+d 件" % [
			(FLAME_BLADE if wearing == null else wearing.resource_path), str(back_in_bag),
			flat_now, want, PlayerState.bag.size() - bag_before])


## 卸下：装备回背包，点数回落到 0
func _t5_unequip_returns_to_bag() -> void:
	var before := _flat()
	PlayerState.unequip(&"weapon")
	await _pframes(2)
	var after := _flat()
	var slot_empty := PlayerState.item_at(&"weapon") == null
	var back := _in_bag(FLAME_BLADE)
	_check("5", "卸下武器：回背包、平铺攻击回落到 0",
		slot_empty and back and after == 0,
		"槽空=%s　玄铁剑回背包=%s　平铺攻击 %d → %d（期望 0）" % [
			str(slot_empty), str(back), before, after])


## 头盔的生命词条：血上限加多少、当前血就补多少（不是掉一截）
func _t6_hp_bonus_raises_max_hp() -> void:
	(_player.get_node("Health") as Health).heal_full()
	await _pframes(1)
	var hp_before := _max_hp()
	var cur_before := int((_player.get_node("Health") as Health).hp)
	var uid := _wear(IRON_HELM)
	await _pframes(2)
	var hp_after := _max_hp()
	var cur_after := int((_player.get_node("Health") as Health).hp)
	var gain := int(PlayerState.stat_of(uid).get("hp", 0))
	_check("6", "穿上精钢盔：血上限与当前血一起加上这一件 roll 到的血量",
		gain > 0 and hp_after - hp_before == gain and cur_after - cur_before == gain,
		"血上限 %d → %d　当前血 %d → %d（该件血 +%d）" % [
			hp_before, hp_after, cur_before, cur_after, gain])


## 胸甲的防御词条：走护甲曲线 def/(100+def)，挨同样一下掉血更少。
## **期望值在测试里手算**（不读 Health 的函数）—— 拿被测函数算期望等于没测
func _t7_def_bonus_reduces_damage() -> void:
	await _place(320.0)
	# **先清干净**：上一条断言装的精钢盔还戴在头上，它的防御会混进「无甲」这一档
	# （实测第一次跑就是这样：无甲掉 19 而不是 20，差值来自头盔的 4 点防）
	_reset_stats()
	var h := _player.get_node("Health") as Health
	h.heal_full()
	var no_armor: int = h.take_damage(20, Vector2.ZERO, false, 0)
	h.heal_full()
	var uid := _wear(IRON_ARMOR)
	await _pframes(2)
	var defense := _defense()
	var want_def := int(PlayerState.stat_of(uid).get("def", 0))
	h.heal_full()
	var with_armor: int = h.take_damage(20, Vector2.ZERO, false, 0)
	h.heal_full()
	# 手算：减伤 = def/(100+def)，再取 1 点保底
	var expect := maxi(1, int(round(20.0 * 100.0 / (100.0 + float(defense)))))
	_check("7", "穿上铁甲：防御变成平铺点数，同样一下 20 点按护甲曲线减伤",
		no_armor == 20 and defense == want_def and want_def > 0 and with_armor == expect,
		"无甲掉 %d　有甲掉 %d（期望 %d）　防御 %d（def/(100+def)=%.1f%%）" % [
			no_armor, with_armor, expect, defense,
			100.0 * float(defense) / (100.0 + float(defense))])


## 装备栏与背包进快照，读档原样回来
func _t8_equipment_survives_snapshot() -> void:
	await _place(320.0)
	PlayerState.add_item(IRON_SWORD)
	PlayerState.add_item(FLAME_BLADE)
	var snap := _room.call("collect") as Dictionary
	var equipped_before: Dictionary = PlayerState.equipped.duplicate()
	var bag_before: Array = PlayerState.bag.duplicate()

	PlayerState.set_equipment({}, [])
	await _pframes(1)
	var wiped: bool = PlayerState.equipped.is_empty() and PlayerState.bag.is_empty()

	_room.call("_apply_state", snap)
	await _pframes(2)
	var same_equipped: bool = PlayerState.equipped == equipped_before
	var same_bag: bool = PlayerState.bag == bag_before
	_check("8", "装备栏与背包进快照，读档原样回来",
		wiped and same_equipped and same_bag,
		"清空成功=%s　装备栏一致=%s（%s）　背包一致=%s（%d 件）" % [
			str(wiped), str(same_equipped), str(PlayerState.equipped),
			str(same_bag), PlayerState.bag.size()])


## B 键开背包：面板可见 + 世界真暂停；再按一次关掉并恢复
func _t9_bag_key_pauses_and_shows() -> void:
	await _place(320.0)
	var hud := _player.get_node("HUD")
	var panel := hud.get_node("BagPanel") as Panel
	var was := panel.visible

	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)
	var opened: bool = panel.visible and hud.call("is_bag_open") == true and get_tree().paused

	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)
	var closed: bool = (not panel.visible) and (not get_tree().paused)

	_check("9", "B 键开关装备背包：打开即暂停世界，再按关闭即恢复",
		(not was) and opened and closed,
		"初始关=%s　按后可见+暂停=%s　再按关闭+恢复=%s" % [
			str(not was), str(opened), str(closed)])


## 光标上下移动 + J 穿戴（用真实按键事件，不是动作）
func _t10_cursor_and_equip_by_key() -> void:
	var hud := _player.get_node("HUD")
	PlayerState.set_equipment({}, [FLAME_BLADE])
	await _pframes(2)
	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)

	var c0: int = int(hud.get("_cursor"))
	for i in ItemData.SLOT_IDS.size():
		_key(KEY_DOWN)
		await _pframes(2)
	var c1: int = int(hud.get("_cursor"))
	_key(KEY_J)
	await _pframes(3)

	var equipped_now := PlayerState.item_at(&"weapon")
	var bag_now: int = PlayerState.bag.size()

	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)

	_check("10", "背包里上下移动光标，按 J 把选中的装备穿上",
		c1 == ItemData.SLOT_IDS.size() and equipped_now != null \
			and equipped_now.resource_path == FLAME_BLADE and bag_now == 0,
		"光标 %d → %d（期望 %d=背包第一行）　穿上的=%s　背包剩 %d 件" % [
			c0, c1, ItemData.SLOT_IDS.size(),
			("无" if equipped_now == null else equipped_now.resource_path), bag_now])


## 面板上真的写出了装备名和词条 —— 防「静默空白 / 显示 key 本身」
func _t11_panel_shows_names_and_stats() -> void:
	var hud := _player.get_node("HUD")
	PlayerState.set_equipment({}, [])
	var helm_uid := _wear(IRON_HELM)
	var blade_uid := _wear(FLAME_BLADE)
	await _pframes(2)
	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)

	var equip_text := _hud_texts(hud)
	var hint: String = str((hud.get_node("BagPanel/Hint") as Label).text)
	var title: String = str((hud.get_node("BagPanel/Title") as Label).text)

	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)

	# 名字直接从**这一件自己的 name_key** 取（v2 换过全部装备 key，写死就会漏改）
	var has_weapon_name := equip_text.contains(tr(String(PlayerState.item_of(blade_uid).name_key)))
	var has_helm_name := equip_text.contains(tr(String(PlayerState.item_of(helm_uid).name_key)))
	var has_stat := equip_text.contains(tr("STAT_ATK")) or equip_text.contains(tr("STAT_HP"))
	var no_key_leak: bool = not equip_text.contains("ITEM_") and not title.contains("UI_") \
		and not hint.contains("UI_")
	_check("11", "面板写出装备名与词条，且不显示翻译 key 本身",
		has_weapon_name and has_helm_name and has_stat and no_key_leak and not hint.is_empty(),
		"武器名=%s　头盔名=%s　词条=%s　无 key 泄漏=%s\n              「%s」\n              操作提示「%s」" % [
			str(has_weapon_name), str(has_helm_name), str(has_stat),
			str(no_key_leak), equip_text.replace("\n", " ／ "), hint])


## 空背包：面板得说「（空）」，光标也不能越界
func _t12_empty_bag_state() -> void:
	var hud := _player.get_node("HUD")
	PlayerState.set_equipment({}, [])
	await _pframes(2)
	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)
	var cursor_before: int = int(hud.get("_cursor"))
	_key(KEY_DOWN)
	await _pframes(2)
	_key(KEY_DOWN)
	await _pframes(2)
	var cursor_after: int = int(hud.get("_cursor"))

	var grid := (hud.get_node("BagPanel/BagGrid") as GridContainer)
	var first_cell_icon := (grid.get_child(0).get_child(1) as ItemIcon)
	var detail: String = (hud.get_node("BagPanel/BagDetail") as Label).text
	var equip_text := _hud_texts(hud)

	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)

	_check("12", "背包空着时面板写明「（空）」，光标也不会越界",
		not first_cell_icon.visible and detail == tr("UI_BAG_EMPTY") \
			and equip_text.contains(tr("UI_BAG_EMPTY")) \
			and cursor_after <= ItemData.SLOT_IDS.size() - 1,
		"首格图标隐藏=%s　详情行=「%s」　光标 %d → %d（上限 %d）" % [
			str(not first_cell_icon.visible), detail,
			cursor_before, cursor_after, ItemData.SLOT_IDS.size() - 1])


## 界面上不许出现翻译 key 本身。
## 漏翻 / 拼错 key **不报任何错**，界面上就显示 "PANEL_SHARD" 这种字样 ——
## 只有截图和断言抓得到。这条就是为「静默失败」专门设的探针
## （写这条时立刻抓到一处：角色面板的 PANEL_SHARD 是个不存在的 key）
func _t13_no_translation_key_leak() -> void:
	var hud := _player.get_node("HUD")
	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)

	# 一次收全 HUD 上所有 Label 文本 —— 布局怎么改都不用动这条断言
	var texts: Array = hud.call("panel_texts")

	var leaks := PackedStringArray()
	var re := RegEx.new()
	re.compile("(UI|PANEL|HUD|ITEM|SLOT|STAT)_[A-Z_]+")
	for t in texts:
		for m in re.search_all(str(t)):
			leaks.append(m.get_string())

	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)

	_check("13", "两个面板上都不出现翻译 key 本身（漏翻是静默失败，只能这么抓）",
		leaks.is_empty(),
		"扫了 %d 段文本　泄漏的 key：%s" % [
			texts.size(), "无" if leaks.is_empty() else ", ".join(leaks)])


## 装备图标（用户反馈「武器装备没有图标」）：
## 面板每个槽 / 每行都要有图标，图标内容要指向那一件装备；地上掉落物同理。
## 图标是程序化画的（ItemIcon），所以除了「节点在不在」还要验「画的是哪一件」
func _t14_item_icons() -> void:
	var hud := _player.get_node("HUD")
	PlayerState.set_equipment({}, [])
	_wear(IRON_HELM)
	await _pframes(2)
	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)

	var equip_box := hud.get_node("BagPanel/EquipRows") as VBoxContainer
	var grid := hud.get_node("BagPanel/BagGrid") as GridContainer
	var helm_icon := equip_box.get_child(1).get_child(0) as ItemIcon
	var weapon_icon := equip_box.get_child(0).get_child(0) as ItemIcon
	var empty_bag_icon := (grid.get_child(0).get_child(1) as ItemIcon)

	var helm_ok: bool = _icon_path(helm_icon) == IRON_HELM and helm_icon.visible
	var empty_slot_ok: bool = weapon_icon != null and weapon_icon.item() == null and weapon_icon.visible
	var empty_row_ok: bool = empty_bag_icon != null and not empty_bag_icon.visible

	# 换一把武器：图标要跟着换（不是画完就定死）
	_wear(FLAME_BLADE)
	await _pframes(2)
	var switched: bool = _icon_path(weapon_icon) == FLAME_BLADE

	# 背包面板的装备行也用同一套图标（角色面板已并入背包 —— C 键废除）
	hud.call("refresh_bag")
	await _pframes(2)
	var char_box := hud.get_node("BagPanel/EquipRows") as VBoxContainer
	var char_weapon_icon := char_box.get_child(0).get_child(0) as ItemIcon
	var char_helm_icon := char_box.get_child(1).get_child(0) as ItemIcon
	var char_ok: bool = _icon_path(char_weapon_icon) == FLAME_BLADE \
		and _icon_path(char_helm_icon) == IRON_HELM
	var char_ids := "%s / %s" % [_id_of(char_weapon_icon), _id_of(char_helm_icon)]
	_press("bag")
	await _pframes(3)
	_release("bag")
	await _pframes(2)

	# 地上的装备掉落物也用同一套图标
	var drop: Node2D = PICKUP.instantiate()
	drop.set("item_path", IRON_SWORD)
	add_child(drop)
	drop.global_position = Vector2(120.0, 288.0)      # 离玩家远点，免得当场被吸走
	await _pframes(3)
	var drop_icon := drop.get_node_or_null("Visual") as ItemIcon
	var drop_ok: bool = _icon_path(drop_icon) == IRON_SWORD
	# 先取值再释放：queue_free 之后碰 drop_icon 会拿到已释放对象
	var drop_id := _id_of(drop_icon)
	var drop_size := Vector2.ZERO if drop_icon == null else drop_icon.size
	drop.queue_free()
	await _pframes(2)

	_check("14", "装备有图标：装备槽 / 背包行 / 角色面板 / 地上掉落物四处一致，换装跟着换",
		helm_ok and empty_slot_ok and empty_row_ok and switched and char_ok and drop_ok \
			and drop_size.x >= 18.0,
		"头盔槽图标=%s（%s）　空武器槽有框=%s　空背包行藏图标=%s\n              换装后武器图标=%s（%s）　角色面板=%s（%s）　掉落物=%s（%s，%.0f×%.0f px）" % [
			str(helm_ok), str(_id_of(helm_icon)), str(empty_slot_ok), str(empty_row_ok),
			str(switched), str(_id_of(weapon_icon)), str(char_ok), char_ids,
			str(drop_ok), str(drop_id), drop_size.x, drop_size.y])


## 手里的刀跟着武器变 —— 装备变强必须看得见，光面板数字不够
func _t15_blade_takes_weapon_color() -> void:
	await _place(320.0)
	PlayerState.set_equipment({}, [])
	await _pframes(2)
	var blade := _player.get_node("Visuals/Blade") as ColorRect
	var plain: Color = blade.color
	var plain_reach: float = blade.offset_right

	_wear(FLAME_BLADE)
	await _pframes(2)
	var armed: Color = blade.color
	var armed_reach: float = blade.offset_right
	var expect: Color = (load(FLAME_BLADE) as ItemData).tier_color().lightened(0.2)

	_check("15", "装备武器后手里的光刃换成武器品质色，刃也更长",
		not plain.is_equal_approx(armed) and armed.is_equal_approx(expect) \
			and armed_reach > plain_reach,
		"无武器 %s（长 %.0f） → 玄铁剑 %s（长 %.0f，期望色 %s）" % [
			str(plain), plain_reach, str(armed), armed_reach, str(expect)])


func _id_of(icon: ItemIcon) -> StringName:
	if icon == null or icon.item() == null:
		return &"无"
	return icon.item().id


## HUD 上全部 Label 文本拼成一个串（判定「某段文字在不在」用）
func _hud_texts(hud: Node) -> String:
	var out := ""
	for t in hud.call("panel_texts"):
		out += str(t) + "\n"
	return out
