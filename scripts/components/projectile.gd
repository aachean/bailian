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
## 打谁（碰撞层位掩码）。敌方投射物（掷矛）打 player=1，玩家的剑气打 enemy=2
var target_mask: int = 1
## 伤害倍率。玩家发射的剑气用它带上装备加成 —— 与 Hitbox.damage_scale 同一个意思：
## 加成属于「这个人」，不属于「这一招」
var damage_scale: float = 1.0
## 命中反馈三件套（M4 打击感）：顿帧、火花、屏震。
## 由发射方从 SkillData 抄进来 —— 敌方的矛不设（默认 0），命中只有掉血，
## 玩家听到的受击声与红色火花由玩家自己的 _on_damaged 负责，两头不重样
var hitstop_frames: int = 0
var heavy: bool = false
var shake_gain: float = 0.0
const HIT_FX := preload("res://scenes/components/hit_fx.tscn")

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
	params.collision_mask = target_mask
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
		var dmg := int(round(float(damage) * damage_scale))
		# 命中反馈：声、火花、双方顿帧、屏震 —— 与近战 _on_hit_landed 同一套语言。
		# 弓箭打人不该是哑的（这正是远程角色要复用的管线）
		Audio.play(&"hit")
		var fx: Node2D = HIT_FX.instantiate()
		fx.setup(Color(1.0, 0.62, 0.25) if heavy else Color(1.0, 0.9, 0.5),
				16 if heavy else 10, 190.0 if heavy else 140.0)
		get_tree().current_scene.add_child(fx)
		fx.global_position = point
		if body.has_method("apply_hitstop"):
			body.call("apply_hitstop", hitstop_frames)
		if hitstop_frames > 0 and is_instance_valid(source) and source.has_method("apply_hitstop"):
			source.call("apply_hitstop", hitstop_frames)
		if shake_gain > 0.0 and is_instance_valid(source) and source.has_method("add_shake"):
			source.call("add_shake", shake_gain)
		h.take_damage(dmg, point, false, dir)
		_hit_done = true
		queue_free()
		return


func _in_bounds() -> bool:
	# 出了合理范围就消散，别在天上飞一辈子。范围随 life 限制其实已够，这是双保险
	return global_position.y < 2000.0
