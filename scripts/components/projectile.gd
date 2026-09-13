extends Node2D
## 敌方投射物（掷矛手的矛）。直线飞、命中玩家结算一次、超时消散。
##
## 为什么不用 Area2D 的 body_entered：和 Hitbox 同一个理由 ——
## 重叠列表晚一帧更新，飞快的矛会穿过玩家第一帧白给。
## 这里每帧移动 + shape query，命中精确到帧，断言可复现。
##
## 不复用 Hitbox：Hitbox 是「挂在攻击方身上的判定区」，矛是独立飞行的实体，
## 生命周期（超时、出界、命中即亡）完全不同，硬套只会两头别扭。

const RADIUS := 5.0

var velocity := Vector2.ZERO
var damage := 5
var life := 1.6
var source: Node2D = null        # 投掷者（命中判定时排除它自己）

var _hit_done := false


func setup(from: Vector2, dir: Vector2, speed: float, dmg: int, life_sec: float, src: Node2D) -> void:
	global_position = from
	velocity = dir.normalized() * speed
	damage = dmg
	life = life_sec
	source = src


func _physics_process(delta: float) -> void:
	if _hit_done:
		return
	global_position += velocity * delta
	life -= delta
	if life <= 0.0 or not _in_bounds():
		queue_free()
		return

	var params := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	params.shape = shape
	params.transform = Transform2D(0.0, global_position)
	params.collision_mask = 1                 # player 层
	params.collide_with_bodies = true
	params.collide_with_areas = false
	if is_instance_valid(source) and source is CollisionObject2D:
		params.exclude = [(source as CollisionObject2D).get_rid()]

	var space := get_world_2d().direct_space_state
	for hit: Dictionary in space.intersect_shape(params, 4):
		var body := hit.get("collider") as Node2D
		if body == null:
			continue
		var h := body.get_node_or_null("Health") as Health
		if h == null:
			continue
		var point := global_position
		var dir := 1 if velocity.x >= 0.0 else -1
		h.take_damage(damage, point, false, dir)
		_hit_done = true
		queue_free()
		return


func _in_bounds() -> bool:
	# 出了合理范围就消散，别在天上飞一辈子。范围随 life 限制其实已够，这是双保险
	return global_position.y < 2000.0
