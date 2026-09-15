extends Node
## 《百炼》M3 第 3 步自动验收：**经济**（元宝 / 商店 / 出售 / 消耗品掉落）。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m14.tscn
##
## 设计依据：计划 §3.7（2026-09-14 定）——
##   · 元宝是**唯一通用货币**，与精铁刻意互不兑换（两笔钱各管各的）
##   · 元宝来源只有两条：打怪掉小额 + 出售装备
##   · 消耗品掉在地上**走近直接生效**，不进背包；满血 / 满蓝不拾取
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
const SWORD := "res://data/items/iron_sword.tres"          # 精良，定价 40
const FLAME := "res://data/items/flame_blade.tres"         # 稀有，不在货架
const CAP := "res://data/items/leather_cap.tres"           # 普通，定价 16（货架第一件）

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
	PlayerState.add_gold(100)
	var uid := PlayerState.buy_item(SWORD)
	var bought := not uid.is_empty() and PlayerState.bag.has(uid) \
		and PlayerState.gold == 60 and PlayerState.item_of(uid) != null
	# 新实例：uid 带序号，不是资源路径本身（型号 ≠ 实例）
	var is_instance: bool = uid.contains(PlayerState.UID_SEP)
	var gain := PlayerState.sell_item(uid)
	var sold := gain == 20 and PlayerState.gold == 80 and not PlayerState.bag.has(uid)
	_check("2", "买卖闭环：40 买进 → 半价 20 卖出；实例 uid；账目吻合",
		bought and is_instance and sold,
		"元宝 100 → 60（买剑）→ 80（卖剑，floor(40×0.5)=20）")


## 卖的三条规矩：货架外的不卖（那是「买」的反向）；穿在身上的不收；没这东西不收
func _t3_sell_rules() -> void:
	_fresh_state()
	PlayerState.add_gold(100)
	var not_in_bag := PlayerState.sell_item(SWORD) == 0        # 路径 ≠ 背包里的实例
	var uid := PlayerState.buy_item(SWORD)
	PlayerState.equip(uid)                                     # 穿上（离开背包）
	var worn := PlayerState.sell_item(uid) == 0 \
		and PlayerState.equipped_uid(&"weapon") == uid \
		and PlayerState.gold == 60
	var unequipped := PlayerState.unequip(&"weapon")
	var back_gain := PlayerState.sell_item(unequipped)
	var sold_after_unequip: bool = back_gain == 20 and PlayerState.gold == 80
	_check("3", "出售规矩：身上穿的卖不掉；卸下后才能卖；没进过背包的路径不收",
		not_in_bag and worn and sold_after_unequip,
		"穿上时 sell=0，卸下后 sell=20；卖东西不产生第二份元宝")


## 商店面板（真实按键）：J 买货架第一件、买不起有话、Esc 关门
func _t4_shop_panel_buys() -> void:
	_fresh_state()
	PlayerState.add_gold(50)
	var panel := _player.get_node("ShopPanel")
	panel.call("open")
	await _pframes(2)
	var opened: bool = bool(panel.call("is_open")) and get_tree().paused
	_tap_key(KEY_J)                       # 货架第一件 = leather_cap（16 元宝）
	await _pframes(2)
	var bought: bool = PlayerState.gold == 34 and PlayerState.bag.size() == 1
	_tap_key(KEY_ESCAPE)
	await _pframes(2)
	var closed: bool = not bool(panel.call("is_open")) and not get_tree().paused
	_check("4", "商店面板：开 → J 买下 16 元宝的帽子 → Esc 关（暂停随面板走）",
		opened and bought and closed,
		"元宝 50 → 34；背包 +1；Esc 后不暂停")


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


## 药水的门：满血不收（躺着不动），掉了血才吸走并生效（计划 §3.7）
func _t6_potion_gate() -> void:
	var h := _player.get_node("Health") as Health
	h.heal_full()

	# 满血：药在玩家脚下也不收
	var hp_pot := PICKUP.instantiate()
	hp_pot.set("potion", &"hp")
	add_child(hp_pot)
	hp_pot.global_position = _player.global_position
	await _pframes(12)
	var stayed: bool = is_instance_valid(hp_pot) and not hp_pot.get("_collected")
	if is_instance_valid(hp_pot):
		hp_pot.queue_free()
	await _pframes(2)          # 必须等它真消失：留着的话，下一步一掉血
	                          # 它的「门」就开了，会抢在第二瓶之前把血回掉（测试自己污染自己）

	# 掉血：吸走 + 回血 40
	var low := h.max_hp - 50
	h.restore(low)
	var pot2 := PICKUP.instantiate()
	pot2.set("potion", &"hp")
	add_child(pot2)
	pot2.global_position = _player.global_position
	await _pframes(12)
	var healed: bool = not is_instance_valid(pot2) \
		and h.hp == mini(low + 40, h.max_hp)

	# 回蓝：满了不收，掉了才收（同一扇门，两条管道）
	var mp_pot := PICKUP.instantiate()
	mp_pot.set("potion", &"mp")
	add_child(mp_pot)
	mp_pot.global_position = _player.global_position
	_player.set("mp", _player.get("max_mp"))
	await _pframes(12)
	var mp_stayed: bool = is_instance_valid(mp_pot)
	if is_instance_valid(mp_pot):
		mp_pot.queue_free()
	await _pframes(2)          # 同上：别让满蓝时躺着的瓶子混进下一轮
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

	_check("6", "消耗品：满血/满蓝不拾取（原地躺）；有缺口才吸走并直接生效",
		stayed and healed and mp_stayed and mp_filled,
		"stayed=%s healed=%s mp_stayed=%s mp_filled=%s" % [stayed, healed, mp_stayed, mp_filled])


## 老货币一分不许动：强化仍然只走精铁；卖装备不产精铁（两条管道互不兑换）
func _t7_forge_still_uses_shards() -> void:
	_fresh_state()
	PlayerState.add_gold(500)
	PlayerState.shards = 10
	var uid := PlayerState.buy_item(SWORD)
	var forged := PlayerState.forge_once(uid)
	var ok: bool = forged and PlayerState.forge_level(uid) == 1 \
		and PlayerState.shards < 10 and PlayerState.gold == 460
	var gain := PlayerState.sell_item(uid)
	_check("7", "两条管道：强化扣精铁不动元宝；出售进元宝不动精铁",
		ok and gain == 20 and PlayerState.shards >= 0 and PlayerState.gold == 480,
		"精铁 10 → 少（强化），元宝 500 → 460 → 480（卖）")


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


## 数据一致性：价格都填了、货架都指向真装备、怪的掉落账能对上
func _t9_data_consistency() -> void:
	var shop := PlayerState.shop()
	var stock_ok := shop != null and not shop.stock.is_empty()
	for p in (shop.stock if shop != null else []):
		var it := load(str(p)) as ItemData
		if it == null or it.gold_price <= 0:
			stock_ok = false
	var flame_ok: bool = true
	var flame_it := load(FLAME) as ItemData
	if flame_it == null or flame_it.gold_price != 150:
		flame_ok = false
	var boss2 := load("res://data/enemies/boss2.tres") as EnemyData
	var walker := load("res://data/enemies/walker.tres") as EnemyData
	var luhou := load("res://data/enemies/boss_luhou.tres") as EnemyData
	var drops_ok := boss2 != null and boss2.drop_gold == 40 \
		and walker != null and walker.drop_gold == 2 \
		and luhou != null and luhou.drop_gold == 0     # 炉喉收尾不打架，不掉钱
	var sell_ok: bool = shop != null and shop.sell_price(40) == 20
	_check("9", "数据：8 件装备都有定价；货架指到真装备；怪掉落账目；炉喉不掉钱",
		stock_ok and flame_ok and drops_ok and sell_ok,
		"卖价公式只在 ShopData 一处：floor(40×0.5)=20")
