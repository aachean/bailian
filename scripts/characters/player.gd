extends CharacterBody2D
## 《百炼》玩家角色 —— M1 的第二步：移动 + 跳跃 + 三段连招 + 闪避。
##
## 设计原则（整个项目都遵守）：
##   1. 所有可调数值放在 @export 或 data/skills/*.tres 里，改完立刻看效果，不改逻辑。
##   2. 脚本里不出现"魔法数字"。
##   3. 手感优先。土狼时间、跳跃缓冲、连招缓冲、顿帧，都是这类游戏的地基。
##
## ── 状态机只有五个状态 ────────────────────────────────────────
## FREE（自由行动，地面和空中都算这一个）/ ATTACK / DODGE / HURT（受击硬直）
## / DEAD。M1 时只有前三个，因为靶子不还手；M2 有会打人的怪了，
## 「被打」本身必须是玩家状态机里的一等公民，而不是一个瞬间。
## 没有拆成 IDLE/RUN/JUMP/AIRFALL/…那一套：现在只有这一个使用者，
## 拆细只会让「角色现在在干嘛」更难一眼看出来。M2 有怪物 AI 要复用时再抽。
##
## ── 时间单位全是【帧】，基准 60fps ─────────────────────────────
## 和 SkillData 一致。判定在第几帧生效、闪避无敌到第几帧，都必须可复现，
## 不然自动验收里「第几帧命中」这类断言就没意义了。
##
## ── 一条手感纪律：连招缓冲 ────────────────────────────────────
## 按了攻击键但当前段还不能衔接时，不是丢弃这次按键，而是【记住】它，
## 等衔接窗口一开就自动接上。玩家连按起来是「哒哒哒」连成一片，
## 而不是「按早了就没反应」。这就是「按一下没接上」和「按一下接上了」的分界。

enum State { FREE, ATTACK, DODGE, HURT, DEAD }

const COMBO_PATHS := [
	"res://data/skills/attack_1.tres",
	"res://data/skills/attack_2.tres",
	"res://data/skills/attack_3.tres",
]
const DODGE_PATH := "res://data/skills/dodge.tres"

## 技能池：按解锁等级排。加一个技能 = 加一个 .tres + 这里加一行。
## 顺序同时决定了三件事：技能面板里的显示顺序、升级时自动补位的顺序、
## 以及「解锁了但没带」的判定基准
const SKILL_PATHS := [
	"res://data/skills/whirl.tres",       # 旋风斩 Lv1
	"res://data/skills/thrust.tres",      # 突刺斩 Lv2
	"res://data/skills/ironwall.tres",    # 铁壁 Lv3
	"res://data/skills/sword_wave.tres",  # 剑气斩 Lv4
	"res://data/skills/quake.tres",       # 崩山击 Lv5
	"res://data/skills/breathe.tres",     # 调息 Lv6
	"res://data/skills/upcut.tres",       # 上撩斩 Lv8
]

## 携带的 5 个技能（槽位 → SkillData，空槽 null）。真相在 PlayerState.skill_slots
var skills: Array[SkillData] = []
## 每个槽独立的冷却（帧）。技能多了以后必须各算各的 ——
## 共用一个冷却的话，五连放完要等五个冷却，等于只有一个技能
var skill_cooldowns: Array = [0, 0, 0, 0, 0]

## 槽 0 的技能与冷却。这是 M3-1 就存在的旧接口（那会儿只有一个技能），
## 留着是因为 anvil / HUD / test_m4 都在用它 —— 语义仍然成立：第一格
var skill: SkillData:
	get:
		return skills[0] if skills.size() > 0 else null

var skill_cooldown: int:
	get:
		return int(skill_cooldowns[0]) if skill_cooldowns.size() > 0 else 0
	set(value):
		if skill_cooldowns.size() > 0:
			skill_cooldowns[0] = value

@export_group("移动")
## 最大水平速度（像素/秒）
@export var max_speed: float = 180.0
## 从静止加速到最大速度所需时间（秒）。越小越灵敏
@export var accel_time: float = 0.08
## 松开方向键后减速到静止所需时间（秒）
@export var friction_time: float = 0.06

@export_group("跳跃")
## 起跳初速度（像素/秒）。Godot 的 Y 轴向下为正，所以是负数
@export var jump_velocity: float = -420.0
## 下落时的重力倍率。大于 1 会让下落更快、跳跃更"脆"，是横版动作的常用手法
@export var fall_gravity_scale: float = 1.6

@export_group("宽容度")
## 土狼时间（秒）：刚走出平台边缘后仍允许起跳的宽限
@export var coyote_time: float = 0.10
## 跳跃缓冲（秒）：落地前提前按跳，落地瞬间会自动起跳
@export var jump_buffer_time: float = 0.10

@export_group("碰撞")
## 敌人的碰撞层。平时玩家被敌人挡住 —— 不然近身打完一套会从敌人身上滑过去，
## 打到的是空气。闪避期间会临时忽略这一层：「滚过敌人」是横版动作里
## 逃出包围的标准手段，不能让敌人把自己的退路堵死。
@export_flags_2d_physics var enemy_physics_layer: int = 2

@export_group("战斗")
## 三段连招，数组顺序 = 按键顺序。留空则从 data/skills/ 加载默认三连
@export var attack_combo: Array[SkillData] = []
## 闪避。留空则从 data/skills/dodge.tres 加载
@export var dodge_skill: SkillData = null
## 闪避能不能打断自己的攻击。关掉 = 出招期间完全不能闪（更硬，但更容易挨打）
@export var dodge_cancels_attack: bool = true
## 攻击要不要限定在地面。M1 先不做空中攻击
@export var attack_requires_ground: bool = true

@export_group("受击")
## 被击中后的硬直（帧 @60fps）。硬直里输入全部无效 —— 挨打要有代价
@export var hurt_stun_frames: int = 14
## 被击中时沿受击方向弹开的速度（像素/秒）
@export var hurt_knockback: float = 140.0
## 倒地之后过多久弹出死亡界面（秒）。**这段延迟是刻意的** ——
## 立刻弹界面会让「我怎么死的」来不及看清，先让人躺一下
@export var revive_delay: float = 1.2

# ── 供自动验收读取的公开状态。改这些名字会让 tests/ 一起改 ──────
var state: int = State.FREE
## 当前是连招的第几段（0/1/2），不在攻击时为 -1
var attack_index: int = -1
## 累计出招次数。用来断言「连按三次真的打了三段」而不是一次
var attacks_started: int = 0
var casts_started: int = 0
var dodges_started: int = 0
## 闪避冷却剩余帧数
var dodge_cooldown: int = 0
## 累计挨打 / 死亡次数（自动验收用）
var hurts_taken: int = 0
var deaths: int = 0
## 精铁碎片（强化素材）与武器强化等级 —— 进存档，随快照恢复
var shards: int = 0
var upgrade_level: int = 0
## 等级 / 经验跨场景住在 PlayerState；蓝量是场景内资源（回城满蓝）
var level: int = 1
var exp_pts: int = 0
var mp: int = 50
var max_mp: int = 50
var _mp_regen_tick := 0

var _state_frame: int = 0
var _hitstop: int = 0
var _current: SkillData = null
var _attack_queued: bool = false
var _dodge_queued: bool = false
var _dodge_dir: int = 1
var _revive_t: float = 0.0
## 已经喊过「倒下之后怎么办」了。切场景 / 弹界面都是排队到帧末才发生的，
## 不设这道闸的话，这一帧里会连着喊好几次
var _reviving := false
var _hurt_flash: float = 0.0
## 升级金光的标记（与受击红光共用衰减通道）
var _level_flash := false
## 装备给的减伤基线。铁壁这类技能出招期间会临时改用更大的减伤，
## 动作结束要恢复到这条基线（不然格挡一次，全身减伤永久变了）
var _base_reduction: float = 0.0
## 本次出招的投射物有没有发过（判定窗口跨 4 帧，只该发一道剑气）
var _projectile_fired := false

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 1200.0)
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
## 常态碰撞掩码。闪避时会被改掉，动作结束再还原
var _body_mask: int = 0

## 面朝方向：1 = 右，-1 = 左。它是一份"状态"，不是每帧算出来的临时值
var _facing: int = 1

## 出生点 = 场景里摆的位置（_ready 那一刻的坐标）。
## 测试里瞬移玩家不影响它 —— 重生永远回到关卡设计者定的那个点。
var _spawn_point: Vector2 = Vector2.ZERO

## 掉到这条线以下视为掉出世界（场景高 360，地面在 320 附近）
const FALL_KILL_Y := 800.0


## 读档恢复（stage.gd 调用）：血量与位置回到离开那一刻。
## 状态一律回到 FREE —— 存档瞬间可能在闪避/硬直里，那些不该被「续」上。
func apply_saved(d: Dictionary) -> void:
	_end_action()
	shards = int(d.get("shards", shards))
	upgrade_level = int(d.get("upgrade", upgrade_level))
	level = int(d.get("level", level))
	exp_pts = int(d.get("exp", exp_pts))
	mp = int(d.get("mp", max_mp))
	PlayerState.shards = shards
	PlayerState.upgrade_level = upgrade_level
	PlayerState.level = level
	PlayerState.exp = exp_pts
	# 装备栏 / 背包也在快照里，先摆回 PlayerState 再算属性
	if d.has("equipped") or d.has("bag"):
		PlayerState.set_equipment(d.get("equipped", {}) as Dictionary, d.get("bag", []) as Array)
	# 携带的技能同理
	if d.has("skill_slots"):
		PlayerState.skill_slots = (d.get("skill_slots", []) as Array).duplicate()
		PlayerState.skills_changed.emit()
	max_mp = 50 + (level - 1) * 10
	# 装备栏住在 PlayerState（存档恢复时已一并回填），这里按它重算上限与倍率。
	# 血量必须在这之后再摆 —— _set_max_hp 会动 hp，
	# 先 restore 再改上限的话，读回来的血量会被上限变动改写
	_apply_upgrade()
	_health.restore(int(d.get("hp", _health.max_hp)))
	_hurt_flash = 0.0
	_visuals.modulate = Color.WHITE
	# 复活点也存进了快照 —— 不存的话读档后死一次，人回到关卡最开头，
	# 中途的复活点（checkpoint.tscn）就白踩了。
	# 必须放在下面那行**之前**：_spawn_point 正是位置的兜底默认值
	_spawn_point = Vector2(float(d.get("spawn_x", _spawn_point.x)), float(d.get("spawn_y", _spawn_point.y)))
	global_position = Vector2(float(d.get("x", _spawn_point.x)), float(d.get("y", _spawn_point.y)))
	velocity = Vector2.ZERO
	state = State.FREE
	_state_frame = 0


## 中途复活点用（checkpoint.tscn 调）：把「死后回到哪」推到当前位置。
## 关卡越做越长之后，死在关底要重走整关 —— 那不叫难度
func set_spawn_point(p: Vector2) -> void:
	_spawn_point = p


## 当前复活点。存档要存它，所以留一个读取口
func spawn_point() -> Vector2:
	return _spawn_point

@onready var _visuals: Node2D = $Visuals
@onready var _blade: ColorRect = $Visuals/Blade
@onready var _whirl_fx: Node2D = $Visuals/WhirlFx
@onready var _hitbox: Hitbox = $Hitbox
@onready var _health: Health = $Health
@onready var _shape_node: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# 连招和闪避是数据，不写死在这里；tscn 里若已指定则优先用 tscn 的
	if attack_combo.is_empty():
		for p in COMBO_PATHS:
			var r := load(p)
			if r is SkillData:
				attack_combo.append(r)
			else:
				push_error("[player] 连招数据加载失败: %s" % p)
	if dodge_skill == null:
		dodge_skill = load(DODGE_PATH) as SkillData
	_body_mask = collision_mask
	_hitbox.hit_landed.connect(_on_hit_landed)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	_health.revived.connect(_on_revived)
	_health.hp_changed.connect(_update_hp_bar)
	# 碎片 / 强化 / 等级经验是「属于玩家」的数据，住在 PlayerState（autoload）里 ——
	# 切场景会重建玩家节点，存在节点上的东西会丢（实测丢过）
	shards = PlayerState.shards
	upgrade_level = PlayerState.upgrade_level
	level = PlayerState.level
	exp_pts = PlayerState.exp
	# 回城即治疗：进场景满血满蓝；等级越高蓝上限越高
	max_mp = 50 + (level - 1) * 10
	mp = max_mp
	if not PlayerState.level_up.is_connected(_on_level_up):
		PlayerState.level_up.connect(_on_level_up)
	if not PlayerState.exp_changed.is_connected(_on_exp_changed):
		PlayerState.exp_changed.connect(_on_exp_changed)
	if not PlayerState.equipment_changed.is_connected(_on_equipment_changed):
		PlayerState.equipment_changed.connect(_on_equipment_changed)
	if not PlayerState.skills_changed.is_connected(_on_skills_changed):
		PlayerState.skills_changed.connect(_on_skills_changed)
	# 技能：先按当前等级把「已解锁但没带」的技能补进空槽，再读进节点
	_sync_skill_slots()
	_rebuild_skills()
	# 先按「等级 + 强化 + 装备」算全属性，再满血 —— 顺序反了的话
	# 装备加的生命上限会被 heal_full 用旧上限截掉
	_apply_upgrade()
	_health.heal_full()
	_spawn_point = global_position


## 把节点上的技能表按 PlayerState 的槽位重建
func _rebuild_skills() -> void:
	skills.clear()
	for i in PlayerState.SKILL_SLOT_COUNT:
		skills.append(PlayerState.skill_at(i))
	while skill_cooldowns.size() < PlayerState.SKILL_SLOT_COUNT:
		skill_cooldowns.append(0)


func _on_skills_changed() -> void:
	_rebuild_skills()
	var hud := get_node_or_null("HUD")
	if hud != null and hud.has_method("refresh"):
		hud.call("refresh")


## 按等级算「哪些技能已解锁」，把没带的补进空槽。
## 补位只填空槽 —— 槽满了换哪个是玩家的决定，系统不替他做主
func _sync_skill_slots() -> void:
	PlayerState.auto_fill_slots(unlocked_skill_paths())


## 当前等级下已解锁的技能资源路径（按 SKILL_PATHS 的顺序）
func unlocked_skill_paths() -> Array:
	var out: Array = []
	for p in SKILL_PATHS:
		var sk := load(p) as SkillData
		if sk != null and level >= sk.unlock_level:
			out.append(p)
	return out


## 整个技能池的路径（技能面板按这个顺序列）
func skill_pool_paths() -> Array:
	return SKILL_PATHS.duplicate()


## 某个技能是否已解锁（技能面板用它把未解锁的画灰）
func is_skill_unlocked(p: String) -> bool:
	var sk := load(p) as SkillData
	return sk != null and level >= sk.unlock_level


func _exit_tree() -> void:
	# 离开场写回：下一次进任何场景，碎片和等级都还在。
	# 装备栏 / 背包不在这里写回 —— 它们本来就住在 PlayerState，玩家节点只是读者
	PlayerState.shards = shards
	PlayerState.upgrade_level = upgrade_level
	PlayerState.level = level
	PlayerState.exp = exp_pts


## 击杀经验落到场景内玩家头上：同步字段并让 HUD 的经验条当场涨
func _on_exp_changed(new_exp: int) -> void:
	exp_pts = new_exp
	var hud := get_node_or_null("HUD")
	if hud != null and hud.has_method("refresh"):
		hud.call("refresh")


## 升级：血上限 +15、蓝上限 +10，血蓝全回满，外加一圈金光和飘字 ——
## 升级就该有仪式感，没反馈的成长等于没升级（用户实测反馈）
func _on_level_up(new_level: int) -> void:
	level = new_level
	max_mp = 50 + (level - 1) * 10
	# 升级可能解锁新技能：有空槽就自动补进去（槽满了不动，换哪个由玩家决定）
	_sync_skill_slots()
	# 血上限、攻击倍率、减伤统一由 _apply_upgrade 重算（含装备词条），
	# 再回满 —— 升级是「上限涨了并且当场补满」，不是「上限涨了血条变短」
	_apply_upgrade()
	_health.heal_full()
	mp = max_mp
	_level_up_fx()


func _level_up_fx() -> void:
	_hurt_flash = 1.0
	_level_flash = true
	var host := get_tree().current_scene
	if host == null:
		return
	var lbl := Label.new()
	lbl.z_index = 50
	lbl.text = tr("UI_LEVELUP")
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	lbl.position = global_position + Vector2(-30, -70)
	host.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 30.0, 1.0)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.0)
	tw.tween_callback(lbl.queue_free)


func _update_hp_bar(_hp: int, _max_hp: int) -> void:
	($HealthBar/Fill as ColorRect).scale.x = clampf(_health.ratio(), 0.0, 1.0)


## 武器强化每级 +20%；角色等级每级 +5%；装备的攻击词条直接相加（同一个乘区）。
## 改的是 Hitbox 的伤害倍率，技能表（招式本身）不动 —— 强化的是人，不是招
const UPGRADE_STEP := 0.2
const LEVEL_ATK_STEP := 0.05

## 手里那把刀的样子。攻击时挥出的光刃跟着【当前武器】走：换了武器，
## 刃的颜色（品质色）和长度都跟着变 —— 装备变强必须看得见，光看面板数字不够
const BLADE_BASE_COLOR := Color(0.96, 0.92, 0.76)
const BLADE_BASE_REACH := 42.0


## 重算玩家身上所有「由外部数据推导出来」的属性：攻击倍率 / 生命上限 / 减伤。
## 触发点：开局、升级、铁砧强化、换装备、读档。
## 名字保留 _apply_upgrade（原本只干「强化」一件事）是因为调用方已经散布在
## anvil.gd / HUD / 测试里，改名的收益小于风险。
func _apply_upgrade() -> void:
	var bonus := PlayerState.bonus_total()
	_hitbox.damage_scale = 1.0 + UPGRADE_STEP * float(upgrade_level) \
		+ LEVEL_ATK_STEP * float(level - 1) + float(bonus.get("atk", 0.0))
	_set_max_hp(100 + (level - 1) * 15 + int(bonus.get("hp", 0)))
	_base_reduction = float(bonus.get("def", 0.0))
	_health.damage_reduction = _base_reduction
	_refresh_blade()
	_refresh_hud()


## 光刃跟着武器变：颜色取品质色（与面板图标、地上掉落物同一个色源），
## 刃长按品质递进。没拿武器时回到默认的米白短刃
func _refresh_blade() -> void:
	var weapon := PlayerState.item_at(&"weapon")
	if weapon == null:
		_blade.color = BLADE_BASE_COLOR
		_blade.offset_right = BLADE_BASE_REACH
	else:
		_blade.color = weapon.tier_color().lightened(0.2)
		_blade.offset_right = BLADE_BASE_REACH + 4.0 * (float(weapon.tier) + 1.0)


## 改生命上限时把新增的那截补进当前血（上限变低则把血夹回去）。
## 少了这一步，穿上 +45 血的铁盔会出现「血条瞬间掉一截」这类观感问题。
## 注意是【补差值】不是【设满血】—— 否则换装就成了免费回血，挨打的代价被抹掉
func _set_max_hp(value: int) -> void:
	var old := _health.max_hp
	_health.max_hp = value
	if value > old:
		_health.hp = mini(_health.hp + (value - old), value)
	else:
		_health.hp = mini(_health.hp, value)


## 换装 / 捡装备：重算属性并刷新界面
func _on_equipment_changed() -> void:
	_apply_upgrade()


## 拾取装备（地面掉落物调）。装备本体进 PlayerState 的背包，玩家节点只负责表现
func collect_item(path: String) -> void:
	if not PlayerState.add_item(path):
		return
	var it := load(path) as ItemData
	if it != null:
		_item_pickup_fx(it)


## 捡到装备时头顶飘出装备名（按品质上色）——
## 掉落拾取必须有反馈，否则玩家不知道自己捡到了什么（设计规范：反馈原则）
func _item_pickup_fx(item: ItemData) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var lbl := Label.new()
	lbl.z_index = 50
	lbl.text = tr(item.name_key)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", item.tier_color())
	lbl.position = global_position + Vector2(-20, -56)
	host.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 26.0, 0.9)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9)
	tw.tween_callback(lbl.queue_free)


## 回血时头顶飘一个绿字 —— 放了技能但屏幕上什么都没发生，玩家不会知道血回来了
func _heal_fx(amount: int) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var lbl := Label.new()
	lbl.z_index = 50
	lbl.text = "+%d" % amount
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 0.45))
	lbl.position = global_position + Vector2(-14, -58)
	host.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 26.0, 0.8)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(lbl.queue_free)


func _refresh_hud() -> void:
	var hud := get_node_or_null("HUD")
	if hud != null and hud.has_method("refresh"):
		hud.call("refresh")


## 拾取碎片（Pickup 组件调）。满 3 块可去城镇铁砧强化一次
func collect_shard() -> void:
	shards += 1
	PlayerState.shards = shards
	_refresh_hud()


func _physics_process(delta: float) -> void:
	if _hitstop > 0:
		_hitstop -= 1
		# 顿帧期间动作冻住，但【按键必须照收】。
		# 只 return 不采样输入的话，命中那几帧里按下的 J 会被整个丢掉 ——
		# 而「打到人的那一瞬间」恰恰是玩家最容易连按的时候，
		# 结果是连招莫名其妙断在第二段。这个 bug 是自动验收抓出来的。
		_latch_action_input()
		return

	if dodge_cooldown > 0:
		dodge_cooldown -= 1
	# 五个槽各算各的冷却
	for i in skill_cooldowns.size():
		if int(skill_cooldowns[i]) > 0:
			skill_cooldowns[i] = int(skill_cooldowns[i]) - 1

	# 蓝量自然恢复：每半秒回 1 点。站着不动也有，鼓励随时交技能
	_mp_regen_tick += 1
	if _mp_regen_tick >= 30:
		_mp_regen_tick = 0
		mp = mini(mp + 1, max_mp)

	# 掉出世界 = 死。走同一条死亡重生流程，不然被挤下边缘就无限下落。
	if state != State.DEAD and global_position.y > FALL_KILL_Y:
		_health.take_damage(9999, global_position, true, 0)

	# 闪避结束之后，如果人还压在敌人身上，碰撞要晚一点再还原（见 _restore_body_collision_if_clear）
	if state != State.DODGE:
		_restore_body_collision_if_clear()

	match state:
		State.FREE:
			_free_process(delta)
		State.ATTACK:
			_attack_process(delta)
		State.DODGE:
			_dodge_process(delta)
		State.HURT:
			_hurt_process(delta)
		State.DEAD:
			_dead_process(delta)

	_update_hurt_flash(delta)
	_update_facing()
	move_and_slide()


## 受击硬直：输入全部无效，只剩击退的惯性 + 重力。
## 「挨打要停一拍」是动作游戏的基本代价，它让敌人的攻击真的构成威胁。
func _hurt_process(delta: float) -> void:
	_apply_gravity(delta)
	_state_frame += 1
	# 击退衰减要在硬直内走完：否则回到 FREE 后残余速度会把朝向又翻过去
	velocity.x = move_toward(velocity.x, 0.0, max_speed * 6.0 * delta)
	if _state_frame >= hurt_stun_frames:
		_end_action()


## 死亡：锁一切输入，计时结束后**弹一个二选一**。
##
## 2026-09-14 神的要求：不再自动重开，而是让玩家自己选
## ——「重新开始」（重开本副本）或「返回城镇」。理由写在 scripts/ui/death_menu.gd 顶上。
func _dead_process(delta: float) -> void:
	velocity.x = 0.0
	_apply_gravity(delta)
	_revive_t -= delta
	if _revive_t <= 0.0 and not _reviving:
		_reviving = true
		_open_death_menu()


## 倒下之后的去处交给死亡界面（挂在玩家下，与 HUD / 暂停菜单同一套挂法）。
##
## 只有**关卡**才弹（它有 `restart`）—— 测试场景、单独跑的角色场景没有，
## 那些退回**原地满血**：测试要观测「死亡 → 重生」这条链，
## 一死就弹一个要求按键的界面等于把测试卡死在那儿
func _open_death_menu() -> void:
	var menu := get_node_or_null("DeathMenu")
	var root := get_tree().current_scene
	if menu != null and root != null and root.has_method("restart"):
		menu.call("open")
		return
	global_position = _spawn_point
	velocity = Vector2.ZERO
	_health.heal_full()          # 发 revived → _on_revived 把 _reviving 放回去


# ─────────────────────────────────────────────────────────────
# 自由行动（地面 / 空中）
# ─────────────────────────────────────────────────────────────

func _free_process(delta: float) -> void:
	_apply_gravity(delta)
	_update_jump(delta)
	_update_horizontal(delta)
	_try_start_action()


func _try_start_action() -> void:
	# 五个技能键：数字 1~5 直接放对应槽位；L 是 1 号槽的别名（M3-1 的旧习惯）
	for i in PlayerState.SKILL_SLOT_COUNT:
		if Input.is_action_just_pressed("skill_%d" % (i + 1)) and can_cast(i):
			_start_cast(i)
			return
	if Input.is_action_just_pressed("skill") and can_cast(0):
		_start_cast(0)
		return
	if Input.is_action_just_pressed("dodge") and can_dodge():
		_start_dodge()
		return
	if Input.is_action_just_pressed("attack"):
		if attack_requires_ground and not is_on_floor():
			return
		if not attack_combo.is_empty():
			_start_attack(0)


## 某个槽位的技能现在能不能放：有技能、不在冷却、蓝够、站在地上。
## 不传参数 = 槽 0（M3-1 的旧接口，anvil / test_m4 在调）
func can_cast(slot: int = 0) -> bool:
	var sk := skill_in_slot(slot)
	return sk != null and int(skill_cooldowns[slot]) <= 0 \
		and mp >= sk.mp_cost and is_on_floor()


func skill_in_slot(slot: int) -> SkillData:
	if slot < 0 or slot >= skills.size():
		return null
	return skills[slot]


## 放技能：扣蓝、进 ATTACK 状态机（与普攻同一套「前摇→判定→后摇」）、
## 并且执行这一招的额外效果（回血 / 格挡减伤 / 发射剑气）
func _start_cast(slot: int) -> void:
	var sk := skill_in_slot(slot)
	if sk == null:
		return
	mp -= sk.mp_cost
	_current = sk
	_state_frame = 0
	attack_index = -1
	_attack_queued = false
	_dodge_queued = false
	_jump_buffer_timer = 0.0
	_hitbox.deactivate()
	velocity.x = sk.lunge_speed * float(_facing)
	casts_started += 1
	_projectile_fired = false
	skill_cooldowns[slot] = sk.total_frames() + sk.cooldown_frames
	if sk.heal_amount > 0:
		_health.heal(sk.heal_amount)
		_heal_fx(sk.heal_amount)
	state = State.ATTACK


func _apply_gravity(delta: float) -> void:
	var g := _gravity
	if velocity.y > 0.0:
		g *= fall_gravity_scale
	velocity.y += g * delta


func _update_jump(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0


func _update_horizontal(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")

	if not is_zero_approx(direction):
		var accel := max_speed / maxf(accel_time, 0.001)
		velocity.x = move_toward(velocity.x, direction * max_speed, accel * delta)
	else:
		var decel := max_speed / maxf(friction_time, 0.001)
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)


func _update_facing() -> void:
	# HURT / DEAD 期间朝向锁定。击退的速度指向「远离攻击者」的一侧，
	# 如果照常按速度翻朝向，挨打后会变成背对敌人 —— 反打方向全反（用户实测）。
	# 造梦西游的规则：挨打后面向打你的人，正好准备还手。
	if state == State.HURT or state == State.DEAD:
		_visuals.scale.x = float(_facing)
		return
	# 只在真正有横向速度时更新朝向。
	# 这样"停下来"的那一刻会保留上一次的朝向，而不是弹回默认的右侧。
	if not is_zero_approx(velocity.x):
		_facing = 1 if velocity.x > 0.0 else -1

	# 翻转整个 Visuals 容器，而不是逐个去改 Body / Face 的位置。
	# 目的：M3 把色块换成真正的美术资源时，这里一行都不用改。
	_visuals.scale.x = float(_facing)


# ─────────────────────────────────────────────────────────────
# 攻击：三段连招
# ─────────────────────────────────────────────────────────────

func _start_attack(index: int) -> void:
	if index < 0 or index >= attack_combo.size():
		_end_action()
		return
	attack_index = index
	_current = attack_combo[index]
	state = State.ATTACK
	_state_frame = 0
	_attack_queued = false
	_dodge_queued = false
	_jump_buffer_timer = 0.0
	_hitbox.deactivate()
	velocity.x = _current.lunge_speed * float(_facing)
	attacks_started += 1


func _attack_process(delta: float) -> void:
	_apply_gravity(delta)
	_state_frame += 1
	var t := _state_frame - 1        # 本帧是技能的第 t 帧（0 起算）
	var sk := _current

	_health.invincible = sk.is_invincible_at(t)
	# 铁壁这类技能在出招期间额外减伤。与装备减伤【取较大值】，不是相加 ——
	# 叠加很容易堆成免伤，那挨打就没有代价了（同 Health 的 60% 上限精神）
	if sk.guard_reduction > 0.0:
		_health.damage_reduction = maxf(_base_reduction, sk.guard_reduction)
	velocity.x = sk.lunge_speed * sk.lunge_factor(t) * float(_facing)

	if sk.is_active_at(t):
		_hitbox.activate(sk, self, _facing)
		_blade.modulate.a = 1.0
		# 剑气这类技能在判定窗口的第一帧甩出投射物（窗口有 4 帧，只该发一道）
		if not _projectile_fired and sk.projectile_scene != null:
			_projectile_fired = true
			_fire_projectile(sk)
	else:
		_hitbox.deactivate()
		_blade.modulate.a = 0.0

	# 技能特效：旋风斩的判定窗口里三片剑光绕身旋转，前摇渐显、后摇渐隐。
	# 没有这一层，玩家只看到蓝条掉了（用户实测反馈：没有技能效果）
	if sk.id == &"whirl":
		var vis := t >= sk.startup_frames - 2 and t < sk.total_frames() - 4
		_whirl_fx.visible = vis
		if vis:
			_whirl_fx.rotation += 0.42
			_whirl_fx.scale = Vector2.ONE * (0.7 + 0.3 * clampf(float(t) / float(sk.active_to()), 0.0, 1.0))
			_whirl_fx.modulate.a = 0.95 if sk.is_active_at(t) else 0.4
			# 三片剑光在场景里已摆好 0°/120°/240° 方位，这里只转父节点

	# 缓冲这次按键，而不是因为它「按早了」就丢掉
	_latch_action_input()

	# 闪避可以打断自己的攻击 —— 出招硬直期间被贴身时，玩家得有路可走
	if _dodge_queued and dodge_cancels_attack and can_dodge():
		_start_dodge()
		return

	# 衔接窗口：判定结束之后、动作结束之前，且这一段允许被取消。
	# 只有普攻接普攻 —— 技能不参与连招，不然连按会串成一串
	var last := sk.total_frames() - 1
	if sk.chainable and attack_index >= 0 and t >= sk.active_to() and t < last \
			and _attack_queued and attack_index + 1 < attack_combo.size():
		_start_attack(attack_index + 1)
		return

	if t >= last:
		_end_action()


## 这一招是不是「技能」（而不是普攻）。回放字幕与状态名要区分它们
func _is_skill(sk: SkillData) -> bool:
	return sk != null and skills.has(sk)


## 甩出投射物（剑气）。伤害沿用技能自己的 damage，倍率带上装备与强化 ——
## 与近战判定同一条管线（Hitbox.damage_scale），不另算一套
func _fire_projectile(sk: SkillData) -> void:
	if sk.projectile_scene == null:
		return
	var host := get_tree().current_scene
	if host == null:
		return
	var node := sk.projectile_scene.instantiate() as Node2D
	if node == null:
		return
	node.set("damage_scale", _hitbox.damage_scale)
	node.set("target_mask", 2)          # 打敌人层
	host.add_child(node)
	node.global_position = global_position + Vector2(18.0 * float(_facing), -4.0)
	if node.has_method("setup"):
		node.call("setup", node.global_position, Vector2(float(_facing), 0.0),
			sk.projectile_speed, sk.damage, sk.projectile_life, self)


# ─────────────────────────────────────────────────────────────
# 闪避
# ─────────────────────────────────────────────────────────────

func can_dodge() -> bool:
	return dodge_skill != null and dodge_cooldown <= 0


func _start_dodge() -> void:
	var dir := Input.get_axis("move_left", "move_right")
	if is_zero_approx(dir):
		dir = float(_facing)
	_dodge_dir = 1 if dir > 0.0 else -1

	_current = dodge_skill
	state = State.DODGE
	_state_frame = 0
	_attack_queued = false
	_dodge_queued = false
	attack_index = -1
	_jump_buffer_timer = 0.0
	_hitbox.deactivate()
	_blade.modulate.a = 0.0
	# 冷却从「闪避开始」算起，所以要把闪避本身的时长加进去
	dodge_cooldown = dodge_skill.total_frames() + dodge_skill.cooldown_frames
	# 闪避期间忽略敌人层：能滚过敌人，才叫「有退路」
	collision_mask = _body_mask & ~enemy_physics_layer
	velocity.x = dodge_skill.lunge_speed * float(_dodge_dir)
	dodges_started += 1


func _dodge_process(delta: float) -> void:
	_apply_gravity(delta)
	_state_frame += 1
	var t := _state_frame - 1
	var sk := _current

	_health.invincible = sk.is_invincible_at(t)
	velocity.x = sk.lunge_speed * sk.lunge_factor(t) * float(_dodge_dir)

	if t >= sk.total_frames() - 1:
		_end_action()


# ─────────────────────────────────────────────────────────────

## 只做一件事：把这一帧按下的攻击/闪避记进缓冲。不推进任何状态。
## 顿帧分支和攻击分支都调用它，保证「顿帧里按的键」和「正常帧里按的键」待遇一样。
func _latch_action_input() -> void:
	if Input.is_action_just_pressed("attack"):
		_attack_queued = true
	if Input.is_action_just_pressed("dodge"):
		_dodge_queued = true


func _end_action() -> void:
	_hitbox.deactivate()
	_blade.modulate.a = 0.0
	_whirl_fx.visible = false
	_whirl_fx.modulate.a = 0.0
	_health.invincible = false
	_health.damage_reduction = _base_reduction   # 格挡类技能的临时减伤在这里收回去
	_projectile_fired = false
	_current = null
	state = State.FREE
	_state_frame = 0
	attack_index = -1
	_attack_queued = false
	_dodge_queued = false


## 闪避会临时忽略敌人层（见 _start_dodge）。但闪避结束的那一刻如果人正好压在敌人身上，
## 不能立刻把碰撞还原 —— 物理引擎的退出重叠（depenetration）会把人「吐」出去，
## 实测会往后弹 25 px，看起来像瞬移。所以改成：还压着就继续忽略，彻底离开敌人的那一刻再还原。
func _restore_body_collision_if_clear() -> void:
	if collision_mask == _body_mask:
		return
	if _overlaps_enemy():
		return
	collision_mask = _body_mask


func _overlaps_enemy() -> bool:
	if _shape_node == null or _shape_node.shape == null:
		return false
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _shape_node.shape
	params.transform = global_transform
	params.collision_mask = enemy_physics_layer
	params.collide_with_bodies = true
	params.collide_with_areas = false
	params.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty()


## 命中时把双方一起冻住几帧。打击感主要来自这里，不是来自数值
func _on_hit_landed(target: Node2D, _damage: int, _point: Vector2, _heavy: bool) -> void:
	var frames := 0
	if _current != null:
		frames = _current.hitstop_frames
	if frames <= 0:
		return
	apply_hitstop(frames)
	if target != null and target.has_method("apply_hitstop"):
		target.call("apply_hitstop", frames)


## 公开给攻击方（敌人命中玩家时也会走 duck-typing 调这里）
func apply_hitstop(frames: int) -> void:
	_hitstop = maxi(_hitstop, frames)


## 被敌人的判定框打中（Health.damaged）。做四件事：
## 打断当前动作 → 进入硬直 → 沿受击方向弹开 → 闪一下。
## 受击后的短暂无敌由 Health 内部负责（防同一次挥砍连扣），
## 硬直帧数比无敌窗口长，所以连招惩罚依然成立 —— 这是有意的。
func _on_damaged(_amount: int, _hp_left: int, point: Vector2, _heavy: bool, dir: int) -> void:
	hurts_taken += 1
	_level_flash = false
	if state == State.ATTACK or state == State.DODGE:
		_end_action()
	if state == State.DEAD:
		return
	_end_action()
	state = State.HURT
	_state_frame = 0
	var sign_dir := 1 if dir > 0 else (-1 if dir < 0 else -_facing)
	velocity.x = hurt_knockback * float(sign_dir)
	# 面朝打你的人（不是背对他）：击退往反方向推，但脸要转回来准备还手
	_facing = -sign_dir
	_hurt_flash = 1.0


func _on_died() -> void:
	deaths += 1
	_end_action()
	state = State.DEAD
	_revive_t = revive_delay
	_visuals.modulate = Color(0.45, 0.45, 0.5, 0.6)


## Health.heal_full() 会发 revived —— 重生只在这里恢复外观
func _on_revived() -> void:
	state = State.FREE
	_state_frame = 0
	_hurt_flash = 0.0
	_visuals.modulate = Color.WHITE
	# 这道闸要放开：原地重生的路径不走场景重载，不放开的话第二次死亡会站着不动
	_reviving = false


## 受击变红 → 渐回原色。走 physics 帧的衰减，与硬直同步
func _update_hurt_flash(delta: float) -> void:
	if _hurt_flash <= 0.0 or state == State.DEAD:
		return
	_hurt_flash = move_toward(_hurt_flash, 0.0, 6.0 * delta)
	var f := _hurt_flash
	if _level_flash:
		_visuals.modulate = Color(1.0 + 0.3 * f, 1.0, 1.0 - 0.3 * f, 1.0)   # 升级闪金
	else:
		_visuals.modulate = Color(1.0, 1.0 - 0.45 * f, 1.0 - 0.45 * f, 1.0) # 受击闪红


## 调试用：把状态名打出来（回放字幕和日志都靠它）
func state_name() -> String:
	match state:
		State.ATTACK:
			if _is_skill(_current):
				return "SKILL"
			return "ATTACK%d" % (attack_index + 1)
		State.DODGE:
			return "DODGE"
		State.HURT:
			return "HURT"
		State.DEAD:
			return "DEAD"
		_:
			return "AIR" if not is_on_floor() else "FREE"
