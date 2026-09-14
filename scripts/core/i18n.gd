class_name I18n
extends RefCounted
## 带参数的翻译。**所有「翻译里要填数字」的地方都走这里，别直接 `tr(KEY) % args`。**
##
## ── 为什么需要它 ──────────────────────────────────────────────
## `tr()` 拿不到 key 时**返回 key 本身**（这是 Godot 的既定行为，也是这个项目
## 反复踩的「漏翻静默失败」家族的头号成员）。平时它只是让界面上出现
## `UI_STAGE_TOTAL` 这种字样 —— 难看但不出事。
##
## 可一旦这个 key 的文案里**带占位符**（`"共 %d 段"`），链式格式化就会当场炸：
## ```
## tr("UI_STAGE_TOTAL") % 3     # key 缺失 → "UI_STAGE_TOTAL" % 3
## → String formatting error: not all arguments converted
## ```
## 而 `hud.refresh()` 是**每帧**都在跑的 —— 一次漏填 csv，就是每帧一条报错刷屏。
## 这条路真的走通过（加段号那一轮，csv 加了但没重新导入）。
##
## 本函数把那种情况退化成「显示 key 本身」：和其余漏翻一样难看，
## 但**不炸**，也不会把真正的报错淹掉。
##
## 用法：
##     I18n.t(&"UI_STAGE_LABEL", [i + 1])       # 「第 2 段」
##     I18n.t(&"UI_ATLAS_REC", [lv, weapon])    # 「推荐 Lv.3　武器 Lv.1」

static func t(key: StringName, args: Array = []) -> String:
	# 用 TranslationServer 而不是 tr()：静态函数里没有 Node 的那套 tr
	var s := TranslationServer.translate(String(key))
	if args.is_empty() or not s.contains("%"):
		return s
	return s % args
