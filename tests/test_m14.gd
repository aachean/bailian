extends Node
## 《百炼》M3 第 3 步自动验收：**经济**（元宝 / 商店 / 出售 / 消耗品掉落）。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m14.tscn
##
## 设计依据：计划 §3.7（2026-09-14 定）——
##   · 元宝是**唯一通用货币**，与精铁刻意互不兑换（两笔钱各管各的）
##   · 元宝来源只有两条：打怪掉小额 + 出售装备
##   · 消耗品掉在地上**走近直接生效**，不进背包；满血 / 满蓝也喝
##     （2026-09-15 神的黑盒反馈推翻了原「满了不收」—— 白喝是玩家自己走进去的）
##   · 商店随第一个副本首通解锁；出售进账 = 定价 × 折价率（ShopData）
##
## 断言盯的都是「静默就完蛋」的接缝：
##   · 卖价算法只住在 ShopData 一处；买来的是**新实例**（不是共享型号）
##   · 穿在身上的装备卖不掉（先卸下再来）
##   · 满血的药躺在地上等人；掉了血才被吸走
##   · 强化仍走精铁 —— 经济上线不许动老货币的一根毫毛

const TOWN := preload("res://scenes/stages/town.tscn")
const PICKUP := preload("res://scenes/components/pickup.tscn")
const SHOP_STAND := preload("res://scenes/core/shop_stand.tscn")
## 测哪一件**从货架数据里挑**，不写死路径。
## v2 换过全部装备资源、也换过货架内容（现在 11 件「普通」档）——
## 写死路径的测试在数据一改时就变成「元件不存在 → 一路静默失败」，
## 而失败信息看起来像经济算错了，查起来最费时间
func _stock_items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	if PlayerState.shop() == null:
		return out
	for p in PlayerState.shop().stock:
		var it := load(str(p)) as ItemData
		if it != null:
			out.append(it)
	return out


## 货架里**当前角色穿得上**的最便宜武器（#2/#3/#7 要穿上）。
## ⚠️ 必须过 `can_equip`：v2 货架里有四种武器（剑/刀/弓/杖），
## 挑到一把刀 `equip()` 会静默失败 —— 后面的账目断言会变成「穿上时就把装备卖了」
## 这种看起来像经济算错的假红（实测踩过一次）
func _stock_weapon() -> ItemData:
	var best: ItemData = null
	for it in _stock_items():
		if it.slot != ItemData.Slot.WEAPON or not PlayerState.can_equip(it):
			continue
		if best == null or it.gold_price < best.gold_price:
			best = it
	return best


## 货架第一行（商店面板按 J 买的就是它）
func _stock_first() -> ItemData:
	var items := _stock_items()
	return null if items.is_empty() else items[0]

var _pass := 0
var _fail := 0
var _town: Node
var _player: Node
var _snapshot: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》经济 自动验收 ═══")

	_snapshot = PlayerState.save_to()      # 测试动的是全局 autoload，收尾还回去
	_town = TOWN.instantiate()
	add_child(_town)
	await _pframes(6)
	_player = _town.get_node("Player")

	await _t1_gold_basics()
	await _t2_buy_sell_loop()
	await _t3_sell_rules()
	await _t4_shop_panel_buys()
	await _t5_stand_unlock_gate()
	await _t6_potion_gate()
	await _t7_forge_still_uses_shards()
	await _t8_save_roundtrip()
	await _t9_data_consistency()
	await _t10_drop_pools()
	await _t11_disassemble_craft_loop()

	# 还原全局状态（本进程内 autoload 已被改动；存档文件没碰过，
	# 只有 T5 动了通关表 —— 它自己负责了备份还原）
	PlayerState.load_from(_snapshot)

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	Audio.stop_all()
	_town.queue_free()
	await _pframes(2)
	get_tree().paused = false          # 安全网：绝不能带着暂停退出
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


func _tap_key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _fresh_state() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.shards = 0


# ── 断言 ───────────────────────────────────────────────────────

## 元宝进出的门卫：花不起就是花不起，一个子儿都不能变成负数
func _t1_gold_basics() -> void:
	_fresh_state()
	PlayerState.add_gold(100)
	var got_signal: bool = PlayerState.gold == 100
	PlayerState.spend_gold(30)
	var after_spend: bool = PlayerState.gold == 70
	var refused: bool = not PlayerState.spend_gold(999) and PlayerState.gold == 70
	PlayerState.add_gold(0)
	var no_zero_add: bool = PlayerState.gold == 70
	_check("1", "元宝：加 / 花 / 花不起拒绝 / 零额无效",
		got_signal and after_spend and refused and no_zero_add,
		"100 → 花 30 → 70；花 999 被拒；加 0 不动")


## 买卖闭环：货架内买得到、买来是新实例、卖价 = 定价 × 折价率（半价）
func _t2_buy_sell_loop() -> void:
	_fresh_state()
	var w := _stock_weapon()
	var price := 0 if w == null else w.gold_price
	var half := int(floor(float(price) * PlayerState.shop().sell_ratio))
	PlayerState.add_gold(100)
	var uid := PlayerState.buy_item(w.resource_path) if w != null else ""
	var bought := w != null and not uid.is_empty() and PlayerState.bag.has(uid) \
		and PlayerState.gold == 100 - price and PlayerState.item_of(uid) != null
	# 新实例：uid 带序号，不是资源路径本身（型号 ≠ 实例）
	var is_instance: bool = uid.contains(PlayerState.UID_SEP)
	var gain := PlayerState.sell_item(uid)
	var sold := gain == half and PlayerState.gold == 100 - price + half \
		and not PlayerState.bag.has(uid)
	_check("2", "买卖闭环：按定价买进 → 半价卖出；实例 uid；账目吻合",
		bought and is_instance and sold,
		"这一件定价 %d　元宝 100 → %d（买）→ %d（卖，floor(%d×%.1f)=%d）" % [
			price, 100 - price, PlayerState.gold, price,
			PlayerState.shop().sell_ratio, half])


## 卖的三条规矩：货架外的不卖（那是「买」的反向）；穿在身上的不收；没这东西不收
func _t3_sell_rules() -> void:
	_fresh_state()
	var w := _stock_weapon()
	var price := 0 if w == null else w.gold_price
	var half := int(floor(float(price) * PlayerState.shop().sell_ratio))
	PlayerState.add_gold(100)
	var not_in_bag := PlayerState.sell_item(w.resource_path) == 0   # 路径 ≠ 背包里的实例
	var uid := PlayerState.buy_item(w.resource_path)
	PlayerState.equip(uid)                                     # 穿上（离开背包）
	var worn := PlayerState.sell_item(uid) == 0 \
		and PlayerState.equipped_uid(&"weapon") == uid \
		and PlayerState.gold == 100 - price
	var gold_worn := PlayerState.gold
	var unequipped := PlayerState.unequip(&"weapon")
	var back_gain := PlayerState.sell_item(unequipped)
	var sold_after_unequip: bool = back_gain == half \
		and PlayerState.gold == 100 - price + half
	_check("3", "出售规矩：身上穿的卖不掉；卸下后才能卖；没进过背包的路径不收",
		not_in_bag and worn and sold_after_unequip,
		"没进过包的不收=%s　穿上时 sell=0 且元宝 %d（期望 %d）　卸下后 sell=%d（期望 %d）元宝 %d（期望 %d）" % [
			str(not_in_bag), gold_worn, 100 - price, back_gain, half,
			PlayerState.gold, 100 - price + half])


## 商店面板（真实按键）：J 买货架第一件、买不起有话、Esc 关门
func _t4_shop_panel_buys() -> void:
	_fresh_state()
	PlayerState.add_gold(50)
	var first := _stock_first()
	var price := 0 if first == null else first.gold_price
	var panel := _player.get_node("ShopPanel")
	panel.call("open")
	await _pframes(2)
	var opened: bool = bool(panel.call("is_open")) and get_tree().paused
	_tap_key(KEY_J)                       # 货架第一件
	await _pframes(2)
	var bought: bool = PlayerState.gold == 50 - price and PlayerState.bag.size() == 1
	_tap_key(KEY_ESCAPE)
	await _pframes(2)
	var closed: bool = not bool(panel.call("is_open")) and not get_tree().paused
	_check("4", "商店面板：开 → J 买下货架第一件 → Esc 关（暂停随面板走）",
		opened and bought and closed,
		"第一件「%s」定价 %d　元宝 50 → %d；背包 +1；Esc 后不暂停" % [
			("—" if first == null else str(first.display_name)), price, PlayerState.gold])


## 商店台的门：首通砺场才开张（计划 §3.7）。通关表动了要原样还回去
func _t5_stand_unlock_gate() -> void:
	var path := SaveManager.slot_path(SaveManager.current_slot)
	var had := FileAccess.file_exists(path)
	var before := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()

	var stand := SHOP_STAND.instantiate()
	add_child(stand)
	await _pframes(2)
	GameProgress.reset_progress()
	var locked: bool = not bool(stand.call("_unlocked"))
	SaveManager.mark_cleared(&"lichang")
	var unlocked: bool = bool(stand.call("_unlocked"))
	stand.queue_free()

	# 还回去（这是玩家真正在玩的那份存档）
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(before)
			f.close()
	GameProgress.reset_progress()
	_check("5", "商店台：砺场未通 → 没开张；通关 → 开张（解锁门读通关表）",
		locked and unlocked,
		"开张与否只看 SaveManager 的通关表，商店台不存第二份")


## 消耗品（2026-09-15 黑盒反馈修订）：**不管满不满，靠近就喝**；
## 「防止没靠近就被用」由拾取距离管 —— 10px 内才生效，远处躺着不动
func _t6_potion_gate() -> void:
	var h := _player.get_node("Health") as Health
	h.heal_full()

	# 满血：也喝（白喝是玩家自己走进去的），血不掉就是全部效果
	var hp_pot := PICKUP.instantiate()
	hp_pot.set("potion", &"hp")
	add_child(hp_pot)
	hp_pot.global_position = _player.global_position
	await _pframes(12)
	var drank_at_full: bool = not is_instance_valid(hp_pot) and h.hp == h.max_hp

	# 距离门：放远了不吸不喝；把玩家挪过去才被喝掉
	h.heal_full()
	var far := PICKUP.instantiate()
	far.set("potion", &"hp")
	add_child(far)
	far.global_position = _player.global_position + Vector2(300.0, 0.0)
	await _pframes(12)
	var waited: bool = is_instance_valid(far) and not far.get("_collected")
	far.global_position = _player.global_position
	await _pframes(12)
	var drank_when_close: bool = not is_instance_valid(far) and h.hp == h.max_hp

	# 回蓝：满蓝也喝；有缺口喝下去真回
	var mp_pot := PICKUP.instantiate()
	mp_pot.set("potion", &"mp")
	add_child(mp_pot)
	mp_pot.global_position = _player.global_position
	_player.set("mp", _player.get("max_mp"))
	await _pframes(12)
	var mp_drank_at_full: bool = not is_instance_valid(mp_pot) \
		and int(_player.get("mp")) >= int(_player.get("max_mp"))
	_player.set("mp", 10)
	var mp_pot2 := PICKUP.instantiate()
	mp_pot2.set("potion", &"mp")
	add_child(mp_pot2)
	mp_pot2.global_position = _player.global_position
	await _pframes(12)
	# 用 ≥ 而不是 ==：拾取后那几帧里还有**自然回蓝**（每 30 帧 +1）在跑，
	# 它只会往上加 —— 药的 25 点至少要到位，多出来的是自然恢复的账
	var mp_filled: bool = not is_instance_valid(mp_pot2) \
		and int(_player.get("mp")) >= 35

	_check("6", "消耗品：满状态也直接喝；远处不吸不喝，靠近才生效",
		drank_at_full and waited and drank_when_close and mp_drank_at_full and mp_filled,
		"满血=%s 远候=%s 近喝=%s 满蓝=%s 回蓝=%s" % [
			drank_at_full, waited, drank_when_close, mp_drank_at_full, mp_filled])


## 老货币一分不许动：强化仍然只走精铁；卖装备不产精铁（两条管道互不兑换）
func _t7_forge_still_uses_shards() -> void:
	_fresh_state()
	var w := _stock_weapon()
	var price := 0 if w == null else w.gold_price
	var half := int(floor(float(price) * PlayerState.shop().sell_ratio))
	PlayerState.add_gold(500)
	PlayerState.shards = 10
	var uid := PlayerState.buy_item(w.resource_path)
	var forged := PlayerState.forge_once(uid)
	var ok: bool = forged and PlayerState.forge_level(uid) == 1 \
		and PlayerState.shards < 10 and PlayerState.gold == 500 - price
	var gain := PlayerState.sell_item(uid)
	_check("7", "两条管道：强化扣精铁不动元宝；出售进元宝不动精铁",
		ok and gain == half and PlayerState.shards >= 0 \
			and PlayerState.gold == 500 - price + half,
		"精铁 10 → %d（强化），元宝 500 → %d → %d（卖）" % [
			PlayerState.shards, 500 - price, PlayerState.gold])


## 存档：gold 随档走；旧档没有这字段 → 安静从 0 起
func _t8_save_roundtrip() -> void:
	_fresh_state()
	PlayerState.add_gold(77)
	var d := PlayerState.save_to()
	var saved: bool = int(d.get("gold", -1)) == 77
	PlayerState.load_from(d)
	var reloaded: bool = PlayerState.gold == 77
	PlayerState.load_from({"level": 3})          # 旧档形状：没有 gold 键
	var legacy: bool = PlayerState.gold == 0 and PlayerState.level == 3
	_check("8", "存档：gold 进档出档；旧档缺字段 → 0 起步（VERSION 9 纯增量）",
		saved and reloaded and legacy,
		"save_to 带 gold=77；load_from({level:3}) → gold=0")


## 数据一致性：**每一件装备**都填了定价、货架都指向真装备、怪的掉落账能对上。
## v2 起装备从 9 件变成 132 件，所以这里扫目录而不是点名几件 ——
## 漏填定价的装备会变成「商店里标 0 元宝」这种没人发现的漏洞
func _t9_data_consistency() -> void:
	var shop := PlayerState.shop()
	var stock_ok := shop != null and not shop.stock.is_empty()
	for p in (shop.stock if shop != null else []):
		var it := load(str(p)) as ItemData
		if it == null or it.gold_price <= 0:
			stock_ok = false
	# 全部装备都有定价（含不在货架上的）
	var dir := "res://data/items"
	var files := ResDir.files(dir)
	var priced := 0
	var unpriced: Array[String] = []
	for f in files:
		var it := load("%s/%s" % [dir, f]) as ItemData
		if it == null:
			continue
		if it.gold_price > 0:
			priced += 1
		else:
			unpriced.append(str(it.id))
	var all_priced: bool = files.size() >= 132 and unpriced.is_empty()
	var boss2 := load("res://data/enemies/boss2.tres") as EnemyData
	var walker := load("res://data/enemies/walker.tres") as EnemyData
	var luhou := load("res://data/enemies/boss_luhou.tres") as EnemyData
	var drops_ok := boss2 != null and boss2.drop_gold == 40 \
		and walker != null and walker.drop_gold == 2 \
		and luhou != null and luhou.drop_gold == 0     # 炉喉收尾不打架，不掉钱
	var sell_ok: bool = shop != null and shop.sell_price(40) == 20
	_check("9", "数据：每件装备都有定价；货架指到真装备；怪掉落账目；炉喉不掉钱",
		stock_ok and all_priced and drops_ok and sell_ok,
		"装备 %d 件有定价／%d 件（没定价的：%s）　卖价公式只在 ShopData 一处：floor(40×0.5)=20" % [
			priced, files.size(), "无" if unpriced.is_empty() else ", ".join(unpriced.slice(0, 5))])


## 副本掉落档次池（批 5）。守三条：
##   ① 六个副本的池与设计表对上（漏落的副本会静默回落到怪身上的固定池，档次就乱了）
##   ② **途径隔离**（ADR-0016）：任何实物池里不许出现极品(3)及以上 —— 那些只能来自打造
##   ③ `roll_drop` 掷出来的件真的属于池内档次（索引按 tier 分桶没错位）
const POOL_WANT := {
	&"lichang": [0], &"duancuiqu": [0, 1], &"luhou": [1],
	&"canjianlin": [1, 2], &"xiushi": [2], &"zhongxin": [2],
}
func _t10_drop_pools() -> void:
	var out: Array[String] = []
	var table_ok := true
	var isolation_ok := true
	for id in POOL_WANT:
		var d := GameProgress.dungeon(id)
		if d == null:
			table_ok = false
			out.append("%s 不在副本序列里" % id)
			continue
		var got: Array = d.drop_tiers
		if got != (POOL_WANT[id] as Array):
			table_ok = false
			out.append("%s 池=%s（期望 %s）" % [id, str(got), str(POOL_WANT[id])])
		for t in got:
			if int(t) >= ItemData.Tier.RARE:
				isolation_ok = false
				out.append("%s 的实物池里出现了 %d 档（≥极品）" % [id, int(t)])

	# ③ roll 的件必须属于池内档次；掷 60 次砺场池（单档普通），应全落普通
	var roll_ok := true
	var bad_tier := -1
	for i in 60:
		var path := GameProgress.roll_drop([0])
		var it := load(path) as ItemData
		if it == null or it.tier != ItemData.Tier.COMMON:
			roll_ok = false
			bad_tier = -1 if it == null else int(it.tier)
			break
	var pool_size := GameProgress.drop_pool(ItemData.Tier.COMMON).size()
	_check("10", "掉落档次池：六副本对表；实物池无极品+；roll 的件属于池内档次",
		table_ok and isolation_ok and roll_ok,
		"　".join(out) + "　砺场掷 60 次全普通=%s（普通池 %d 件，坏档：%d）" % [
			str(roll_ok), pool_size, bad_tier])


## 回收闭环（批 6 · 原则 5.5）。守四条：
##   ① 分解：材料到账（精铁进 shards、玄铁进 materials）、装备离包；**穿在身上的不收**
##   ② 打造：档没解锁 / 材料不够都不发货；**付料是原子的**（不够就一分不动）
##   ③ 制书：买 = 永久解锁并扣元宝；**重复买直接拒绝**（重复付费不该是可能的事故）
##   ④ 铁律读进数据：每档分解产量 < 该档打造成本（堵「分解→重造」白嫖）
##   装备全部从数据读（drop_pool 里拿现成件），不写死路径
func _t11_disassemble_craft_loop() -> void:
	_fresh_state()
	# ── ① 分解 ──
	var uncommon := GameProgress.drop_pool(ItemData.Tier.UNCOMMON)[0]   # 优秀档
	var uid: String = PlayerState.add_item(uncommon)
	var yld := PlayerState.disassemble(uid)
	var d := PlayerState.disassemble_table().yield_for(int(ItemData.Tier.UNCOMMON))
	var iron_gain := int(d.get("mat_refined_iron", 0))
	var black_gain := int(d.get("mat_black_iron", 0))
	var gone := not PlayerState.bag.has(uid)
	var iron_ok: bool = PlayerState.shards == iron_gain and iron_gain > 0
	var black_ok: bool = PlayerState.material_count(&"mat_black_iron") == black_gain
	# 穿在身上的不收：从优秀档里挑一件当前角色穿得上的 → 穿上 → 拆（应失败、槽还在）
	var wear_uid := ""
	var wear_slot := &""
	for p in GameProgress.drop_pool(ItemData.Tier.UNCOMMON):
		var cand := load(str(p)) as ItemData
		if cand != null and PlayerState.can_equip(cand):
			wear_uid = PlayerState.add_item(str(p))
			wear_slot = ItemData.SLOT_IDS[int(cand.slot)]   # 枚举序号 → 槽 id
			break
	PlayerState.equip(wear_uid)
	var worn_refused := PlayerState.disassemble(wear_uid).is_empty() \
		and PlayerState.equipped_uid(wear_slot) == wear_uid
	PlayerState.unequip(&"weapon")
	PlayerState.disassemble(wear_uid)      # 收尾拆掉，别把状态带给打造段

	# ── ②③ 打造与制书（**逐件**：书名就是装备名）──
	var tier := ItemData.Tier.RARE                        # 极品（最低的可打造档）
	var cost := PlayerState.crafting().cost_for(int(tier))
	var pool := GameProgress.drop_pool(tier)
	var craftable := str(pool[0])
	var other := str(pool[mini(1, pool.size() - 1)])       # 同档另一件（书不通用）
	var bp_price := int(PlayerState.crafting().blueprint_price.get(str(int(tier)), 0))
	var locked_refused := PlayerState.craft(craftable).is_empty()       # 没这本书
	PlayerState.add_gold(bp_price)
	var bought := PlayerState.unlock_blueprint(craftable) \
		and PlayerState.gold == 0 and PlayerState.has_blueprint(craftable)
	var repurchase_refused: bool = not PlayerState.unlock_blueprint(craftable)
	# **书不通用**：有寒月剑的书 ≠ 能造同档别的件 —— 逐件制书的核心
	var book_not_shared := PlayerState.craft(other).is_empty() \
		and not PlayerState.has_blueprint(other)
	# 材料不够：一分不动（原子），造不出
	var before := PlayerState.material_count(&"mat_refined_iron")
	var still_locked := PlayerState.craft(craftable).is_empty() \
		and PlayerState.material_count(&"mat_refined_iron") == before
	# 给足：新实例进包、料按配方扣减（注意前面分解段已有材料存量，验扣减不清零）
	for id in cost:
		PlayerState.add_material(StringName(String(id)), int(cost[id]))
	var shards_full := PlayerState.shards
	var black_full := PlayerState.material_count(&"mat_black_iron")
	var new_uid := PlayerState.craft(craftable)
	var crafted_ok: bool = not new_uid.is_empty() and PlayerState.bag.has(new_uid) \
		and PlayerState.shards == shards_full - int(cost.get("mat_refined_iron", 0)) \
		and PlayerState.material_count(&"mat_black_iron") == black_full - int(cost.get("mat_black_iron", 0))

	# ── ④ 铁律（读数据重算，不抄落地脚本的结论）──
	var table_ok := true
	for t in PlayerState.crafting().recipes:
		var c: Dictionary = PlayerState.crafting().cost_for(int(t))
		var y: Dictionary = PlayerState.disassemble_table().yield_for(int(t))
		for mid in c:
			if int(y.get(mid, 0)) >= int(c[mid]):
				table_ok = false

	var ok := gone and iron_ok and black_ok and worn_refused \
		and locked_refused and bought and repurchase_refused and book_not_shared \
		and still_locked and crafted_ok and table_ok
	_check("11", "回收闭环：分解到账（穿的不收）；打造要**这一件**的制书+付料（原子、书不通用）；重复买拒绝；分解<打造",
		ok,
		"优秀档拆 %d 精铁+%d 玄铁　极品解锁 %d 元宝、打造新 uid=%s、料扣减=%s、书不通用=%s　铁律=%s" % [
			iron_gain, black_gain, bp_price, str(not new_uid.is_empty()),
			str(crafted_ok), str(book_not_shared), str(table_ok)])
