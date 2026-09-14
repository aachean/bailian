extends SceneTree
## 打印成长曲线的关键量级 —— 调 progression.tres 时跑它看一眼，不用进游戏。
##
## 用法（必须带 --script，且路径是 res:// 形式）：
##   <godot> --headless --path . --script res://tools/probe_progression.gd

func _initialize() -> void:
	var p := load("res://data/progression.tres") as ProgressionData
	if p == null:
		print("[probe] 加载失败：res://data/progression.tres")
		quit(1)
		return

	print("[probe] 等级上限 %d / 经验 = %s × level^%s" % [p.level_cap, p.exp_base, p.exp_exponent])
	print("[probe] 满级所需总经验 %d" % p.total_exp_to_cap())

	var lv := 1
	while lv < p.level_cap and lv <= 12:
		print("  Lv.%2d → 上级需 %6d   （生命 %4d / 蓝 %3d / 攻击 +%d%%）" % [
			lv, p.exp_needed(lv), p.hp_at(lv), p.mp_at(lv), int(round(p.atk_bonus_at(lv) * 100.0))])
		lv += 1
	print("  ... 跳到末段 ...")
	for l in range(maxi(p.level_cap - 3, 1), p.level_cap):
		print("  Lv.%2d → 上级需 %6d" % [l, p.exp_needed(l)])
	print("[probe] 末段 3 级占总经验 %.1f%%（设计原则 3.3 要求 < 40%%）" % calc_tail(p, 3))
	print("[probe] 满级时：生命 %d / 蓝 %d / 攻击 +%d%%" % [
		p.hp_at(p.level_cap), p.mp_at(p.level_cap), int(round(p.atk_bonus_at(p.level_cap) * 100.0))])
	quit()


## 最后 n 级占总经验的比例
func calc_tail(p: ProgressionData, n: int) -> float:
	var total := p.total_exp_to_cap()
	if total <= 0:
		return 0.0
	var tail := 0
	for lv in range(maxi(p.level_cap - n, 1), p.level_cap):
		tail += p.exp_needed(lv)
	return float(tail) / float(total) * 100.0
