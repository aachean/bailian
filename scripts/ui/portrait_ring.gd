class_name PortraitRing
extends Control
## 圆形角色头像 + 环形经验条 —— 取代原来贴着屏幕最底边的全屏经验条。
##
## ── 为什么把经验条做成环 ──────────────────────────────────────
## 全屏细条钉在屏幕最底边，正好落在视野边缘：玩家得把视线挪到角落才读得到进度，
## 而战斗里没人会那么做。改成围着角色头像的环之后，头像本来就在左上角这块
## 眼球常驻区，顺带把经验读了。省下来的一整条底部空间还给场景。
##
## ── 左上角那个人必须和屏幕中央那个人长得一样 ─────────────────
## 头像的配色直接取自 player.tscn 的 Visuals（红橙身体 + 白脸 + 斗笠），
## 不是随便找张图。头像和角色不像，玩家会当成两个东西。
##
## ── 不用贴图的理由 ────────────────────────────────────────────
## 与 ItemIcon / SkillIcon 同一套思路：项目现在整体是色块，一张 60×60 的图
## 不值得开贴图管线；环形经验还得随进度实时改角度，矢量画最省事。

const DESIGN := 60.0

## 经验弧：黄绿，与旧底部经验条**同色** —— 换了位置不该换含义
const EXP_COLOR := Color(0.62, 0.8, 0.35)
const EXP_BG := Color(0.16, 0.15, 0.2)
## 环外描边：暗金，与 HUD 其他面板边框同色
const RIM_COLOR := Color(0.47, 0.4, 0.26)
## 内圆底：与技能格底色同色
const DISC_COLOR := Color(0.11, 0.11, 0.14, 0.94)
## 角色配色，取自 player.tscn
const BODY_COLOR := Color(0.847, 0.353, 0.188)
const FACE_COLOR := Color(0.98, 0.98, 0.95)
const HAT_COLOR := Color(0.36, 0.27, 0.18)
const EYE_COLOR := Color(0.12, 0.12, 0.15)

## 经验进度 0..1
var _ratio := 0.0

## 立绘头像（ADR-0015）：非空时画方形照片（内接内圆），空则维持程序化小人。
## 弓手还没立绘 —— 这就是那条兜底
var face_texture: Texture2D = null


func set_face_texture(t: Texture2D) -> void:
	if t == face_texture:
		return
	face_texture = t
	queue_redraw()


## 设置经验进度。值没变就不重画 —— 每帧轮询调用，不做这个判断会白白重绘
func set_exp(v: float) -> void:
	var r := clampf(v, 0.0, 1.0)
	if absf(r - _ratio) < 0.0015:
		return
	_ratio = r
	queue_redraw()


func exp_ratio() -> float:
	return _ratio


func _draw() -> void:
	var k := minf(size.x, size.y) / DESIGN
	if k <= 0.0:
		return
	var c := Vector2(30.0, 30.0) * k
	var ring_r := 26.0 * k
	var ring_w := maxf(2.0, 4.0 * k)

	# 底环 → 进度弧（从正上方顺时针长出去，和钟表一个方向）
	draw_arc(c, ring_r, 0.0, TAU, 48, EXP_BG, ring_w, true)
	if _ratio > 0.0:
		var a0 := -PI * 0.5
		draw_arc(c, ring_r, a0, a0 + TAU * _ratio, 48, EXP_COLOR, ring_w, true)
	# 外描边压在最外圈
	draw_arc(c, ring_r + ring_w * 0.5, 0.0, TAU, 48, RIM_COLOR, maxf(1.0, 1.0 * k), true)
	# 内圆底再画头像，头像压着圆底
	draw_circle(c, 23.0 * k, DISC_COLOR)
	if face_texture != null:
		# 照片取内接正方形：边长 31（角距中心 ≈21.9 < 内圆半径 23，不出方角）
		var side := 31.0 * k
		draw_texture_rect(face_texture,
			Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
	else:
		_draw_person(k)


## 头像：斗笠 + 头 + 肩。
## 每个形状都算过到中心的距离，全部落在内圆半径 23 以内 ——
## Control 没有圆形裁剪，超出去的像素会画成方的，外圈会出现方角。
## 改这里的坐标必须重新算一遍这个距离。
##
## ── 两个画错过的版本，别再走回去 ─────────────────────────────
## 1. 脸画成**方形**：方脸 + 三角斗笠 + 梯形肩，三个直边图形摞起来
##    读出来的是「一栋带屋顶的房子」，不是一个人。
## 2. 脸画成 9×15 的**窄长方**：比例失真，看着像插在肩膀上的一根白瓶子，
##    眼睛小到像两个洞。
## 定稿是圆头：圆是这个尺寸下唯一能一眼读成「人头」的形状。
func _draw_person(k: float) -> void:
	# 肩 / 身体（红橙）—— 最远角 (19,49)、(41,49) 距中心 21.9
	draw_colored_polygon(_poly([
		Vector2(19, 49), Vector2(24, 36), Vector2(36, 36), Vector2(41, 49),
	], k), BODY_COLOR)
	# 头（圆）—— 最远点 (30,17)/(21,26) 距中心 13 / 9.8
	draw_circle(Vector2(30, 26) * k, 9.0 * k, FACE_COLOR)
	# 眼（深）：画在斗笠下缘（y=25）露出来的那半张脸上
	draw_rect(_rect(25.5, 26, 28, 29, k), EYE_COLOR)
	draw_rect(_rect(32, 26, 34.5, 29, k), EYE_COLOR)
	# 斗笠：底边压在额头上，只露出眼以下 —— 最远角 (15,25) 距中心 15.8
	draw_colored_polygon(_poly([
		Vector2(30, 9), Vector2(45, 25), Vector2(15, 25),
	], k), HAT_COLOR)
	# 受光的一条窄亮边，避免糊成一团死色（画宽了斗笠会变成一棵树）
	draw_colored_polygon(_poly([
		Vector2(30, 9), Vector2(44, 25), Vector2(41, 25), Vector2(30, 14),
	], k), HAT_COLOR.lightened(0.28))


func _poly(pts: Array, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.x, p.y) * k)
	return out


func _rect(x0: float, y0: float, x1: float, y1: float, k: float) -> Rect2:
	return Rect2(Vector2(x0, y0) * k, Vector2(x1 - x0, y1 - y0) * k)
