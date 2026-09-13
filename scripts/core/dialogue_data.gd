class_name DialogueData
extends Resource
## 一段对话：说话人 + 若干句台词 + 可选的赠礼。
##
## ── 台词存的是【翻译 key】，不是原文 ─────────────────────────
## 界面文案一律走 data/i18n/ui.csv，对话框没有例外。
## 加剧情 = 加一个 .tres + 往 csv 加几行，不改代码。
##
## ── 为什么带 give_item / flag ────────────────────────────────
## 「老铁匠给你一把剑」是主线里最朴素的一次推进。赠礼与进度标记都挂在对话上，
## 于是「剧情推进」= 播一段对话，不需要再写一套任务系统。
## flag 的作用是「同一份礼物只给一次」：给过就记下来，第二次只说话不给东西。

@export_group("标识")
## 说话人名字的翻译 key（NPC_SMITH 之类）
@export var speaker_key: StringName = &""

@export_group("台词")
## 按顺序播的台词，每项是一个翻译 key
@export var lines: Array[String] = []

@export_group("推进")
## 说完后赠予的装备（ItemData 资源路径）。留空 = 不赠
@export var give_item: String = ""
## 赠礼与「已完成」记在这个 flag 上。留空 = 不记录（每次都能聊、每次都送）
@export var flag: StringName = &""


func has_content() -> bool:
	return not lines.is_empty()
