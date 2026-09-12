extends CharacterBody2D
## 《百炼》玩家角色 —— M1 的第一步：只做「移动 + 跳跃」，不含战斗。
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


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_update_jump(delta)
	_update_horizontal(delta)
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


# ═══════════════════════════════════════════════════════════════════
# 你的第一个练习 —— 本轮唯一的任务
#
# 现状：角色身上有两块方块，Body（橙色身体）和 Face（白色小方块，代表"脸"）。
#       现在不管往哪走，脸都固定在右边，很别扭。
#
# 目标：让"面朝方向"有视觉反馈。
#   1) 往左走时，Face 应出现在身体左侧；往右走时回到右侧。
#   2) 只用改 Face 这个子节点的位置（它的位置由 offset_left / offset_right 决定，
#      你现在拿到的是 Control 类型的 ColorRect）。
#   3) 判定依据是 velocity.x 的正负，注意还要处理"停下"的情况
#      —— 停下时应该保持上一次的朝向，而不是弹回默认方向。
#
# 提示（Godot 4 的 API）：
#   - 取子节点：$Face
#   - Control 的水平位置：position.x，或直接改 offset_left / offset_right
#   - 更省事的做法：给 Face 设一个基准位置，需要翻转时用 -abs() / abs()
#
# 做完之后：
#   1) 在游戏里左右跑一遍，确认脸跟着转
#   2) git add -A && git commit，message 写清楚你做了什么
#   3) 把这个注释块删掉，换成你的实现
# ═══════════════════════════════════════════════════════════════════
