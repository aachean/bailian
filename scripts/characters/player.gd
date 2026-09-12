extends CharacterBody2D
## 《百炼》玩家角色 —— M1 的第二步：移动 + 跳跃 + 三段连招 + 闪避。
##
## 设计原则（整个项目都遵守）：
##   1. 所有可调数值放在 @export 或 data/skills/*.tres 里，改完立刻看效果，不改逻辑。
##   2. 脚本里不出现"魔法数字"。
##   3. 手感优先。土狼时间、跳跃缓冲、连招缓冲、顿帧，都是这类游戏的地基。
##
## ── 状态机只有三个状态 ────────────────────────────────────────
## FREE（自由行动，地面和空中都算这一个）/ ATTACK / DODGE。
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

enum State { FREE, ATTACK, DODGE }

const COMBO_PATHS := [
	"res://data/skills/attack_1.tres",
	"res://data/skills/attack_2.tres",
	"res://data/skills/attack_3.tres",
]
const DODGE_PATH := "res://data/skills/dodge.tres"

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

# ── 供自动验收读取的公开状态。改这些名字会让 tests/ 一起改 ──────
var state: int = State.FREE
## 当前是连招的第几段（0/1/2），不在攻击时为 -1
var attack_index: int = -1
## 累计出招次数。用来断言「连按三次真的打了三段」而不是一次
var attacks_started: int = 0
var dodges_started: int = 0
## 闪避冷却剩余帧数
var dodge_cooldown: int = 0

var _state_frame: int = 0
var _hitstop: int = 0
var _current: SkillData = null
var _attack_queued: bool = false
var _dodge_queued: bool = false
var _dodge_dir: int = 1

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 1200.0)
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
## 常态碰撞掩码。闪避时会被改掉，动作结束再还原
var _body_mask: int = 0

## 面朝方向：1 = 右，-1 = 左。它是一份"状态"，不是每帧算出来的临时值
var _facing: int = 1

@onready var _visuals: Node2D = $Visuals
@onready var _blade: ColorRect = $Visuals/Blade
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

	_update_facing()
	move_and_slide()


# ─────────────────────────────────────────────────────────────
# 自由行动（地面 / 空中）
# ─────────────────────────────────────────────────────────────

func _free_process(delta: float) -> void:
	_apply_gravity(delta)
	_update_jump(delta)
	_update_horizontal(delta)
	_try_start_action()


func _try_start_action() -> void:
	if Input.is_action_just_pressed("dodge") and can_dodge():
		_start_dodge()
		return
	if Input.is_action_just_pressed("attack"):
		if attack_requires_ground and not is_on_floor():
			return
		if not attack_combo.is_empty():
			_start_attack(0)


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
	velocity.x = sk.lunge_speed * sk.lunge_factor(t) * float(_facing)

	if sk.is_active_at(t):
		_hitbox.activate(sk, self, _facing)
		_blade.modulate.a = 1.0
	else:
		_hitbox.deactivate()
		_blade.modulate.a = 0.0

	# 缓冲这次按键，而不是因为它「按早了」就丢掉
	_latch_action_input()

	# 闪避可以打断自己的攻击 —— 出招硬直期间被贴身时，玩家得有路可走
	if _dodge_queued and dodge_cancels_attack and can_dodge():
		_start_dodge()
		return

	# 衔接窗口：判定结束之后、动作结束之前，且这一段允许被取消
	var last := sk.total_frames() - 1
	if sk.chainable and t >= sk.active_to() and t < last \
			and _attack_queued and attack_index + 1 < attack_combo.size():
		_start_attack(attack_index + 1)
		return

	if t >= last:
		_end_action()


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
	_health.invincible = false
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
	_hitstop = maxi(_hitstop, frames)
	if target != null and target.has_method("apply_hitstop"):
		target.call("apply_hitstop", frames)


## 调试用：把状态名打出来（回放字幕和日志都靠它）
func state_name() -> String:
	match state:
		State.ATTACK:
			return "ATTACK%d" % (attack_index + 1)
		State.DODGE:
			return "DODGE"
		_:
			return "AIR" if not is_on_floor() else "FREE"
