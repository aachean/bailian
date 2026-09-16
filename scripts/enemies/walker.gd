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
const PICKUP := preload("res://scenes/components/pickup.tscn")
const HIT_FX := preload("res://scenes/components/hit_fx.tscn")

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
@onready var swipe: ColorRect = $Visuals/Swipe
@onready var bar: Node2D = $HealthBar
@onready var bar_fill: ColorRect = $HealthBar/Fill
@onready var _hitbox: Hitbox = $Hitbox

## 精灵模式下的贴图节点（_setup_skin 建；空 sprite_path 时保持 null）
var _skin: Sprite2D = null
var _skin_walk: Array = []
var _skin_frame_clock := 0.0

## 掉到这条线以下就是掉出世界，走各自的善后流程。
## 场景高 360，地面在 320 附近 —— 800 已经是「肯定出世界」的深度
const FALL_KILL_Y := 800.0

## 供自动验收读取
var state: int = State.PATROL
var attacks_started: int = 0
var hits_taken: int = 0

var _frame := 0                 # 当前状态内经过的物理帧
var _home_x := 0.0              # 出生点（巡逻围绕它）
var _facing := 1
var _cooldown := 0
var _turn_cooldown := 0         # 巡逻折返后的方向锁定帧数
var _stuck := 0                 # 追击卡住的连续帧数（贴墙/卡缝兜底）
var _stuck_x := 0.0
var _attack_pose := 0.0         # 攻击姿势偏移（前缩/后缩），叠加在后仰弹簧上
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
## 休眠中（这一波还没轮到它出场）。见 set_dormant
var _dormant := false
## 场景里声明的碰撞层 / 掩码。休眠会把它们清零，醒过来要还原成这两个
var _base_layer := 0
var _base_mask := 0


func _ready() -> void:
	_rng.randomize()
	_base_layer = collision_layer
	_base_mask = collision_mask
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
	_setup_skin()


## 精灵模式（ADR-0015）：data.sprite_path 非空时色块退位。
## 素材面朝左，而 visuals.scale.x 的 +1 是朝右 —— 给 skin 恒定 -1，
## 两个镜像相互抵消：怪朝右时正好露出素材的右向。精英变体没配图，维持色块
func _setup_skin() -> void:
	if not data.sprite_dir.is_empty():
		_setup_skin_frames()
		return
	if data.sprite_path.is_empty():
		return
	_skin = Sprite2D.new()
	_skin.name = "Skin"
	visuals.add_child(_skin)
	visuals.move_child(_skin, 0)
	for n in ["Body", "Head", "Eye", "Flash", "Swipe"]:
		var n2 := visuals.get_node_or_null(n)
		if n2 != null:
			n2.visible = false
	_skin.texture = load(data.sprite_path)
	# 高清手绘帧用线性 + mipmap（项目默认最近邻会把缩小采样成糊块）
	_skin.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tex_h := float(_skin.texture.get_height())
	var s := 52.0 / tex_h          # 小怪比玩家（64）矮一头
	_skin.scale = Vector2(-s, s)
	_skin.position = Vector2(0.0, 20.0 - 52.0 * 0.5)   # 底边对齐旧色块脚底（+20）


## 帧序列模式（sprite_dir）：walk_N 循环 + idle/hurt/dead 单帧。
## 32px 原生 ×2 整数缩放，nearest。
func _setup_skin_frames() -> void:
	_skin = Sprite2D.new()
	_skin.name = "Skin"
	visuals.add_child(_skin)
	visuals.move_child(_skin, 0)
	for n in ["Body", "Head", "Eye", "Flash", "Swipe"]:
		var n2 := visuals.get_node_or_null(n)
		if n2 != null:
			n2.visible = false
	_skin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_skin.scale = Vector2(-1.5, 1.5)   # x -1：素材面朝左，抵消 _apply_facing 的翻转；帧 32x64
	_skin.position = Vector2(0.0, -2.0 - 64.0 * 1.5 * 0.5)   # 帧底 -2：与骑士视觉脚位平齐（帧 32x64，脚贴帧底）
	# 帧序列模式下小人实际头顶在 -44（帧上半是空白），血条贴头顶上方一点
	bar.position.y = -54.0
	_skin.visible = true
	var d := DirAccess.open(data.sprite_dir)
	if d == null:
		return
	var walk: Array = []
	for f in d.get_files():
		if f.begins_with("walk_") and f.ends_with(".png"):
			walk.append([int(f.trim_prefix("walk_").trim_suffix(".png")), f])
	walk.sort_custom(func(a, b): return a[0] < b[0])
	_skin_walk = []
	for e in walk:
		_skin_walk.append(load(data.sprite_dir + "/" + str(e[1])))
	var idle_path := data.sprite_dir + "/idle_0.png"
	if ResourceLoader.exists(idle_path):
		_skin.texture = load(idle_path)


func _physics_process(delta: float) -> void:
	if _hitstop > 0:
		_hitstop -= 1
		return

	if _cooldown > 0:
		_cooldown -= 1
	if _turn_cooldown > 0:
		_turn_cooldown -= 1

	velocity.y += _gravity * delta

	# 掉出世界（追玩家追下悬崖 / 地图边缘）：回到出生点上空落下来，满血，回巡逻。
	# 跟玩家不同 —— 玩家掉出去算死亡，它只是个会重置的木桩加威胁。
	if global_position.y > FALL_KILL_Y:
		global_position = Vector2(_home_x, -40.0)
		velocity = Vector2.ZERO
		health.heal_full()
		_enter(State.PATROL)
		return

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

	# 攻击距离内就站住 —— 哪怕冷却没好也站着等。
	# 继续全速顶着玩家走 = 一台推土机：把玩家一路拱到地图边缘掉出世界（实测翻过车）。
	if _dist(player) <= data.attack_range:
		_facing = -1 if player.global_position.x < global_position.x else 1
		velocity.x = 0.0
		_apply_facing()
		if _cooldown <= 0:
			_start_attack()
		return

	# 追击卡住兜底：贴墙、卡缝时位置不动，干瞪 45 帧就放弃这次追击回巡逻。
	# 玩家在高台上时它会在墙下站着等 —— 这是正确行为，玩家得自己下来。
	if absf(global_position.x - _stuck_x) < 0.5:
		_stuck += 1
		if _stuck > 45:
			_stuck = 0
			_enter(State.PATROL)
			return
	else:
		_stuck = 0
	_stuck_x = global_position.x

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
	# 攻击的视觉三拍：前摇蓄力后缩 → 判定帧刀光亮起 → 后摇熄灭。
	# 没有这三拍，贴脸的玩家只看到色块突然掉血（实测反馈：没有攻击动作）。
	if _skill == null:
		return
	var total := _skill.total_frames()
	if t < _skill.startup_frames:
		# 前摇：往后缩，告诉玩家「我要打了」
		_attack_pose = -3.0 * float(_facing) * _ease_in(t, _skill.startup_frames)
		swipe.modulate.a = 0.0
	elif _skill.is_active_at(t):
		_attack_pose = 4.0 * float(_facing)
		swipe.modulate.a = 0.9
	else:
		_attack_pose = 0.0
		swipe.modulate.a = maxf(0.9 * (1.0 - float(t - _skill.active_to()) / float(maxi(total - _skill.active_to(), 1))), 0.0)
	if t >= total:
		_hitbox.deactivate()
		_skill = null
		_cooldown = data.attack_cooldown_frames
		_enter(State.CHASE)


## 0→1 的缓入，前摇后缩用
func _ease_in(t: int, span: int) -> float:
	if span <= 1:
		return 1.0
	return clampf(float(t) / float(span - 1), 0.0, 1.0)


func _start_attack() -> void:
	_skill = data.attack_skill
	attacks_started += 1
	_enter(State.ATTACK)
	velocity.x = _skill.lunge_speed * float(_facing)


func _enter(s: int) -> void:
	# 离开攻击状态时必须关判定 —— 判定框是多留一帧都会多结算一次的东西
	if state == State.ATTACK and s != State.ATTACK:
		_hitbox.deactivate()
		_attack_pose = 0.0
		swipe.modulate.a = 0.0
	state = s
	_frame = 0
	_apply_facing()


func _dist(player: Node2D) -> float:
	return absf(player.global_position.x - global_position.x)


## 帧推进：死亡 KO 静帧 → 受击帧（闪白期）→ walk 循环
func _tick_skin_frames(delta: float) -> void:
	if state == State.DEAD:
		var d0 := data.sprite_dir + "/dead_0.png"
		if ResourceLoader.exists(d0):
			_skin.texture = load(d0)
		return
	var h0 := data.sprite_dir + "/hurt_0.png"
	if _flash > 0.2 and ResourceLoader.exists(h0):
		_skin.texture = load(h0)
		return
	if _skin_walk.is_empty():
		return
	_skin_frame_clock += delta * 10.0
	_skin.texture = _skin_walk[int(_skin_frame_clock) % _skin_walk.size()]


func _apply_facing() -> void:
	visuals.scale.x = 1.0 if _facing >= 0 else -1.0


# ── 受击 / 死亡 / 重生（与靶子同一套表现）──────────────────────

func apply_hitstop(frames: int) -> void:
	_hitstop = maxi(_hitstop, frames)


func is_alive() -> bool:
	return not health.is_dead


## 休眠中？清屏判定要跳过它（它都没出场，不该算这一屏的怪）
func is_dormant() -> bool:
	return _dormant


## 休眠 / 唤醒 —— **分批出怪**（波次）的地基。
##
## 还没轮到出场的那一波必须**从世界里完全退出去**。只 `hide()` 是不够的，
## 它会以三种方式泄漏，而且每一种都不报错：
##   1. **挡路** —— 看不见的身子还是堵在那儿，玩家撞上去会以为地图坏了
##   2. **挨打** —— 玩家的刀会砍到"空气"（判定框照样命中）
##   3. **让这一屏永远清不掉** —— 清屏判定数的是 `enemy` 组，留着它就永远有活怪
## 所以四件事一起做：看不见 / 不跑逻辑 / 不参与碰撞 / 退出 `enemy` 组。
func set_dormant(dormant: bool) -> void:
	if _dormant == dormant:
		return
	_dormant = dormant
	visible = not dormant
	process_mode = Node.PROCESS_MODE_DISABLED if dormant else Node.PROCESS_MODE_INHERIT
	for node in find_children("*", "CollisionShape2D", true, false):
		node.set_deferred("disabled", dormant)
	set_deferred("collision_layer", 0 if dormant else _base_layer)
	set_deferred("collision_mask", 0 if dormant else _base_mask)
	if dormant:
		remove_from_group("enemy")
	else:
		add_to_group("enemy")


## 读档恢复：摆回存档时的血量与位置。血空了就连死亡状态一起复现，
## 让它按原定重生计时安静地等复活 —— 世界该是离开那一刻的样子。
func apply_saved(d: Dictionary) -> void:
	global_position = Vector2(float(d.get("x", global_position.x)), float(d.get("y", global_position.y)))
	velocity = Vector2.ZERO
	_stuck = 0
	_enter(State.PATROL)
	var hp := int(d.get("hp", data.max_hp))
	if hp <= 0:
		health.hp = 0
		health.is_dead = true
		_dead_pose()          # 只摆尸，不掉落不给经验 —— 见 _dead_pose 的注释
	else:
		health.restore(hp)
		_refresh_bar()


## 死亡爆点 + 轻震（M4 打击感）：尸体位置撒一把碎屑，屏幕跟着轻晃一下。
## 死亡必须有存在感 —— 不然杀怪和杀空气分不开
func _death_burst() -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	var fx: Node2D = HIT_FX.instantiate()
	fx.setup(Color(0.62, 0.72, 0.85), 14, 120.0)
	host.add_child(fx)
	fx.global_position = global_position
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("add_shake"):
		pl.call("add_shake", 0.12)

func _on_died() -> void:
	_death_burst()
	_dead_pose()
	_drop_shards()
	_drop_gold()
	_drop_potions()
	_drop_item()
	PlayerState.add_exp(data.exp_reward)   # 击杀经验进玩家成长


## 死亡该有的样子：进死亡态、透明掉、关掉碰撞与血条、起重生计时。
##
## 与「掉落 + 给经验」**分成两半**是刻意的：读档复现一具尸体时只能走这一半。
## 走整个 _on_died 的话，每读一次档就重掉一次装备、重给一次经验 ——
## Boss 用 revive_delay = 0 永不重生，玩家反复读档就能无限刷它的掉落。
func _dead_pose() -> void:
	_enter(State.DEAD)
	_revive_t = data.revive_delay
	_target_alpha = 0.0
	set_collision_layer_value(2, false)
	bar.visible = false


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


## 死亡掉落精铁碎片。散在尸体周围，玩家走近自动吸附
func _drop_shards() -> void:
	var host := get_tree().current_scene
	if host == null or data.drop_shards <= 0:
		return
	for i in data.drop_shards:
		var p: Node2D = PICKUP.instantiate()
		host.add_child(p)
		p.global_position = global_position + Vector2(
			_rng.randf_range(-24.0, 24.0), _rng.randf_range(-16.0, 4.0))


## 死亡掉装备：按 EnemyData 的概率，从掉落池里随机抽一件扔在地上。
## item_path 必须在 add_child 【之前】设好 —— pickup 的 _ready 要拿它决定颜色
func _drop_item() -> void:
	var host := get_tree().current_scene
	if host == null or data.drop_items.is_empty():
		return
	if data.drop_item_chance < 1.0 and _rng.randf() > data.drop_item_chance:
		return
	var path: String = data.drop_items[_rng.randi_range(0, data.drop_items.size() - 1)]
	var p: Node2D = PICKUP.instantiate()
	p.set("item_path", path)
	host.add_child(p)
	p.global_position = global_position + Vector2(_rng.randf_range(-18.0, 18.0), -8.0)


## 死亡掉元宝：一笔（一个拾取物，值 data.drop_gold）。
## 元宝是商店的钱，与精铁两条管道（计划 §3.7）—— 别把它并进碎片循环里
func _drop_gold() -> void:
	var host := get_tree().current_scene
	if host == null or data.drop_gold <= 0:
		return
	var p: Node2D = PICKUP.instantiate()
	p.set("gold_amount", data.drop_gold)
	host.add_child(p)
	p.global_position = global_position + Vector2(
		_rng.randf_range(-20.0, 20.0), _rng.randf_range(-12.0, 2.0))


## 死亡按概率掉药（回血 / 回蓝各判一次）。药掉在地上走近直接生效 ——
## **满了玩家不收**，这扇门在 pickup 里（计划 §3.7），这里只管掉不掉
func _drop_potions() -> void:
	var host := get_tree().current_scene
	if host == null:
		return
	if data.drop_heal_chance > 0.0 and _rng.randf() <= data.drop_heal_chance:
		var hp: Node2D = PICKUP.instantiate()
		hp.set("potion", &"hp")
		host.add_child(hp)
		hp.global_position = global_position + Vector2(
			_rng.randf_range(-22.0, 22.0), _rng.randf_range(-12.0, 2.0))
	if data.drop_mana_chance > 0.0 and _rng.randf() <= data.drop_mana_chance:
		var mp: Node2D = PICKUP.instantiate()
		mp.set("potion", &"mp")
		host.add_child(mp)
		mp.global_position = global_position + Vector2(
			_rng.randf_range(-22.0, 22.0), _rng.randf_range(-12.0, 2.0))


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
	# 精灵模式下旧 Flash 色块已藏，受击闪白改走 self_modulate 提亮（>1 过饱和发白）
	if _skin != null:
		var f := minf(_flash, 1.0)
		_skin.self_modulate = Color(1.0 + f, 1.0 + f, 1.0 + f)
	if _skin_walk.size() > 0:
		_tick_skin_frames(delta)
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
	# 受击后仰（弹簧）与攻击姿势（前缩/后缩）叠在同一根视觉骨骼上
	visuals.position.x = _recoil + _attack_pose


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
