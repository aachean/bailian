extends CharacterBody2D
## 近战追击敌人（第一种小怪）：巡逻 → 发现玩家 → 追 → 挥击。
##
## 和训练靶子共用同一套骨架（CharacterBody2D + Health + 后仰/闪白/重生），
## 差别只在多了 AI。攻击动作直接复用玩家的 SkillData —— 敌我双方的动作
## 是同一张表，手感规则（前摇 / 判定 / 后摇 / 顿帧）天然一致。
##
## ai_enabled = false 时它就是一只靶子：物理和受击反馈都在，AI 不跑。
## 自动验收靠这个开关把「移动测试」和「敌人测试」隔离在同一间房里。

enum State { PATROL, CHASE, ATTACK, HURT, DEAD }

const DAMAGE_NUMBER := preload("res://scenes/ui/damage_number.tscn")

## 后仰弹簧参数，与靶子一致 —— 挨打的观感应该敌我相同
const RECOIL_STIFF := 1500.0
const RECOIL_DAMP := 30.0
const RECOIL_KICK := 420.0
const RECOIL_KICK_HEAVY := 1.6

@export_group("数值")
## 用哪套数值。留空则加载 data/enemies/walker.tres
@export var data: EnemyData
## 关掉 = 一只靶子（AI 不跑，只保留物理与受击表现）
@export var ai_enabled: bool = true

@onready var health: Health = $Health
@onready var visuals: Node2D = $Visuals
@onready var flash: ColorRect = $Visuals/Flash
@onready var bar: Node2D = $HealthBar
@onready var bar_fill: ColorRect = $HealthBar/Fill
@onready var _hitbox: Hitbox = $Hitbox

## 供自动验收读取
var state: int = State.PATROL
var attacks_started: int = 0
var hits_taken: int = 0

var _frame := 0                 # 当前状态内经过的物理帧
var _home_x := 0.0              # 出生点（巡逻围绕它）
var _facing := 1
var _cooldown := 0
var _turn_cooldown := 0         # 巡逻折返后的方向锁定帧数
var _skill: SkillData = null    # 攻击进行中引用的那张技能表
var _hitstop := 0
var _revive_t := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 1200.0)
# 受击视觉（与靶子同一套）
var _recoil := 0.0
var _recoil_v := 0.0
var _flash := 0.0
var _alpha := 1.0
var _target_alpha := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if data == null:
		data = load("res://data/enemies/walker.tres") as EnemyData
	health.max_hp = data.max_hp
	health.hp = data.max_hp
	health.post_hit_invincible = 0.10
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.revived.connect(_on_revived)
	_home_x = global_position.x
	_refresh_bar()


func _physics_process(delta: float) -> void:
	if _hitstop > 0:
		_hitstop -= 1
		return

	if _cooldown > 0:
		_cooldown -= 1
	if _turn_cooldown > 0:
		_turn_cooldown -= 1

	velocity.y += _gravity * delta

	if not ai_enabled:
		# 靶子模式：只保留物理与后仰，不跑 AI
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		move_and_slide()
		_update_recoil(delta)
		return

	_frame += 1
	match state:
		State.PATROL:
			_patrol()
		State.CHASE:
			_chase()
		State.ATTACK:
			_attack()
		State.HURT:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			if _frame >= data.hurt_stun_frames:
				_enter(State.CHASE)
		State.DEAD:
			velocity.x = 0.0

	move_and_slide()
	_update_recoil(delta)


# ── AI ─────────────────────────────────────────────────────────

func _player() -> Node2D:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	# 玩家死了就当没看见 —— 追一个尸体没有意义
	if p != null:
		var h := p.get_node_or_null("Health") as Health
		if h != null and h.is_dead:
			return null
	return p


func _patrol() -> void:
	var player := _player()
	if player != null and _dist(player) <= data.aggro_range:
		_enter(State.CHASE)
		return
	# 在出生点两侧来回走。被墙 / 玩家车身挡住时也要折返 ——
	# 只看位置会卡死在障碍物前原地推墙。
	# 折返后留一小段冷却：is_on_wall() 反映的是上一帧的碰撞结果，
	# 不冷却的话会在墙边一帧翻两次面抖死。
	var lo := _home_x - data.patrol_range * 0.5
	var hi := _home_x + data.patrol_range * 0.5
	if _turn_cooldown <= 0 and (is_on_wall() or global_position.x <= lo or global_position.x >= hi):
		_facing = -_facing
		_turn_cooldown = 20
	velocity.x = data.patrol_speed * float(_facing)
	_apply_facing()


func _chase() -> void:
	var player := _player()
	if player == null or _dist(player) > data.deaggro_range:
		_enter(State.PATROL)
		return
	if _dist(player) <= data.attack_range and _cooldown <= 0:
		_start_attack()
		return
	_facing = -1 if player.global_position.x < global_position.x else 1
	velocity.x = data.chase_speed * float(_facing)
	_apply_facing()


func _attack() -> void:
	# 挥出去就挥完 —— 中途改变主意会看不出「前摇」这件事
	velocity.x = 0.0
	var t := _frame
	if _skill != null and _skill.is_active_at(t):
		_hitbox.activate(_skill, self, _facing)
	else:
		_hitbox.deactivate()
	if t >= _skill.total_frames():
		_hitbox.deactivate()
		_skill = null
		_cooldown = data.attack_cooldown_frames
		_enter(State.CHASE)


func _start_attack() -> void:
	_skill = data.attack_skill
	attacks_started += 1
	_enter(State.ATTACK)
	velocity.x = _skill.lunge_speed * float(_facing)


func _enter(s: int) -> void:
	# 离开攻击状态时必须关判定 —— 判定框是多留一帧都会多结算一次的东西
	if state == State.ATTACK and s != State.ATTACK:
		_hitbox.deactivate()
	state = s
	_frame = 0
	_apply_facing()


func _dist(player: Node2D) -> float:
	return absf(player.global_position.x - global_position.x)


func _apply_facing() -> void:
	visuals.scale.x = 1.0 if _facing >= 0 else -1.0


# ── 受击 / 死亡 / 重生（与靶子同一套表现）──────────────────────

func apply_hitstop(frames: int) -> void:
	_hitstop = maxi(_hitstop, frames)


func is_alive() -> bool:
	return not health.is_dead


func _on_damaged(amount: int, _hp_left: int, point: Vector2, heavy: bool, dir: int) -> void:
	hits_taken += 1
	_spawn_number(amount, point, heavy)
	var sign_dir := 1.0 if dir >= 0 else -1.0
	_recoil_v += RECOIL_KICK * sign_dir * (RECOIL_KICK_HEAVY if heavy else 1.0)
	_flash = maxf(_flash, 1.0 if heavy else 0.75)
	_refresh_bar()
	if ai_enabled and not health.is_dead:
		_skill = null
		_enter(State.HURT)          # 被打断：攻击 / 追击统统让位给硬直


func _on_died() -> void:
	_enter(State.DEAD)
	_revive_t = data.revive_delay
	_target_alpha = 0.0
	set_collision_layer_value(2, false)
	bar.visible = false


func _on_revived() -> void:
	_enter(State.PATROL)
	_target_alpha = 1.0
	_alpha = 0.0
	_recoil = 0.0
	_recoil_v = 0.0
	_flash = 0.0
	flash.modulate.a = 0.0
	modulate.a = 0.0
	set_collision_layer_value(2, true)
	bar.visible = true
	_refresh_bar()


func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, 7.0 * delta)
	flash.modulate.a = _flash
	if not is_equal_approx(_alpha, _target_alpha):
		_alpha = move_toward(_alpha, _target_alpha, 5.5 * delta)
		modulate.a = _alpha
	if _revive_t > 0.0:
		_revive_t -= delta
		if _revive_t <= 0.0:
			health.heal_full()


func _update_recoil(delta: float) -> void:
	_recoil_v += (-_recoil * RECOIL_STIFF - _recoil_v * RECOIL_DAMP) * delta
	_recoil += _recoil_v * delta
	visuals.position.x = _recoil


func _spawn_number(amount: int, point: Vector2, heavy: bool) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var dn := DAMAGE_NUMBER.instantiate() as Label
	host.add_child(dn)
	dn.position = point + Vector2(_rng.randf_range(-8.0, 8.0) - 40.0, -12.0)
	dn.setup(amount, heavy)


func _refresh_bar() -> void:
	bar_fill.scale.x = clampf(health.ratio(), 0.0, 1.0)
