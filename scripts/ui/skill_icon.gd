class_name SkillIcon
extends Control
## 技能图标：程序化自绘，**形状按技能 id、颜色按技能固定** —— 与 ItemIcon 同一套路。
##
## 为什么每个技能一个手画形状：技能之间靠「一眼认出来」区分，全靠颜色不够 ——
## 五个格子都是色块的话，玩家在紧张的战斗里根本分不清哪个是哪个。
##
## 颜色表写在这里而不是 SkillData 里：颜色是**表现**不是**数值**，
## 调色的时候改这一个文件就够，不用去动 7 个 .tres。

const DESIGN := 16.0

## 技能配色（按 id）。同一族的技能给相近的色：位移偏暖、防御偏冷
const COLORS := {
	&"whirl": Color(0.55, 0.82, 1.0),
	&"thrust": Color(1.0, 0.84, 0.45),
	&"ironwall": Color(0.68, 0.74, 0.86),
	&"sword_wave": Color(0.55, 0.95, 0.9),
	&"quake": Color(0.95, 0.6, 0.38),
	&"breathe": Color(0.55, 0.95, 0.6),
	&"upcut": Color(0.86, 0.68, 1.0),
}
const EMPTY_COLOR := Color(0.3, 0.29, 0.33)

var skill_id: StringName = &""
## 变暗（未解锁 / 蓝不够）—— 技能栏里「放不出来」要一眼看得出
var dim := false

var _skill: SkillData = null


func set_skill(sk: SkillData) -> void:
	_skill = sk
	skill_id = sk.id if sk != null else &""
	queue_redraw()


func skill() -> SkillData:
	return _skill


func _draw() -> void:
	var k := minf(size.x, size.y) / DESIGN
	if k <= 0.0:
		return
	if skill_id == &"":
		draw_rect(Rect2(Vector2(3, 3) * k, Vector2(10, 10) * k),
			EMPTY_COLOR, false, maxf(1.0, k))
		return
	var c: Color = COLORS.get(skill_id, Color(0.8, 0.8, 0.85))
	var hi := c.lightened(0.45)
	if dim:
		c = c.darkened(0.5)
		hi = hi.darkened(0.5)
	match skill_id:
		&"whirl":
			_draw_whirl(k, c, hi)
		&"thrust":
			_draw_thrust(k, c, hi)
		&"ironwall":
			_draw_ironwall(k, c, hi)
		&"sword_wave":
			_draw_wave(k, c, hi)
		&"quake":
			_draw_quake(k, c, hi)
		&"breathe":
			_draw_breathe(k, c, hi)
		&"upcut":
			_draw_upcut(k, c, hi)
		_:
			draw_colored_polygon(_poly([
				Vector2(8, 2), Vector2(14, 8), Vector2(8, 14), Vector2(2, 8),
			], k), c)


## 旋风：三片绕着中心转的剑光
func _draw_whirl(k: float, c: Color, hi: Color) -> void:
	for i in 3:
		var a := float(i) * TAU / 3.0
		var pts := PackedVector2Array()
		for p in [Vector2(8, 8), Vector2(8 + 6.0 * cos(a), 8 + 6.0 * sin(a))]:
			pts.append(p * k)
		draw_line(pts[0], pts[1], hi if i == 0 else c, maxf(1.6, 2.2 * k))
	draw_circle(Vector2(8, 8) * k, 1.8 * k, c)


## 突刺：一支向右的箭头（长条 + 头）
func _draw_thrust(k: float, c: Color, hi: Color) -> void:
	draw_rect(Rect2(Vector2(2, 7) * k, Vector2(8, 2.4) * k), c)
	draw_colored_polygon(_poly([
		Vector2(9, 3.5), Vector2(14.5, 8.2), Vector2(9, 12.9),
	], k), hi)


## 铁壁：一堵砖墙（上沿亮）
func _draw_ironwall(k: float, c: Color, hi: Color) -> void:
	draw_rect(_rect(2, 3, 14, 13, k), c)
	draw_rect(_rect(2, 3, 14, 5, k), hi)
	draw_rect(_rect(2, 7.5, 14, 8.8, k), hi.darkened(0.35))
	draw_rect(_rect(7.4, 5, 8.6, 13, k), hi.darkened(0.35))


## 剑气：三道向前推的弧
func _draw_wave(k: float, c: Color, hi: Color) -> void:
	for i in 3:
		var r := 3.0 + 2.4 * float(i)
		draw_arc(Vector2(4, 8) * k, r * k, -PI * 0.42, PI * 0.42,
			16, hi if i == 0 else c, maxf(1.4, 1.8 * k))


## 崩山：裂开的地面（倒三角 + 底横线）
func _draw_quake(k: float, c: Color, hi: Color) -> void:
	draw_colored_polygon(_poly([
		Vector2(8, 2), Vector2(14, 9.5), Vector2(2, 9.5),
	], k), c)
	draw_rect(_rect(1.5, 11, 14.5, 13.5, k), hi)


## 调息：一圈气 + 中心
func _draw_breathe(k: float, c: Color, hi: Color) -> void:
	draw_arc(Vector2(8, 8) * k, 5.6 * k, 0.0, TAU, 24, c, maxf(1.4, 2.0 * k))
	draw_circle(Vector2(8, 8) * k, 2.2 * k, hi)


## 上撩：向上的箭头
func _draw_upcut(k: float, c: Color, hi: Color) -> void:
	draw_rect(Rect2(Vector2(6.8, 6) * k, Vector2(2.4, 8) * k), c)
	draw_colored_polygon(_poly([
		Vector2(4, 6.5), Vector2(8, 1.5), Vector2(12, 6.5),
	], k), hi)


func _poly(pts: Array, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.x, p.y) * k)
	return out


func _rect(x0: float, y0: float, x1: float, y1: float, k: float) -> Rect2:
	return Rect2(Vector2(x0, y0) * k, Vector2(x1 - x0, y1 - y0) * k)
