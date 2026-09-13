class_name ItemData
extends Resource
## 一件装备的全部数据。加装备 = 写一个 .tres，不改代码（与 SkillData / EnemyData 同一套路）。
##
## ── 词条只有三条，且全部走【已有的乘区】 ─────────────────────
## 攻击：累加进 Hitbox.damage_scale（和武器强化、角色等级同一个乘区）。
##       为什么不做「攻击力数值 → 再算公式」那一套：原型期的伤害管线是
##       「技能基础伤害 × 倍率」，多插一层数值公式只会让调参变难，
##       而玩家在界面上看到的 +15% 和实际打出的数字必须对得上。
## 生命：加在 max_hp 上（与等级成长相加）。
## 防御：按比例减伤。这是 M3-2 新引入的属性，见 docs/adr/0005。
##
## ── 为什么槽位用字符串 id 而不是 enum 序号 ───────────────────
## 装备栏要进存档（ConfigFile 存 Dictionary）。用 enum 序号当 key 的话，
## 以后往枚举中间插一个部位，老存档的序号会静默指向错误的槽。
## 字符串 key 没这个隐患，存档也一眼能读出含义。

enum Slot { WEAPON, HELM, ARMOR, TRINKET }
enum Tier { COMMON, FINE, RARE }

## 槽位 id，顺序与 Slot 枚举一致。装备栏字典和存档都用它当 key
const SLOT_IDS: Array[StringName] = [&"weapon", &"helm", &"armor", &"trinket"]
## 槽位显示名的翻译 key，顺序同上
const SLOT_KEYS: Array[StringName] = [&"SLOT_WEAPON", &"SLOT_HELM", &"SLOT_ARMOR", &"SLOT_TRINKET"]

@export_group("标识")
@export var id: StringName = &""
## 名字的翻译 key。界面一律 tr(name_key)，不写死人话
@export var name_key: StringName = &""

@export_group("部位与品质")
@export var slot: Slot = Slot.WEAPON
@export var tier: Tier = Tier.COMMON

@export_group("词条（0 = 没有这条）")
## 攻击加成，直接叠加进 damage_scale。0.15 = +15%
@export var atk_bonus: float = 0.0
## 生命上限加成（点，不是比例）
@export var hp_bonus: int = 0
## 减伤比例。0.1 = 受到的伤害少 10%。全身上限见 Health.MAX_DAMAGE_REDUCTION
@export var def_bonus: float = 0.0


## 本装备所属槽位的字符串 id（存档 / 装备栏字典的 key）
func slot_id() -> StringName:
	return SLOT_IDS[int(slot)]


## 槽位显示名的翻译 key
func slot_key() -> StringName:
	return SLOT_KEYS[int(slot)]


## 品质颜色。普通灰白 / 精良蓝 / 稀有紫 —— 与造梦西游的装备品质观感一致
func tier_color() -> Color:
	match tier:
		Tier.RARE:
			return Color(0.78, 0.55, 0.95)
		Tier.FINE:
			return Color(0.45, 0.72, 0.95)
		_:
			return Color(0.88, 0.88, 0.84)


## 词条是否一条都没有（空装备的兜底显示用）
func has_no_stat() -> bool:
	return is_zero_approx(atk_bonus) and hp_bonus == 0 and is_zero_approx(def_bonus)
