extends Node
## 《百炼》自动验收：**5.6 消耗品预载**（回血符 / 回蓝符 / 补给包）。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m20.tscn
##
## ── 这一组要盯的四件事 ────────────────────────────────────────────
## 1. **两种形态并存不打架**：掉地走近生效（M3 已验收）**原样保留**，
##    新加的只是「买次数、按 6 / 7 主动用」那一份。改预载不该动掉落那条路。
## 2. **「按了没反应」要分着说**。这里一次就有**三种**不同的没反应：
##    没次数 / 生命已满 / 蓝量已满 —— 合并成一句 silent return 的话，
##    玩家分不清是没按上还是条件不满足（本项目最不接受的一种失败）。
## 3. **满血 / 满蓝不许白烧一张符**。「先扣次数再判断满没满」写反了测试也全绿，
##    因为次数确实在减、只是玩家亏了 —— 所以断言要卡住「次数不动」。
## 4. **技能栏的宽度红线**。5 格变 7 格之后横向 236px，仍在
##    「不超过屏幕 40%（240px @640）」以内 —— 这条线是神实测「挡视野」换来的，
##    以后有人加第 8 格时，这一组要能先红。
##
## 另外：`test_m16 #7` 盯的是「武器类型门」，这一组**不碰**它。

const ROOM := preload("res://scenes/stages/test_room.tscn")
## 技能栏横向上限（屏幕 640 的 40%）。**写死是有意的** —— 断言独立于实现
const BAR_MAX_W := 240.0
const CELL_COUNT := 7

var _pass := 0
var _fail := 0
var _room: Node2D
var _player: Node
var _hud: Node
var _health: Node


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》消耗品预载自动验收（5.6 第二条）═══")

	_room = ROOM.instantiate()
	add_child(_room)
	await _pframes(5)
	_player = _room.get_node("Player")
	_hud = _player.get_node("HUD")
	_health = _player.get_node("Health")
	# **必须关掉小怪 AI**：这一组断言的是「血 / 蓝 变了多少」，
	# 场上有只会打人的怪，读数就全是噪声（且失败时看起来像预载坏了）
	var walker := _room.get_node_or_null("Walker")
	if walker != null:
		walker.set("ai_enabled", false)

	await _t1_keymap()
	await _t2_buy_adds_charges()
	await _t3_poor_is_atomic()
	await _t4_supply_both()
	await _t5_drink_hp()
	await _t6_drink_mp()
	await _t7_empty_is_loud()
	await _t8_full_hp_costs_nothing()
	await _t9_full_mp_costs_nothing()
	await _t10_save_roundtrip()
	await _t11_reset_clears()
	await _t12_skill_bar_has_two_potion_cells()
	await _t13_bar_width_within_budget()
	await _t14_shop_left_column()

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().paused = false          # 安全网：绝不能带着暂停退出
	get_tree().quit(0 if _fail == 0 else 1)


# ── 1. 键位 ─────────────────────────────────────────────────────

## `6` / `7` 必须是真 action，而且动作名是从 POTION_KINDS 拼出来的那一个。
## 顺序错了的后果是「按 6 喝了蓝」—— 那种错没人会去代码里翻，只会以为是自己的手
func _t1_keymap() -> void:
	var kinds: Array = PlayerState.POTION_KINDS
	var named := "%s/%s" % [String(kinds[0]), String(kinds[1])]
	var has_actions := InputMap.has_action("item_hp") and InputMap.has_action("item_mp")
	_check("1a", "两个动作都在输入映射里，且顺序 = POTION_KINDS（第 6 格血、第 7 格蓝）",
		has_actions and named == "hp/mp", "POTION_KINDS = %s，动作存在 = %s" % [named, str(has_actions)])

	# 角标画的是 6 / 7，键位也必须真的是 6 / 7（画一个数、绑另一个键是最难发现的那种错）
	var want := {&"item_hp": 54, &"item_mp": 55}
	var got := {}
	for a in want:
		for e in InputMap.action_get_events(a):
			if e is InputEventKey:
				got[a] = (e as InputEventKey).physical_keycode
	# Dictionary.get 返回 Variant —— 这里**必须显式标 bool**，`:=` 推不出类型
	var ok: bool = got.get(&"item_hp", -1) == 54 and got.get(&"item_mp", -1) == 55
	_check("1b", "物理键位就是 6 / 7（54 / 55），与格子角标一致", ok,
		"item_hp=%s　item_mp=%s" % [str(got.get(&"item_hp")), str(got.get(&"item_mp"))])


# ── 2~4. 商店买 ──────────────────────────────────────────────────

func _t2_buy_adds_charges() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.gold = 1000
	var before := PlayerState.potion_charges(PlayerState.POTION_HP)
	var ok := PlayerState.buy_potion(PlayerState.POTION_HP)
	var after := PlayerState.potion_charges(PlayerState.POTION_HP)
	_check("2", "买一份回血符：扣 60 元宝 + 加 3 次",
		ok and PlayerState.gold == 940 and after - before == PlayerState.POTION_CHARGES,
		"元宝 1000→%d　次数 %d→%d（一份 = %d 次）" % [
			PlayerState.gold, before, after, PlayerState.POTION_CHARGES])


## 买不起时**一分都不许动**：钱扣了次数没加（或反过来）都是「付了钱没拿到东西」
func _t3_poor_is_atomic() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.gold = 10
	var before := PlayerState.potion_charges(PlayerState.POTION_HP)
	var ok := PlayerState.buy_potion(PlayerState.POTION_HP)
	_check("3", "元宝不够：返回 false，元宝与次数都不动（原子）",
		not ok and PlayerState.gold == 10 and PlayerState.potion_charges(PlayerState.POTION_HP) == before,
		"元宝=%d　次数=%d" % [PlayerState.gold, PlayerState.potion_charges(PlayerState.POTION_HP)])


func _t4_supply_both() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.gold = 500
	var ok := PlayerState.buy_supply()
	var hp := PlayerState.potion_charges(PlayerState.POTION_HP)
	var mp := PlayerState.potion_charges(PlayerState.POTION_MP)
	_check("4", "补给包：一口价 160，血蓝各加 5 次",
		ok and PlayerState.gold == 340 and hp == PlayerState.SUPPLY_CHARGES and mp == PlayerState.SUPPLY_CHARGES,
		"元宝 500→%d　血 %d 次 / 蓝 %d 次" % [PlayerState.gold, hp, mp])


# ── 5~9. 按 6 / 7 ────────────────────────────────────────────────

## 按 `6` 喝回血符：次数 -1、血真的涨、而且**飘了字**
## （飘字是玩家唯一能看到的「刚才那一下生效了」的证据，没有它就只能靠猜）
func _t5_drink_hp() -> void:
	_arm(3)
	var max_hp := int(_health.get("max_hp"))
	# 从 1 点血喝：这样「回了多少」不会被上限截断，能直接对上 ratio
	_health.set("hp", 1)
	var hp0 := int(_health.get("hp"))
	var floats0 := _float_count()
	await _tap("item_hp")
	var hp1 := int(_health.get("hp"))
	var left := PlayerState.potion_charges(PlayerState.POTION_HP)
	# 回多少 = 上限的 40%（至少 1 点），不许写死数字 —— 数字只有一个家
	var want := int(ceil(float(max_hp) * 0.40))
	_check("5", "按 6：次数 -1、回血 = 上限 × 40%、头顶飘字",
		left == 2 and hp1 > hp0 and hp1 - hp0 == want and _float_count() > floats0,
		"血 %d→%d（+%d，期望 +%d／上限 %d）　次数 3→%d　飘字 %d→%d" % [
			hp0, hp1, hp1 - hp0, want, max_hp, left, floats0, _float_count()])


func _t6_drink_mp() -> void:
	_arm(3)
	var max_mp := int(_player.get("max_mp"))
	_player.set("mp", 0)
	await _tap("item_mp")
	var mp := int(_player.get("mp"))
	var left := PlayerState.potion_charges(PlayerState.POTION_MP)
	var want := int(ceil(float(max_mp) * 0.60))
	_check("6", "按 7：次数 -1、回蓝 = 上限 × 60%",
		left == 2 and mp == want,
		"蓝 0→%d（期望 %d／上限 %d）　次数 3→%d" % [mp, want, max_mp, left])


## 没次数了必须**说出来**。静默的话玩家会以为按键坏了
func _t7_empty_is_loud() -> void:
	_arm(0)
	_health.set("hp", 1)
	var hp0 := int(_health.get("hp"))
	var floats0 := _float_count()
	await _tap("item_hp")
	_check("7", "0 次时按 6：不生效、不出现负数、但**必须出提示**（不静默）",
		int(_health.get("hp")) == hp0
			and PlayerState.potion_charges(PlayerState.POTION_HP) == 0
			and _float_count() > floats0,
		"血 %d（没变）　次数 %d（没变负）　飘字 %d→%d" % [
			int(_health.get("hp")), PlayerState.potion_charges(PlayerState.POTION_HP),
			floats0, _float_count()])


## **满血不扣次数** —— 这条是「先扣再判」写反之后唯一会露馅的地方：
## 写反了次数照样在减，只是玩家白亏，而别的断言全是绿的
func _t8_full_hp_costs_nothing() -> void:
	_arm(3)
	_health.call("heal_full")
	var floats0 := _float_count()
	await _tap("item_hp")
	_check("8", "满血时按 6：**次数一点不扣**，只飘一句原因",
		PlayerState.potion_charges(PlayerState.POTION_HP) == 3 and _float_count() > floats0,
		"次数 %d（必须还是 3）　飘字 %d→%d" % [
			PlayerState.potion_charges(PlayerState.POTION_HP), floats0, _float_count()])


func _t9_full_mp_costs_nothing() -> void:
	_arm(3)
	_player.set("mp", int(_player.get("max_mp")))
	var floats0 := _float_count()
	await _tap("item_mp")
	_check("9", "满蓝时按 7：次数一点不扣，只飘一句原因",
		PlayerState.potion_charges(PlayerState.POTION_MP) == 3 and _float_count() > floats0,
		"次数 %d（必须还是 3）　飘字 %d→%d" % [
			PlayerState.potion_charges(PlayerState.POTION_MP), floats0, _float_count()])


# ── 10~11. 存档 ──────────────────────────────────────────────────

func _t10_save_roundtrip() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.add_potion_charges(PlayerState.POTION_HP, 7)
	PlayerState.add_potion_charges(PlayerState.POTION_MP, 2)
	var snap := PlayerState.save_to()
	PlayerState.potions.clear()
	PlayerState.load_from(snap)
	var hp := PlayerState.potion_charges(PlayerState.POTION_HP)
	var mp := PlayerState.potion_charges(PlayerState.POTION_MP)
	# 旧档（没有 potions 字段）要能读、且当成「没买过」——**不是**崩、也不是留旧值
	PlayerState.potions.clear()
	var legacy := snap.duplicate()
	legacy.erase("potions")
	PlayerState.load_from(legacy)
	var legacy_ok := PlayerState.potion_charges(PlayerState.POTION_HP) == 0 \
		and PlayerState.potion_charges(PlayerState.POTION_MP) == 0
	_check("10", "存档往返保住次数；旧档缺字段 = 0（纯增量，不作废进度）",
		hp == 7 and mp == 2 and legacy_ok,
		"往返后 血 %d / 蓝 %d　旧档读回 血 %d / 蓝 %d" % [
			hp, mp, PlayerState.potion_charges(PlayerState.POTION_HP),
			PlayerState.potion_charges(PlayerState.POTION_MP)])


## 开新档不能带着上一档的符 —— 那就是「新档白送消耗品」
func _t11_reset_clears() -> void:
	PlayerState.add_potion_charges(PlayerState.POTION_HP, 9)
	PlayerState.reset_for_new_game()
	_check("11", "开新档：次数清零（不继承上一档的符）",
		PlayerState.potion_charges(PlayerState.POTION_HP) == 0
			and PlayerState.potion_charges(PlayerState.POTION_MP) == 0,
		"血 %d / 蓝 %d" % [PlayerState.potion_charges(PlayerState.POTION_HP),
			PlayerState.potion_charges(PlayerState.POTION_MP)])


# ── 12~13. 技能栏 ────────────────────────────────────────────────

func _t12_skill_bar_has_two_potion_cells() -> void:
	_arm(2)
	# **显式刷一次**：HUD 的 refresh 挂在 _process 上，而这一组全程没有让出帧，
	# 格子里还是上一轮的数字（读到的会是「上一次的真相」）
	_hud.call("refresh_skill_bar")
	var bar := _hud.get_node_or_null("SkillBar")
	if bar == null:
		_check("12", "技能栏存在", false, "找不到 HUD/SkillBar")
		return
	var cells := bar.get_children()
	var ok_count: bool = cells.size() == CELL_COUNT
	var pot_ok := false
	var count_txt := ""
	var dim_when_empty := false
	if ok_count:
		var hp_icon := cells[5].get_node_or_null("Icon") as ItemIcon
		var mp_icon := cells[6].get_node_or_null("Icon") as ItemIcon
		var hp_cnt := cells[5].get_node_or_null("Count") as Label
		var mp_cnt := cells[6].get_node_or_null("Count") as Label
		if hp_icon != null and mp_icon != null and hp_cnt != null and mp_cnt != null:
			pot_ok = hp_icon.kind == &"potion_hp" and mp_icon.kind == &"potion_mp" \
				and (cells[5].get_node_or_null("Cooldown") == null)
			count_txt = "%s/%s" % [hp_cnt.text, mp_cnt.text]
		# 0 次 = 这张符此刻是废的：图标压暗 + 灰 0（暗就是提示，不弹窗）
		PlayerState.potions.clear()
		_hud.call("refresh_skill_bar")
		if hp_icon != null and hp_cnt != null:
			dim_when_empty = hp_cnt.text == "0" and hp_icon.modulate.r < 0.9
	_check("12", "技能栏 7 格：后两格是消耗品（图标对、没有冷却遮罩）、格内写剩余次数、0 次变暗",
		ok_count and pot_ok and count_txt == "2/2" and dim_when_empty,
		"格数 %d　后两格图标对 = %s　次数显示 %s　0 次时变暗 = %s" % [
			cells.size(), str(pot_ok), count_txt, str(dim_when_empty)])


## 7 格横向不许越过 240px。这条线来自神实测的「挡视野」，不是审美偏好 ——
## 而且它**只能靠算**：多 30px 在 640×360 里肉眼不一定看得出来，但地面被盖住了
func _t13_bar_width_within_budget() -> void:
	var bar := _hud.get_node_or_null("SkillBar")
	if bar == null:
		_check("13", "技能栏宽度", false, "找不到 HUD/SkillBar")
		return
	var cells := bar.get_children()
	if cells.is_empty():
		_check("13", "技能栏宽度", false, "SkillBar 一个格子都没有")
		return
	var w := 0.0
	for c in cells:
		w += float((c as Control).custom_minimum_size.x)
	var sep := float(bar.get_theme_constant("separation"))
	w += sep * float(maxi(cells.size() - 1, 0))
	_check("13", "技能栏横向 ≤ 屏幕 40%%（%dpx）—— 5 格变 7 格之后仍守住" % int(BAR_MAX_W),
		w <= BAR_MAX_W,
		"%d 格 × %.0f + %d 段间距 %.0f = %.0fpx（上限 %.0f）" % [
			cells.size(), float((cells[0] as Control).custom_minimum_size.x),
			cells.size() - 1, sep, w, BAR_MAX_W])


# ── 14. 商店左栏 ─────────────────────────────────────────────────

func _t14_shop_left_column() -> void:
	var shop := _player.get_node_or_null("ShopPanel")
	if shop == null:
		_check("14", "商店面板存在", false, "找不到 player/ShopPanel")
		return
	# **摆满**：7 件货架 = 真实情形，这样「11 条刚好顶到上限」这条才真的被走一遍。
	# 只放 1 件的话，容量这条断言永远是「5 ≤ 11」那种不会红的假绿。
	# 路径取真池子、**不手编** —— 编出来的路径一旦不存在，界面上就是一行 "?"
	var offers: Array = []
	for t in [ItemData.Tier.COMMON, ItemData.Tier.FINE, ItemData.Tier.UNCOMMON]:
		offers.append_array(GameProgress.drop_pool(t))
	PlayerState.shop_offers = offers.slice(0, 7)
	var entries: Array = shop.call("_left_entries")
	var tail: Array = []
	for i in range(7, entries.size()):
		tail.append(str(entries[i]))
	var cap: int = shop.get_script().get_script_constant_map()["GEAR_ROWS"]
	var want_tail := ["revive", "item_hp", "item_mp", "supply"]
	# 左栏**没有滚动**：条目比行数多 = 「上架了但商店里看不见」，而且哪里都不会红。
	# 所以这一组同时卡三件事：货架数、尾部顺序、总条数**正好**顶到上限
	var ok: bool = tail == want_tail and entries.size() == 7 + 4 and entries.size() <= cap
	_check("14",
		"商店左栏：7 件货架 + 还魂丹 / 回血符 / 回蓝符 / 补给包 = 11 条，正好顶到 %d 行上限" % cap,
		ok, "尾部 = %s　共 %d 条（上限 %d）" % [str(tail), entries.size(), cap])


# ── 工具 ─────────────────────────────────────────────────────────

## 把两种符的次数设成固定值，并把血蓝摆到一个「能喝」的状态。
## **顺手把蓝量自然恢复的计时器清零** —— 它每 30 物理帧回 1 点，
## 撞上正好要在这一帧回的话，「按 7 回了多少」就永远差 1（而且时灵时不灵）
func _arm(charges: int) -> void:
	PlayerState.potions.clear()
	if charges > 0:
		PlayerState.add_potion_charges(PlayerState.POTION_HP, charges)
		PlayerState.add_potion_charges(PlayerState.POTION_MP, charges)
	_player.set("_mp_regen_tick", 0)
	_player.set("mp", 0)
	_health.set("hp", 1)


## 按一下某个 action（走 InputMap 真实按下 / 抬起）。
## **不能用 InputEventAction**：玩家读的是 `Input.is_action_just_pressed`，
## 事件对象得经过 InputMap 才算数 —— 这条坑在本项目踩过
func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


## 场上现有的飘字数量（Label 直接挂在 current_scene 下）。
## 用它断言「出了提示」—— 表现层的存在性比文字内容更稳
func _float_count() -> int:
	var cs := get_tree().current_scene
	if cs == null:
		return 0
	var n := 0
	for c in cs.get_children():
		if c is Label:
			n += 1
	return n


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
