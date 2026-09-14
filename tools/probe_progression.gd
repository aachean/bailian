extends SceneTree
## 打印成长曲线的关键量级 —— 调 progression.tres 时跑它看一眼，不用进游戏。
##
## 用法（必须带 --script，且路径是 res:// 形式）：
##   <godot> --headless --path . --script res://tools/probe_progression.gd
##
## 「折算砺场」那一列是拿**砺场一次通关 340 经验**做基准的（数过场景里的怪：
## 31 只 = 340 经验）。它只回答一个问题：**第一章（目前唯一有内容的副本）能练到几级**。
## 后面地图的经验产出还没定，所以「到满级」那个数字现在只是留给后续的空间。

## 砺场一次通关给的经验
const LICHANG_EXP := 340
## 打印哪几个等级
const MARKS := [1, 5, 10, 15, 20, 30, 50, 75, 100]


func _initialize() -> void:
	var p := load("res://data/progression.tres") as ProgressionData
	if p == null:
		print("[probe] 加载失败：res://data/progression.tres")
		quit(1)
		return

	print("[probe] 等级上限 %d ／ 经验 = %s × level^%s" % [p.level_cap, p.exp_base, p.exp_exponent])
	print("[probe] 满级总经验 %d ／ 末段 10%% 的等级占 %.1f%%（设计原则 3.3 要求 < 40%%）"
		% [p.total_exp_to_cap(), p.tail_share(0.1) * 100.0])
	print("")
	print("  等级    生命     蓝   攻击加成   升下一级需   累计经验   折算砺场")
	print("  ───────────────────────────────────────────────────────────────")
	var total := 0
	for lv in range(1, p.level_cap + 1):
		var need := p.exp_needed(lv)
		if lv in MARKS:
			print("  Lv.%-4d %6d %6d   %+7.1f%%   %8s   %8s   %6.1f 次" % [
				lv, p.hp_at(lv), p.mp_at(lv), p.atk_bonus_at(lv) * 100.0,
				("—" if need <= 0 else str(need)), str(total),
				float(total) / float(LICHANG_EXP)])
		total += need

	print("")
	print("[probe] 第一章现在只有砺场（%d 经验/次）：" % LICHANG_EXP)
	var to_cap_total: int = p.total_exp_to_cap(1)
	for lv in [5, 10, 15, 20]:
		# 「从 1 级练到 lv」= 到 cap 的总量 − 从 lv 到 cap 的那一段。
		# 别反过来直接用 total_exp_to_cap(lv) —— 那个函数问的是「还要多少才满级」
		var acc: int = to_cap_total - p.total_exp_to_cap(lv)
		print("       练到 Lv.%-3d 要 %6d 经验 ≈ %5.1f 次砺场" % [
			lv, acc, float(acc) / float(LICHANG_EXP)])
	print("")
	print("[probe] ⚠️ 「到满级 %.0f 次砺场」**现在不是目标**，是留给后续地图的空间 ——"
		% (float(total) / float(LICHANG_EXP)))
	print("       新地图的怪经验更高时这个次数才会降下来，现在别拿它当平衡依据。")
	print("[probe] 另外：每级成长是**等比收敛**的（gain × (1 - falloff^n)），"
		+ "所以 Lv.100 与 Lv.200 的差别本来就很小 —— 上限只是钥匙，不是战力轴。")
	quit()
