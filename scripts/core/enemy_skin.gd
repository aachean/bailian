class_name EnemySkin
extends Sprite2D
## 敌人帧序列精灵（walker / spearman 两套怪共用的组件）。
##
## 之前帧序列逻辑直接写在 walker.gd 里，spearman 系要复用得整段抄一遍。
## 抽成组件后两边只调两个方法：`setup()` 装载、`tick()` 推进。
##
## ── 素材约定（assets/enemies/goblin/<变体>/）────────────────
##     idle_0.png            待机（1 帧）
##     walk_0..N.png         走路循环
##     hurt_0..N.png         受击
##     dead_0..N.png         倒地（KO）
## 帧 32 宽 × 64 高，**小人画在每帧下半**（sprite sheet 的通例：给头顶留空）。
##
## ── 像素纪律 ───────────────────────────────────────────────
## nearest 过滤 + 整数倍缩放。素材面朝左，`scale.x` 取负抵消所在容器的翻转
## （容器 `visuals.scale.x` 由朝向逻辑驱动）。

## 显示缩放（32x64 帧 × 1.5 ≈ 96px 高，比玩家略矮）
@export var px_scale := 1.5
## 脚底相对**怪原点**的 y。walker/spearman 的碰撞体是 28x40（中心在原点），
## 所以脚底在原点 +20 —— 帧底必须对齐到这里，否则怪悬空（飘在半空）。
## 这个值必须从碰撞体推出来，别凭手感调（凭手感调错过三次）。
@export var feet_y := 20.0

const FRAME_H := 64.0

var _walk: Array = []
var _clock := 0.0
var _hurt_tex: Texture2D = null
var _dead_tex: Texture2D = null
var _idle_tex: Texture2D = null


## 装载帧序列。sprite_dir 空或缺图时把自己隐藏（不崩，也不留半个身子）
func setup(sprite_dir: String) -> void:
	name = "Skin"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(-px_scale, px_scale)
	position = Vector2(0.0, feet_y - FRAME_H * px_scale * 0.5)
	var walk: Array = []
	for f in ResDir.files(sprite_dir):
		if f.begins_with("walk_") and f.ends_with(".png"):
			walk.append([int(f.trim_prefix("walk_").trim_suffix(".png")), f])
	if walk.is_empty():
		visible = false
		return
	walk.sort_custom(func(a, b): return a[0] < b[0])
	_walk = []
	for e in walk:
		_walk.append(load(sprite_dir + "/" + str(e[1])))
	_idle_tex = _maybe(sprite_dir + "/idle_0.png")
	_hurt_tex = _maybe(sprite_dir + "/hurt_0.png")
	_dead_tex = _maybe(sprite_dir + "/dead_0.png")
	texture = _idle_tex if _idle_tex != null else (_walk[0] if not _walk.is_empty() else null)
	visible = texture != null


func _maybe(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


## 每帧推进：死亡 KO 静帧 → 受击帧（闪白期）→ 走路循环。
## 死亡/受击优先，因为它们传达的是「现在能不能打它」这个比动作更好看的信息。
func tick(delta: float, dead: bool, flash: float) -> void:
	if not visible:
		return
	if dead and _dead_tex != null:
		texture = _dead_tex
		return
	if flash > 0.2 and _hurt_tex != null:
		texture = _hurt_tex
		return
	if _walk.is_empty():
		return
	_clock += delta * 10.0
	texture = _walk[int(_clock) % _walk.size()]
