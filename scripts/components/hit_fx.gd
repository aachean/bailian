extends Node2D
## 命中特效：一次性粒子爆点，放完自己消失。
##
## ── 为什么是程序化色块 ────────────────────────────────────────
## 整个项目还活在色块美学里（M4 才接美术）；几颗飞溅的小方块配对颜色，
## 比引一整套贴图管线便宜得多，也和伤害数字、装备图标是同一种语言。
##
## ── 为什么手推计时不用 Tween / Timer ─────────────────────────
## 与 damage_number 同一条理由：无头自动验收按物理帧数断言，
## Tween / SceneTreeTimer 的推进时机和物理帧对不齐，「特效还在不在」会飘。
## _process 手动累加，消失的那个帧号是确定的。

## 默认寿命（秒）。粒子本身 one_shot，这之后连节点一起回收
const DEFAULT_LIFE := 0.38
## 粒子比默认 1px 大多少 —— 太小在 640×360 里根本看不见
const PARTICLE_SCALE := 3.0

var _color := Color(1, 0.9, 0.5)
var _count := 10
var _speed := 140.0
var _life := DEFAULT_LIFE
var _configured := false

var _t := 0.0

@onready var _p: CPUParticles2D = $P


## **必须在 add_child 之前调** —— 参数在 _ready 里一次性灌进粒子
func setup(color: Color, count: int, speed: float, life: float = DEFAULT_LIFE) -> void:
	_color = color
	_count = count
	_speed = speed
	_life = life
	_configured = true


func _ready() -> void:
	_p.one_shot = true
	_p.explosiveness = 1.0
	_p.amount = _count
	_p.lifetime = _life
	_p.direction = Vector2.ZERO
	_p.spread = 180.0
	_p.gravity = Vector2(0, 260)          # 火花往下坠一点，比纯放射活
	_p.initial_velocity_min = _speed * 0.4
	_p.initial_velocity_max = _speed
	_p.scale_amount_min = PARTICLE_SCALE * 0.6
	_p.scale_amount_max = PARTICLE_SCALE
	_p.color = _color
	_p.emitting = true
	if not _configured:
		push_warning("HitFx: add_child 前没调 setup —— 用了默认金色小爆点")


func _process(delta: float) -> void:
	_t += delta
	# 粒子放完再留一小会儿，连节点一起回收（一次性场景，不留垃圾）
	if _t >= _life + 0.2:
		queue_free()
