extends CharacterBody2D
## 《百炼》玩家角色 —— M1 的第一步：只做「移动 + 跳跃 + 朝向」，不含战斗。
##
## 设计原则（整个项目都遵守）：
##   1. 所有可调数值放在 @export 里，在检查器里直接改、立刻看效果，不要改代码重跑。
##   2. 脚本里不出现"魔法数字"。数值来自 @export 或 ProjectSettings。
##   3. 手感优先。土狼时间(coyote time)和跳跃缓冲(jump buffer)是这类游戏手感的地基，
##      它们不是"多余功能"，是必需品。

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

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 1200.0)
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0

## 面朝方向：1 = 右，-1 = 左。它是一份"状态"，不是每帧算出来的临时值
var _facing: int = 1

@onready var _visuals: Node2D = $Visuals


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_update_jump(delta)
	_update_horizontal(delta)
	_update_facing()
	move_and_slide()


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


# ═══════════════════════════════════════════════════════════════════
# 你的任务：审查，不是重写
#
# 分工约定已调整为「AI 写代码，你审查并修正」。审查不等于扫一眼说"挺好"，
# 要对下面三个问题给出答案。答不上来就说明这段代码还不属于你 —— 那就来问我。
#
# Q1（读代码）为什么这里要先存一个 _facing 成员变量，
#    而不是每次直接写 _visuals.scale.x = signf(velocity.x)？
#    提示：想想 velocity.x 正好等于 0 的那一刻，signf(0) 会返回什么，
#    以及角色停下时会发生什么。
#
# Q2（动手调）把 max_speed、jump_velocity、fall_gravity_scale 各改一次，
#    每改一次跑一遍 test_room，用一句话说清"手感变好还是变坏，为什么"。
#    这三个数值没有标准答案，你需要形成自己的判断 —— 这是策划能力的起点。
#
# Q3（判断设计）为什么翻转的是 Visuals 这个空节点，
#    而不是分别去改 Body 和 Face 的 offset？
#    提示：想想 M3 要换成真正的美术资源（Sprite2D / AnimatedSprite2D）时，
#    哪种写法不用动代码。
#
# 三个答案写进 commit message。想不清楚的直接问，别装懂。
# ═══════════════════════════════════════════════════════════════════
