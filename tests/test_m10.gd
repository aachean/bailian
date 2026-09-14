extends Node
## 《百炼》批 1 自动验收：**成长曲线 / 逐件强化 / 属性软上限**。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m10.tscn
##
## 这一组盯的是 `docs/design-principles.md` 附录 D 里「批 1 · 结构」那六条 ——
## 它们动的是数据模型与曲线形状，所以断言全部直接盯**形状**，不盯某一个具体数字：
##
##   · 3.2 等级必须有上限（且上限要够得着）        → #1 #4
##   · 3.3 经验走幂函数，末段不能吃掉大半时长      → #2 #3
##   · 3.4 属性走软上限 / 边际递减                 → #7 #8
##   · 4.2 比例属性有硬上限                        → #9
##   · 5.2 品质档位绑定强化上限（逐件、封顶）      → #10 #11 #12
##   · 5.4 强化成本递增、收益递减                  → #13 #14
##
## 「数字唯一真相在资源」这条也在这里验：改资源的字段，结果必须跟着变（#5 #6）——
## 不这么写的话，代码里偷偷留一份魔法数也照样全绿。

const SaveGuard := preload("res://tests/save_guard.gd")

const TOWN_PATH := "res://scenes/stages/town.tscn"
## 三档品质各一件，拿来验「强化上限按品质递增」的台阶
const ITEM_COMMON := "res://data/items/leather_cap.tres"     # 普通｜上限 3
const ITEM_FINE := "res://data/items/iron_sword.tres"        # 精良｜上限 5
const ITEM_RARE := "res://data/items/flame_blade.tres"       # 稀有｜上限 8

var _pass := 0
var _fail := 0
var _bak: Dictionary = {}
var _slot_before := 1


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》批 1 自动验收：等级上限 / 经验幂函数 / 逐件强化 / 软上限 ═══")
	_bak = SaveGuard.backup()
	_slot_before = SaveManager.current_slot
	SaveManager.current_slot = 1
	SaveManager.start_new_game(1, TOWN_PATH)

	await _t1_level_cap()
	await _t2_exp_curve_shape()
	await _t3_tail_share()
	await _t4_max_level_stops_exp()
	await _t5_growth_numbers_come_from_resource()
	await _t6_bad_level_is_clamped()
	await _t7_items_are_instances()
	await _t8_forge_cap_by_tier()
	await _t9_maxed_cannot_forge()
	await _t10_cost_rises_with_level()
	await _t11_gain_falls_off_with_level()
	await _t12_forge_survives_save()
	await _t13_legacy_upgrade_migrates()
	await _t14_forge_atk_joins_damage_pool()
	await _t15_soft_cap_is_lossless_below_knee()
	await _t16_soft_cap_diminishes_above_knee()
	await _t17_ratio_has_hard_cap()

	SaveManager.current_slot = _slot_before
	SaveGuard.restore(_bak)

	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ── 工具 ───────────────────────────────────────────────────────

func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-3s %s\n              %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-3s %s\n              %s" % [id, desc, detail])


# ── 3.2 等级上限 ───────────────────────────────────────────────

## 灌爆经验：等级必须停在 cap，而且循环要能自己停下来（不能死循环）
func _t1_level_cap() -> void:
	var p := PlayerState.progression
	PlayerState.reset_for_new_game()
	var ups := PlayerState.add_exp(999999999)
	_check("1", "等级有上限：灌爆经验也只升到 cap",
		PlayerState.level == p.level_cap and ups == p.level_cap - 1,
		"cap=%d　实际到 Lv.%d（连升 %d 次，期望 %d）" % [
			p.level_cap, PlayerState.level, ups, p.level_cap - 1])


## 幂函数与线性在**一阶差分**上分得开：线性差分恒定，幂函数差分递增。
## 这条是「改回线性」这个回退动作的守门人 —— 光看数值大小是抓不到的
func _t2_exp_curve_shape() -> void:
	var p := PlayerState.progression
	var d1 := p.exp_needed(5) - p.exp_needed(4)
	var d2 := p.exp_needed(15) - p.exp_needed(14)
	var d3 := p.exp_needed(25) - p.exp_needed(24)
	_check("2", "经验曲线是幂函数：每级增量随等级递增（线性的话三个差相等）",
		d1 < d2 and d2 < d3,
		"Δ4→5=%d　Δ14→15=%d　Δ24→25=%d" % [d1, d2, d3])


## 设计原则 3.3 的硬指标：最后 10% 的等级不能吃掉 40% 以上的总时长
func _t3_tail_share() -> void:
	var p := PlayerState.progression
	var share := p.tail_share(0.1)
	_check("3", "末段 10% 的等级吃掉的总经验 < 40%",
		share < 0.4,
		"末段占 %.1f%%（总经验 %d）" % [share * 100.0, p.total_exp_to_cap()])


## 满级之后经验不再累积（不是「攒着但没用」）——
## 后者会让 HUD 上的经验条继续涨，玩家以为还能升
func _t4_max_level_stops_exp() -> void:
	var p := PlayerState.progression
	PlayerState.reset_for_new_game()
	PlayerState.add_exp(999999999)
	var ups := PlayerState.add_exp(500)
	_check("4", "满级后不再吃经验：经验停在 0、不再升级",
		ups == 0 and PlayerState.exp == 0 and PlayerState.level == p.level_cap,
		"再灌 500 经验 → 升级 %d 次　经验 %d　等级 %d" % [ups, PlayerState.exp, PlayerState.level])


## 成长数字的唯一真相在 progression.tres：改资源，结果跟着变。
## 代码里要是偷偷留了一份魔法数，这条立刻红
func _t5_growth_numbers_come_from_resource() -> void:
	var p := PlayerState.progression
	var old_hp := p.hp_per_level
	var old_atk := p.atk_per_level
	var new_hp := old_hp + 7
	var new_atk := old_atk + 0.01
	p.hp_per_level = new_hp
	p.atk_per_level = new_atk
	var hp_val := p.hp_at(10)
	var atk_val := p.atk_bonus_at(11)
	var hp_ok := hp_val == p.base_hp + 9 * new_hp
	var atk_ok := is_equal_approx(atk_val, new_atk * 10.0)
	p.hp_per_level = old_hp
	p.atk_per_level = old_atk
	_check("5", "每级成长读的是资源：改 hp_per_level / atk_per_level 立刻反映到取值上",
		hp_ok and atk_ok,
		"hp_per_level %d→%d：hp_at(10) 得 %d（期望 %d）　atk %.3f（期望 %.3f）" % [
			old_hp, new_hp, hp_val, p.base_hp + 9 * new_hp, atk_val, new_atk * 10.0])


## 坏档 / 越界等级要夹回 cap —— 不夹的话 level=999 会让 exp_needed 返回 0
## 之外的一堆推导值全部失真（生命上限、蓝上限、攻击倍率）
func _t6_bad_level_is_clamped() -> void:
	var p := PlayerState.progression
	PlayerState.load_from({"level": 999})
	var hi := PlayerState.level
	PlayerState.load_from({"level": -5})
	var lo := PlayerState.level
	_check("6", "越界等级被夹回 [1, cap]",
		hi == p.level_cap and lo == 1,
		"level=999 → %d（期望 %d）　level=-5 → %d（期望 1）" % [hi, p.level_cap, lo])


# ── 5.2 装备是【实例】，不是型号 ────────────────────────────────

## 两把同型号的剑必须是两件东西 —— 练过一把，另一把不该跟着变。
## 这条是「拿资源路径当键」那个模型的墓碑：那个版本下两把剑共享强化等级
func _t7_items_are_instances() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.shards = 999
	var a: String = PlayerState.add_item(ITEM_FINE)
	var b: String = PlayerState.add_item(ITEM_FINE)
	var distinct: bool = a != b and PlayerState.path_of(a) == PlayerState.path_of(b)
	PlayerState.forge_once(a)
	PlayerState.forge_once(a)
	var lv_a := PlayerState.forge_level(a)
	var lv_b := PlayerState.forge_level(b)
	_check("7", "装备是实例：同型号两件各自记强化等级（练一把不影响另一把）",
		distinct and lv_a == 2 and lv_b == 0,
		"两件同型号 uid 不同=%s　练过的那件 +%d（期望 2）　没练的 +%d（期望 0）" % [
			str(distinct), lv_a, lv_b])


## 品质档位绑定强化上限（设计原则 5.2）：白 < 精良 < 稀有，
## 而且**每一档的上限都是它自己的**，不是「全部共用一个上限」
func _t8_forge_cap_by_tier() -> void:
	PlayerState.reset_for_new_game()
	var a: String = PlayerState.add_item(ITEM_COMMON)
	var b: String = PlayerState.add_item(ITEM_FINE)
	var c: String = PlayerState.add_item(ITEM_RARE)
	var ca := PlayerState.forge_max(a)
	var cb := PlayerState.forge_max(b)
	var cc := PlayerState.forge_max(c)
	_check("8", "品质档位绑定强化上限：普通 < 精良 < 稀有",
		ca > 0 and ca < cb and cb < cc,
		"普通 %d ／ 精良 %d ／ 稀有 %d" % [ca, cb, cc])


## 练到顶之后：不能再练，而且**不能白扣精铁**。
## 「按了没反应还不说为什么」是不合格的 —— 面板那边另有一条断言盯着提示文字
func _t9_maxed_cannot_forge() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.shards = 9999
	var uid: String = PlayerState.add_item(ITEM_COMMON)
	var cap := PlayerState.forge_max(uid)
	var forged := 0
	while PlayerState.forge_once(uid):
		forged += 1
		if forged > 50:
			break                        # 死循环保护：真出问题要让断言红，不是挂住
	var shards_after_full: int = PlayerState.shards
	var again: bool = PlayerState.forge_once(uid)
	_check("9", "练到品质上限就停：再按不生效、也不扣精铁",
		forged == cap and PlayerState.forge_level(uid) == cap \
			and not again and PlayerState.shards == shards_after_full,
		"白装练了 %d 次（上限 %d）　到顶后再练=%s　精铁 %d → %d" % [
			forged, cap, str(again), shards_after_full, PlayerState.shards])


## 成本递增（设计原则 5.4）：越往上越贵，逼玩家真的去刷
func _t10_cost_rises_with_level() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.shards = 9999
	var uid: String = PlayerState.add_item(ITEM_RARE)
	var c0 := PlayerState.forge_cost(uid)
	PlayerState.forge_once(uid)
	var c1 := PlayerState.forge_cost(uid)
	PlayerState.forge_once(uid)
	var c2 := PlayerState.forge_cost(uid)
	_check("10", "强化成本递增：0→1 级最便宜，越往上越贵",
		c0 < c1 and c1 < c2,
		"第 1 级 %d ／ 第 2 级 %d ／ 第 3 级 %d 精铁" % [c0, c1, c2])


## 收益递减（设计原则 5.4 / 3.4）：每一级给的加成比上一级少。
## 用**一阶差分**验形状 —— 只看总量的话，线性叠加也「看起来在涨」
func _t11_gain_falls_off_with_level() -> void:
	var d1 := PlayerState.forge_atk_at(1) - PlayerState.forge_atk_at(0)
	var d2 := PlayerState.forge_atk_at(2) - PlayerState.forge_atk_at(1)
	var d3 := PlayerState.forge_atk_at(3) - PlayerState.forge_atk_at(2)
	_check("11", "强化收益递减：第 n 级给的加成少于第 n-1 级",
		d1 > d2 and d2 > d3,
		"Δ1=%.4f　Δ2=%.4f　Δ3=%.4f　（练满 8 级合计 +%.1f%%）" % [
			d1, d2, d3, PlayerState.forge_atk_at(8) * 100.0])


## 强化等级与实例 id 都要过存档 —— 少一个就会出现
## 「读档后武器还是那把，但强化等级归零」或者「强化等级跳到同型号的另一件上」
func _t12_forge_survives_save() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.shards = 100
	var uid: String = PlayerState.add_item(ITEM_FINE)
	PlayerState.equip(uid)
	PlayerState.forge_once(uid)
	PlayerState.forge_once(uid)
	var snap := PlayerState.save_to()

	PlayerState.reset_for_new_game()
	PlayerState.load_from(snap)
	var lv := PlayerState.forge_level(uid)
	var worn: String = PlayerState.equipped_uid(&"weapon")
	# 读档后新捡的一件**不能撞上档案里已有的号** —— 撞了就是两件东西共享强化等级。
	# 这比「看一眼计数器数值」直接得多
	var fresh: String = PlayerState.add_item(ITEM_FINE)
	_check("12", "强化等级 / 实例 id 过存档往返，读档后新捡的不会撞号",
		lv == 2 and worn == uid and fresh != uid,
		"强化 +%d（期望 2）　穿着的还是那一件=%s　读档后新捡 uid=%s（原 %s）" % [
			lv, str(worn == uid), fresh, uid])


## 旧档迁移：老存档里 equipped / bag 是**纯路径**（没有 # 后缀），
## 强化是**玩家身上的一个全局数字**。读进来之后要变成
## 「路径即 uid」+「那个数字搬到当时装备的武器上」，而不是把玩家的强化吞掉
func _t13_legacy_upgrade_migrates() -> void:
	PlayerState.reset_for_new_game()
	var old := {
		"shards": 5,
		"level": 9,
		"exp": 0,
		"equipped": {"weapon": ITEM_FINE},      # 纯路径 = 老格式
		"bag": [],
		"upgrade": 4,                           # 老格式的全局强化等级
	}
	PlayerState.load_from(old)
	var lv := PlayerState.forge_level(ITEM_FINE)
	var worn := PlayerState.item_at(&"weapon")
	var lv_ok: bool = lv == 4 and worn != null and worn.id == &"iron_sword"

	# 全局等级高于品质上限时要夹住 —— 精良武器上限 5，给个 9 只能是 5。
	# 注意必须挂在**武器**槽上：旧档那个 upgrade 的语义就是「武器强化」
	# （铁砧的提示牌上写的就是这四个字），搬到别的部位上是无中生有
	PlayerState.reset_for_new_game()
	PlayerState.load_from({"equipped": {"weapon": ITEM_FINE}, "upgrade": 9})
	var clamped := PlayerState.forge_level(ITEM_FINE)

	# 旧档里有强化、但当时没装备武器：那份强化无处可去，丢掉 ——
	# 关键是【不能崩】、也不能因此把精铁弄脏
	PlayerState.reset_for_new_game()
	PlayerState.load_from({"equipped": {}, "bag": [], "upgrade": 6})
	var dropped: bool = PlayerState.forge.is_empty()

	_check("13", "旧档的全局强化等级搬到武器上并按品质上限夹住；没武器就丢掉",
		lv_ok and clamped == PlayerState.forge_max(ITEM_FINE) and dropped,
		"upgrade=4 → 精良武器 +%d（期望 4）　upgrade=9 → +%d（上限 %d）　"
		% [lv, clamped, PlayerState.forge_max(ITEM_FINE)]
		+ "没武器时强化表为空=%s" % str(dropped))


## 强化加成必须真的进了伤害乘区 —— 面板写 +38% 而打出的数字没变，
## 就是设计原则 4.1 要防的那种「游戏在骗玩家」
func _t14_forge_atk_joins_damage_pool() -> void:
	PlayerState.reset_for_new_game()
	PlayerState.shards = 100
	var uid: String = PlayerState.add_item(ITEM_FINE)
	PlayerState.equip(uid)
	var before: float = PlayerState.bonus_total().get("atk", 0.0)
	PlayerState.forge_once(uid)
	var after: float = PlayerState.bonus_total().get("atk", 0.0)
	var gained := after - before
	var expect := PlayerState.forge_atk_at(1)
	_check("14", "强化加成进了伤害乘区（词条聚合里算上了）",
		is_equal_approx(gained, expect),
		"攻击加成 %.3f → %.3f（+%.3f，期望 +%.3f）" % [before, after, gained, expect])


# ── 3.4 软上限 / 4.2 硬上限 ────────────────────────────────────

## 软上限不能误伤「正常装备量级」：几件装备的词条加起来还在 knee 以内时，
## 生效值必须**一分不少**。这条守的是 4.1（面板 +15% 就得真 +15%）——
## 一条一上来就递减的曲线会让单件装备当场对不上账
func _t15_soft_cap_is_lossless_below_knee() -> void:
	PlayerState.reset_for_new_game()
	var uid: String = PlayerState.add_item(ITEM_FINE)       # 攻 +15%
	PlayerState.equip(uid)
	var bonus: float = PlayerState.bonus_total().get("atk", 0.0)
	var raw := (load(ITEM_FINE) as ItemData).atk_bonus       # 0.15，远在 knee(1.0) 以内
	_check("15", "软上限在 knee 以内无损：单件装备的词条原样生效",
		is_equal_approx(bonus, raw),
		"装备词条 +%.3f → 生效 +%.3f（knee=%.1f，一分没少）" % [
			raw, bonus, PlayerState.progression.soft_knee_atk])


## 超出 knee 之后才开始递减：边际收益一次比一次少，而且**永远到不了** knee+cap。
## 用一阶差分验形状 —— 只看总量的话「还在涨」这件事骗得过眼睛
func _t16_soft_cap_diminishes_above_knee() -> void:
	var p := PlayerState.progression
	var k := p.soft_knee_atk
	var c := p.soft_cap_atk
	var g1 := p.soften(k + 0.5, k, c) - p.soften(k, k, c)
	var g2 := p.soften(k + 1.0, k, c) - p.soften(k + 0.5, k, c)
	var far := p.soften(1000.0, k, c)
	_check("16", "软上限：超出 knee 后边际收益递减，且总效果永远到不了 knee+cap",
		g1 > g2 and g2 > 0.0 and far < k + c and far > k + c * 0.99,
		"Δ(+0.5)=%.3f ＞ Δ(再 +0.5)=%.3f　无限堆到 %.3f（上限 %.3f，够不着）" % [
			g1, g2, far, k + c])


## 比例类属性必须有硬上限（4.2）。减伤现在的天花板是 0.6 ——
## 「堆防御到无敌」不能成为解，这条是那个天花板的守门人。
## 未知的比例属性也得被夹住，否则以后加暴击忘了设上限就会漏出去
func _t17_ratio_has_hard_cap() -> void:
	var cap := PlayerState.clamp_ratio(&"def", 5.0)
	var unknown := PlayerState.clamp_ratio(&"crit", 3.7)
	_check("17", "比例属性走硬上限：减伤夹在 0.6，未登记的比例属性夹在 [0,1]",
		is_equal_approx(cap, Health.MAX_DAMAGE_REDUCTION) and is_equal_approx(unknown, 1.0),
		"减伤 5.0 → %.2f（上限 %.2f）　未登记的 crit 3.7 → %.2f" % [
			cap, Health.MAX_DAMAGE_REDUCTION, unknown])
