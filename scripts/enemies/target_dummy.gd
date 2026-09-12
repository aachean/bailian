extends CharacterBody2D
## 训练靶子。站着不动、不还手、会掉血，打死了满血重生。
##
## 为什么它是个 CharacterBody2D 而不是 StaticBody2D：
## M2 的小怪会用同一套骨架，到时候只需要换掉「不还手」这一段。
## 现在用静态刚体，那时候要重写一遍结构和碰撞层，等于白做。

const DAMAGE_NUMBER := preload("res://scenes/ui/damage_number.tscn")

## 后仰是一个欠阻尼弹簧：受击给一个初速度，然后自己荡回来（会轻微过冲）。
## 比「线性退回原位」贵不了几行，但挨打看起来是「弹」的而不是「推」的。
const RECOIL_STIFF := 1500.0
const RECOIL_DAMP := 30.0
## 后仰初速度。峰值位移 ≈ 0.0164 × 这个值 → 约 7 px，重击翻倍
const RECOIL_KICK := 420.0
const RECOIL_KICK_HEAVY := 1.6

@export_group("数值")
@export var max_hp: int = 120
## 被打死之后过多久满血重生。<= 0 表示不重生
@export var revive_delay: float = 1.3

@onready var health: Health = $Health
@onready var visuals: Node2D = $Visuals
@onready var flash: ColorRect = $Visuals/Flash
@onready var bar: Node2D = $HealthBar
@onready var bar_fill: ColorRect = $HealthBar/Fill

## 供自动验收读取
var hits_taken: int = 0
var total_damage_taken: int = 0

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 1200.0)
var _hitstop: int = 0
var _recoil: float = 0.0
var _recoil_v: float = 0.0
var _flash: float = 0.0
var _alpha: float = 1.0
var _target_alpha: float = 1.0
var _revive_t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	health.max_hp = max_hp
	health.hp = max_hp
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.revived.connect(_on_revived)
	_refresh_bar()


func _physics_process(delta: float) -> void:
	if _hitstop > 0:
		_hitstop -= 1
		return                      # 顿帧：位置、速度、后仰全部冻住

	velocity.y += _gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
	move_and_slide()

	_recoil_v += (-_recoil * RECOIL_STIFF - _recoil_v * RECOIL_DAMP) * delta
	_recoil += _recoil_v * delta
	visuals.position.x = _recoil


func _process(delta: float) -> void:
	# 闪白和淡入淡出走 process 帧，不跟物理顿帧绑在一起 ——
	# 顿帧的 0.1 秒里画面看起来是定格的，但白色高光应该继续退下去
	_flash = move_toward(_flash, 0.0, 7.0 * delta)
	flash.modulate.a = _flash

	if not is_equal_approx(_alpha, _target_alpha):
		_alpha = move_toward(_alpha, _target_alpha, 5.5 * delta)
		modulate.a = _alpha

	if _revive_t > 0.0:
		_revive_t -= delta
		if _revive_t <= 0.0:
			health.heal_full()


## 被命中时由攻击方调用。冻住自己，让打击「定」一下
func apply_hitstop(frames: int) -> void:
	_hitstop = maxi(_hitstop, frames)


func is_alive() -> bool:
	return not health.is_dead


func _on_damaged(amount: int, _hp_left: int, point: Vector2, heavy: bool, dir: int) -> void:
	hits_taken += 1
	total_damage_taken += amount
	_spawn_number(amount, point, heavy)
	var sign_dir := 1.0 if dir >= 0 else -1.0
	_recoil_v += RECOIL_KICK * sign_dir * (RECOIL_KICK_HEAVY if heavy else 1.0)
	_flash = maxf(_flash, 1.0 if heavy else 0.75)
	_refresh_bar()


func _spawn_number(amount: int, point: Vector2, heavy: bool) -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var dn := DAMAGE_NUMBER.instantiate() as Label
	host.add_child(dn)
	# Label 是 80×24 的框，往左上挪半个框才是「以命中点为中心」
	dn.position = point + Vector2(_rng.randf_range(-8.0, 8.0) - 40.0, -12.0)
	dn.setup(amount, heavy)


func _on_died() -> void:
	_revive_t = revive_delay
	_target_alpha = 0.0
	set_collision_layer_value(2, false)     # 关掉 enemy 层，死了就打不着了
	bar.visible = false


func _on_revived() -> void:
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


func _refresh_bar() -> void:
	bar_fill.scale.x = clampf(health.ratio(), 0.0, 1.0)
