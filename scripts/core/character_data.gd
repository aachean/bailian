class_name CharacterData
extends Resource
## 一个可玩角色的全部定义。**加角色 = 写一个 .tres，不改代码**——
## 这是 M4 架构验证的本体：第二个角色（逐风）落地时，
## player 场景一行没为它改逻辑，只多了两份数据。
##
## ── 差异放在哪 ────────────────────────────────────────────────
## v1 差异化三样：**连招**（剑客三段斩 / 逐风三段射）、**技能池**（各自一套）、
## **外观色**。成长曲线刻意共用 —— 等级是解锁内容的钥匙（ADR-0010），
## 不该因为选了谁就变成两条成长轴。
##
## ── 注册在哪 ──────────────────────────────────────────────────
## `data/characters/*.tres`。选人页扫这个目录（CHARACTER_DIR），
## 想上第三个角色就是丢一个 .tres 进去，选人页自己长出来。

## 角色的 id。进存档（PlayerState.character_id），改了 id 老档会认不出
@export var id: StringName = &""
## 名字与一句话介绍的翻译 key
@export var name_key: StringName = &""
@export var desc_key: StringName = &""

@export_group("外观（色块美学 v1）")
## 身体主色。脸是固定的白 —— 只换衣服颜色，轮廓不变，一眼「同一个人的两个流派」
@export var body_color: Color = Color(0.847, 0.353, 0.188)

@export_group("精灵图（AI 生图管线，ADR-0015）")
## 精灵图目录。空 = 维持程序化色块视觉（还没生图的角色）。
## 约定文件：idle.png / atk_windup.png / atk_strike.png / portrait.png，
## 全部由 tools/process_art.py 后处理产出（透明底、脚在图底）
@export var sprite_dir: String = ""

@export_group("初始装备（res:// 路径）")
## 初始武器。老铁匠的见面礼按它发货（对话 give_item 写的是剑客的铁剑，
## dialogue_box 发奖时按当前角色换成这里这份）—— 弓手不该背着铁剑出门
@export var starting_weapon: String = ""

@export_group("武器类型")
## 这个角色使什么类型的武器（对照 ItemData.weapon_type）。
## 装备门在 PlayerState.equip：类型不匹配的武器穿不上
@export var weapon_type: StringName = &"sword"

@export_group("战斗数据（res:// 路径）")
## 普攻连招：J 一下接一下的那几段，按顺序
@export var combo: Array[String] = []
## 技能池：按解锁等级排，进技能面板、升级自动补位
@export var skills: Array[String] = []


func load_combo() -> Array[SkillData]:
	var out: Array[SkillData] = []
	for p in combo:
		var r := load(p)
		if r is SkillData:
			out.append(r)
		else:
			push_error("CharacterData %s: 连招数据加载失败 %s" % [id, p])
	return out


func load_skills() -> Array[SkillData]:
	var out: Array[SkillData] = []
	for p in skills:
		var r := load(p)
		if r is SkillData:
			out.append(r)
		else:
			push_error("CharacterData %s: 技能数据加载失败 %s" % [id, p])
	return out


## 选人页扫的目录。加角色 = 丢一个 .tres 进来
const CHARACTER_DIR := "res://data/characters"


## 扫目录列出全部角色（按文件名排序，顺序稳定 —— 选人页光标不跳）。
## 不是 CharacterData 的 .tres 静默跳过（目录以后可能住别的数据）
static func all() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	var dir := DirAccess.open(CHARACTER_DIR)
	if dir == null:
		push_error("CharacterData: 角色目录打不开 %s" % CHARACTER_DIR)
		return out
	var names := []
	for f in dir.get_files():
		if f.ends_with(".tres"):
			names.append(f)
	names.sort()
	for f in names:
		var r := load("%s/%s" % [CHARACTER_DIR, f]) as CharacterData
		if r != null:
			out.append(r)
	return out


## 按 id 取角色；认不出返回 null（老档存着的 id 被改名时，调用方回退默认角色）
static func by_id(cid: StringName) -> CharacterData:
	for c in all():
		if c.id == cid:
			return c
	return null


## 默认角色：**剑客**（第一个角色）。老档没有 character_id 字段、或 id 认不出时
## 回退到它 —— 不能按文件名字典序取第一个（archer 恰好排在前面，纯属文件名巧合）
static func default_character() -> CharacterData:
	var fallback := by_id(&"swordsman")
	if fallback != null:
		return fallback
	var list := all()
	return list[0] if not list.is_empty() else null
