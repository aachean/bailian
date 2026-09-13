extends CanvasLayer
## 玩家 HUD：左上角色状态（血 / 蓝 / 经验 / 等级），右上背包（精铁）。
## C 键开角色面板（属性总览）。
##
## 挂在玩家场景里 —— CanvasLayer 不吃相机变换，永远钉在屏幕角上。
## 数据直接读父节点（玩家），每帧轮询刷新：血 / 蓝 / 碎片 / 经验都可能变，
## 与其给每个变化点接信号，不如一帧一次的轮询便宜又不会漏。

@onready var _player: Node = get_parent()
@onready var _hp_fill: ColorRect = $Status/HPBar/Fill
@onready var _mp_fill: ColorRect = $Status/MPBar/Fill
@onready var _exp_fill: ColorRect = $ExpBar/Fill
@onready var _lv_label: Label = $Status/Level
@onready var _bag_label: Label = $Bag/Count
@onready var _panel: Panel = $CharPanel
@onready var _panel_text: Label = $CharPanel/Text
@onready var _skill_cd: ColorRect = $SkillBar/Cooldown
@onready var _skill_icon: ColorRect = $SkillBar/Icon
@onready var _skill_core: ColorRect = $SkillBar/IconCore


func _ready() -> void:
	_panel.visible = false
	refresh()


func _process(_delta: float) -> void:
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("panel"):
		_panel.visible = not _panel.visible
		refresh()


func refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var h := _player.get_node("Health") as Health
	var level := int(_player.get("level"))
	var exp_pts := int(_player.get("exp_pts"))
	var mp := int(_player.get("mp"))
	var max_mp := int(_player.get("max_mp"))
	var needed: int = PlayerState.exp_needed(level)

	if h != null:
		_hp_fill.scale.x = clampf(h.ratio(), 0.0, 1.0)
	_mp_fill.scale.x = 0.0 if max_mp <= 0 else clampf(float(mp) / float(max_mp), 0.0, 1.0)
	_exp_fill.scale.x = clampf(float(exp_pts) / float(needed), 0.0, 1.0)
	_lv_label.text = "Lv.%d" % level
	_bag_label.text = "%s ×%d" % [tr("HUD_SHARD"), int(_player.get("shards"))]

	refresh_skill_bar()

	if _panel.visible:
		# 造梦西游式属性表：一行一项，标签与数值对齐
		var hp := 0 if h == null else h.hp
		var max_hp := 0 if h == null else h.max_hp
		var dmg: float = _player.get_node("Hitbox").damage_scale
		_panel_text.text = "%s %d\n%s %d / %d\n%s %d / %d\n%s %d / %d\n%s +%d%%\n%s %s ×%d\n%s %s Lv.%d" % [
			tr("PANEL_LEVEL"), level,
			tr("PANEL_EXP"), exp_pts, needed,
			tr("PANEL_HP"), hp, max_hp,
			tr("PANEL_MP"), mp, max_mp,
			tr("PANEL_ATK"), int((dmg - 1.0) * 100.0),
			tr("PANEL_SHARD"), tr("HUD_SHARD"), shards_of(),
			tr("PANEL_WEAPON"), tr("HUD_WEAPON"), int(_player.get("upgrade_level")),
		]


## 技能栏：冷却遮罩从满格缩到无（造梦西游式），蓝不足时图标变暗
func refresh_skill_bar() -> void:
	var skill = _player.get("skill")
	if skill == null:
		_skill_cd.visible = false
		return
	var cd := int(_player.get("skill_cooldown"))
	var total: int = skill.total_frames() + skill.cooldown_frames
	var mp := int(_player.get("mp"))
	var need: int = skill.mp_cost
	var no_mp: bool = mp < need
	if cd > 0:
		_skill_cd.visible = true
		_skill_cd.scale.y = clampf(float(cd) / float(total), 0.05, 1.0)
	else:
		_skill_cd.visible = false
	var dim := 0.45 if no_mp else 1.0
	_skill_icon.modulate = Color(dim, dim, dim, 1.0)
	_skill_core.modulate = Color(dim, dim, dim, 1.0)


func shards_of() -> int:
	return int(_player.get("shards")) if _player != null and is_instance_valid(_player) else 0
