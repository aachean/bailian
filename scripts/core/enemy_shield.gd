class_name EnemyShield
extends Node2D
## 相位的护罩（ADR-0019 的 B 口径、ADR-0023）：敌人进入「打不到」的那段时间时，
## 身上亮起一圈冷色的环。**它是相位唯一的视觉信号** —— 没有它，
## 玩家只会觉得「我明明砍中了却没伤害」，那是本项目最不能接受的一类失败。
##
## ── 为什么是代码建的，不摆进场景 ──────────────────────────────
## 13 个敌人场景（小怪 / 精英 / Boss）都要有这一圈。摆进场景 = 13 处 .tscn 改动，
## 漏一个就是「那只 Boss 的相位看不见」，而且测试抓不到（只能靠截图）。
## 与 `EnemySkin` / `NpcSkin` 同一条路：`EnemyShield.new()` 挂上去，
## **一处代码覆盖全部场景**。
##
## ── 为什么用 _draw 手画，不用贴图 ────────────────────────────
## 与 item_icon / portrait_ring 同一条理由：仓库整体是色块美学，
## 一圈椭圆环不值得开贴图管线。发光感靠「两层环 + 透明度脉冲」凑。
##
## ── 三拍（与 EnemyData 的相位三段一一对应）────────────────────
##   ① 架势：环**渐亮**（`_open` 0→1）—— 给玩家读的时间
##   ② 相位：环**满亮 + 呼吸脉冲** —— 「现在打不动」
##   ③ 恢复：`break_flash()` 白色碎闪一下然后收掉 —— 「现在可以打了」

## 环的尺寸。敌人精灵大体占 y −12..+20（高 52、脚贴 +20），
## 环心放在 −6、半轴 (26, 30) 正好把它圈住，不碰地面
const CENTER := Vector2(0.0, -6.0)
const RX := 26.0
const RY := 30.0
## 椭圆采样点数。32 段在 640×360 下看不出棱角，再多是浪费
const SEGMENTS := 32

## 护罩主色（冷蓝白）。**与命中火花的金/橙刻意拉开** ——
## 一个是「打中了」，一个是「打不动」，颜色不能是同一个家族
const RING_COLOR := Color(0.55, 0.85, 1.0)
## 碎掉那一下的白
const BREAK_COLOR := Color(0.95, 1.0, 1.0)

## 当前张开的程度（0 = 收掉，1 = 全开）。tick 里向 `_target` 缓动
var _open := 0.0
var _target := 0.0
## 碎闪剩余强度（0..1），接在 `_open` 上一起画
var _break := 0.0
## 挨了一下（挡住）的冲击强度（0..1）。**这一下是「你打不动」的当场回执** ——
## 截图实测：只有火花的话，在 640×360 里几乎看不见（2026-09-18）
var _impact := 0.0
var _t := 0.0


func _ready() -> void:
	# 护罩画在敌人本体之上（父节点是敌人根，不跟着后仰弹簧晃 ——
	# 它是「一层罩子」，不该跟着身体一起被撞歪）
	z_index = 1
	queue_redraw()


## 张开 / 收起。**用目标值 + 缓动，不要直接 snap** ——
## 护罩「啪」地出现会让玩家以为卡了一下，渐亮才是「它在起手」
func set_open(open: bool) -> void:
	_target = 1.0 if open else 0.0
	set_process(true)


## 相位结束那一下：白闪 + 立刻开始收
func break_flash() -> void:
	_break = 1.0
	set_open(false)


## 被砍了一下（伤害被挡下）：环当场亮一下、粗一圈。
##
## 光靠火花不够 —— 640×360 里 6 颗小方块很快就被角色动作盖住了（截图实测），
## 而「打不动」这件事必须**在挨打的那个东西身上**看得出来。
## 由敌人自己听 `Health.blocked` 调（见 walker._on_blocked）
func impact() -> void:
	_impact = 1.0
	set_process(true)


## 现在张开到什么程度（断言用）
func open_ratio() -> float:
	return _open


func tick(delta: float) -> void:
	_t += delta
	_open = move_toward(_open, _target, 3.6 * delta)
	_break = move_toward(_break, 0.0, 4.0 * delta)
	_impact = move_toward(_impact, 0.0, 6.0 * delta)
	# 收干净了就停 process —— 常驻的每帧重绘没有意义
	if is_zero_approx(_open) and is_zero_approx(_break) and is_zero_approx(_impact):
		set_process(false)
		visible = false
		return
	visible = true
	queue_redraw()


func _draw() -> void:
	if _open <= 0.0 and _break <= 0.0 and _impact <= 0.0:
		return
	# 呼吸脉冲：相位期间 ±8% 的半径摆动。静止的环看着像 UI，不像力量
	var pulse := 1.0 + 0.08 * sin(_t * 6.0)
	var a := clampf(maxf(_open, _impact), 0.0, 1.0)
	var outer := RING_COLOR
	outer.a = 0.85 * a
	# 挨打那一下把环推到近白、加粗 2px
	outer = outer.lerp(BREAK_COLOR, _impact * 0.8)
	var inner := RING_COLOR
	inner.a = 0.35 * a
	_draw_ring(RX * pulse, RY * pulse, outer, 2.0 + 2.0 * _impact)
	_draw_ring(RX * pulse - 3.0, RY * pulse - 3.0, inner, 1.0)
	if _break > 0.0:
		var b := BREAK_COLOR
		b.a = _break
		_draw_ring(RX * (1.0 + 0.5 * (1.0 - _break)), RY * (1.0 + 0.5 * (1.0 - _break)),
			b, 2.0 + 3.0 * _break)


## 画一圈椭圆（用折线近似；Godot 的 draw_arc 只画正圆）
func _draw_ring(rx: float, ry: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in SEGMENTS + 1:
		var a := TAU * float(i) / float(SEGMENTS)
		pts.append(CENTER + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, color, width, true)
