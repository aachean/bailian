class_name Hitbox
extends Node2D
## 攻击判定框。挂在攻击方下面，形状和位置由技能数据驱动，只在判定帧内工作。
##
## ── 为什么不用 Area2D 的 body_entered 信号 ──────────────────────
## Area2D 的重叠列表要等到【下一个物理帧】才更新。如果开判定的那一帧对方已经站在
## 范围里（挥砍几乎总是这样），body_entered 根本不会触发，等于第一帧白给。
## 判定只有 4 帧，丢一帧就是 25%，而且丢不丢取决于对方站的位置 —— 这种不确定性
## 会让「第几帧命中」永远无法复现。
##
## 这里改成每帧自己做 shape query，命中时机精确到帧，断言可复现。
##
## ── 一次挥砍只结算一次 ─────────────────────────────────────────
## activate() 会清空命中记录。判定持续的 4 帧里，同一个目标只会被结算第一次。

signal hit_landed(target: Node2D, damage: int, point: Vector2, heavy: bool)

## 打谁（碰撞层位掩码）。玩家的判定框打 enemy 层 = 2
@export_flags_2d_physics var target_mask: int = 2
## 是否画出判定框。调手感时开，正常关
@export var debug_draw: bool = false

var _active: bool = false
var _source: Node2D = null
var _skill: SkillData = null
var _facing: int = 1
var _hit: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_physics_process(false)


## 开启判定。facing 用来把判定框的 x 偏移按朝向镜像
func activate(skill: SkillData, source: Node2D, facing: int) -> void:
	if skill == null:
		return
	if _skill != skill or not _active:
		_hit.clear()
	_skill = skill
	_source = source
	_facing = 1 if facing >= 0 else -1
	_active = true
	set_physics_process(true)
	queue_redraw()


func deactivate() -> void:
	if not _active:
		return
	_active = false
	_hit.clear()
	_skill = null
	set_physics_process(false)
	queue_redraw()


func is_active() -> bool:
	return _active


func _physics_process(_delta: float) -> void:
	if not _active or _skill == null:
		return

	var shape := RectangleShape2D.new()
	shape.size = _skill.hitbox_size

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, global_position + _offset())
	params.collision_mask = target_mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	if _source is CollisionObject2D:
		params.exclude = [(_source as CollisionObject2D).get_rid()]

	var space := get_world_2d().direct_space_state
	for hit: Dictionary in space.intersect_shape(params, 16):
		var body := hit.get("collider") as Node2D
		if body == null or _hit.has(body):
			continue
		_hit.append(body)
		_resolve(body)


func rect() -> Rect2:
	if _skill == null:
		return Rect2()
	var c := global_position + _offset()
	return Rect2(c - _skill.hitbox_size * 0.5, _skill.hitbox_size)


func _offset() -> Vector2:
	return Vector2(_skill.hitbox_offset.x * float(_facing), _skill.hitbox_offset.y)


func _resolve(body: Node2D) -> void:
	var h := body.get_node_or_null("Health") as Health
	var point := body.global_position + Vector2(0.0, -12.0)
	var dmg := _skill.roll_damage(_rng)

	# 被击退的方向：从攻击方指向目标
	var dir := 1
	if _source != null:
		dir = 1 if body.global_position.x >= _source.global_position.x else -1

	if h != null:
		var dealt := h.take_damage(dmg, point, _skill.heavy, dir)
		if dealt <= 0:
			return                      # 没打动（无敌 / 已死），不产生任何反馈
		dmg = dealt

	hit_landed.emit(body, dmg, point, _skill.heavy)


## 画判定框。只在 debug_draw 打开时有开销
func _draw() -> void:
	if not debug_draw or not _active or _skill == null:
		return
	var r := _skill.hitbox_size
	var c := _offset()
	draw_rect(Rect2(c - r * 0.5, r), Color(1.0, 0.35, 0.3, 0.28), true)
	draw_rect(Rect2(c - r * 0.5, r), Color(1.0, 0.4, 0.35, 0.85), false, 1.0)
