extends CharacterBody2D
## 远程小怪「掷矛手」：站在原地朝玩家投矛，玩家贴脸它就抓瞎。
##
## 与 walker 共用 Health / 后仰 / 闪白 / 重生 / EnemyData，差别在攻击方式：
## walker 挥刀（Hitbox 近身判定），掷矛手生成 Projectile 飞过去。
## 站桩不追 —— 玩家的闪避第一次有了明确的对手分工：近战躲刀，远程走位。

enum State { PATROL, AIM, HURT, DEAD }

const DAMAGE_NUMBER := preload("res://scenes/ui/damage_number.tscn")
const PROJECTILE := preload("res://scenes/enemies/projectile.tscn")
const PICKUP := preload("res://scenes/components/pickup.tscn")
const FALL_KILL_Y := 800.0

## 后仰弹簧参数，与 walker / 靶子一致 —— 挨打的观感应该敌我相同
const RECOIL_STIFF := 1500.0
const RECOIL_DAMP := 30.0
const RECOIL_KICK := 420.0

## 蓄力帧数：从面向玩家到矛出手。玩家靠这几帧反应
const AIM_FRAMES := 30

@export_group("数值")
@export var data: EnemyData
## 关掉 = 一只靶子（与 walker 同约定，验收隔离用）
@export var ai_enabled: bool = true

@onready var health: Health = $Health
@onready var visuals: Node2D = $Visuals
@onready var flash: ColorRect = $Visuals/Flash
@onready var bar: Node2D = $HealthBar
@onready var bar_fill: ColorRect = $HealthBar/Fill

var state: int = State.PATROL
var throws_started: int = 0
var hits_taken: int = 0

var _frame := 0
var _home_x := 0.0
var _facing := 1
var _cooldown := 0
var _turn_cooldown := 0
var _hitstop := 0
var _revive_t := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 1200.0)
var _recoil := 0.0
var _recoil_v := 0.0
var _flash := 0.0
var _alpha := 1.0
var _target_alpha := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if data == null:
		data = load("res://data/enemies/spearman.tres") as EnemyData
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

	if global_position.y > FALL_KILL_Y:
		global_position = Vector2(_home_x, -40.0)
		velocity = Vector2.ZERO
		health.heal_full()
		_enter(State.PATROL)
		return

	if not ai_enabled:
		velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
		move_and_slide()
		_update_recoil(delta)
		return

	_frame += 1
	match state:
		State.PATROL:
			_patrol()
		State.AIM:
			_aim()
		State.HURT:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			if _frame >= data.hurt_stun_frames:
				_enter(State.PATROL)
		State.DEAD:
			velocity.x = 0.0

	move_and_slide()
	_update_recoil(delta)


func _player() -> Node2D:
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null:
		var h := p.get_node_or_null("Health") as Health
		if h != null and h.is_dead:
			return null
	return p


func _patrol() -> void:
	var player := _player()
	# 冷却没好不许进瞄准 —— 不设防的话扔完下一帧又 AIM，
	# 实际射速 = 蓄力 30 帧（0.5 秒一支矛），冷却字段完全失效（用户实测「射速快」）
	if player != null and _dist(player) <= data.aggro_range and _cooldown <= 0:
		_enter(State.AIM)
		return
	var lo := _home_x - data.patrol_range * 0.5
	var hi := _home_x + data.patrol_range * 0.5
	if _turn_cooldown <= 0 and (is_on_wall() or global_position.x <= lo or global_position.x >= hi):
		_facing = -_facing
		_turn_cooldown = 20
	velocity.x = data.patrol_speed * float(_facing)
	_apply_facing()


func _aim() -> void:
	var player := _player()
	if player == null or _dist(player) > data.deaggro_range:
		_enter(State.PATROL)
		return
	_facing = -1 if player.global_position.x < global_position.x else 1
	_apply_facing()
	velocity.x = 0.0
	# 蓄力：瞄准期间身体微微后仰 —— 和 walker 的前摇是同一套视觉语言
	visuals.position.x = _recoil - 3.0 * float(_facing) * clampf(float(_frame) / float(AIM_FRAMES), 0.0, 1.0)

	if _frame >= AIM_FRAMES:
		_throw(player)
		_cooldown = data.attack_cooldown_frames
		_enter(State.PATROL)


func _throw(player: Node2D) -> void:
	if data.projectile_speed <= 0.0:
		return
	throws_started += 1
	var proj: Node2D = PROJECTILE.instantiate()
	var dir := Vector2(signf(player.global_position.x - global_position.x), 0.0)
	get_tree().current_scene.add_child(proj)
	proj.setup(
		global_position + Vector2(14.0 * float(_facing), -6.0),
		dir, data.projectile_speed, data.projectile_damage, data.projectile_life, self)


func _enter(s: int) -> void:
	state = s
	_frame = 0
	_apply_facing()


func _dist(player: Node2D) -> float:
	return absf(player.global_position.x - global_position.x)


func _apply_facing() -> void:
	visuals.scale.x = 1.0 if _facing >= 0 else -1.0


func apply_hitstop(frames: int) -> void:
	_hitstop = maxi(_hitstop, frames)


func is_alive() -> bool:
	return not health.is_dead


func _on_damaged(amount: int, _hp_left: int, point: Vector2, heavy: bool, dir: int) -> void:
	hits_taken += 1
	_spawn_number(amount, point, heavy)
	var sign_dir := 1.0 if dir >= 0 else -1.0
	_recoil_v += RECOIL_KICK * sign_dir * (1.6 if heavy else 1.0)
	_flash = maxf(_flash, 1.0 if heavy else 0.75)
	_refresh_bar()
	if ai_enabled and not health.is_dead:
		_enter(State.HURT)


func _on_died() -> void:
	_enter(State.DEAD)
	_drop_shards()
	PlayerState.add_exp(data.exp_reward)   # 击杀经验进玩家成长
	_revive_t = data.revive_delay
	_target_alpha = 0.0
	set_collision_layer_value(2, false)
	bar.visible = false


## 死亡掉落精铁碎片（与 walker 同一契约）
func _drop_shards() -> void:
	var host := get_tree().current_scene
	if host == null or data.drop_shards <= 0:
		return
	for i in data.drop_shards:
		var p: Node2D = PICKUP.instantiate()
		host.add_child(p)
		p.global_position = global_position + Vector2(
			_rng.randf_range(-24.0, 24.0), _rng.randf_range(-16.0, 4.0))


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
