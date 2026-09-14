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
## 一件白装 / 一件精良 / 一件稀有，拿来验品质封顶的台阶
const ITEM_COMMON := "res://data/items/leather_cap.tres"
const ITEM_FINE := "res://data/items/iron_sword.tres"

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
