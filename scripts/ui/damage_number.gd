extends Label
## 命中时飘出来的那个数字。
##
## 用 _process 手动推进，不用 Tween。理由：Tween 在无头模式下的推进时机依赖
## 进程帧，而自动验收是按物理帧数的，两者对不齐时「数字还在不在」这种断言会飘。
## 手推的落点和消失帧号都是确定的。

const LIFETIME := 0.72
const RISE_V0 := -92.0
const RISE_G := 240.0
const FADE_FROM := 0.34

var _t := 0.0
var _vy := RISE_V0


## amount 实际伤害；big 为 true 时是重击（更大更亮）
func setup(amount: int, big: bool) -> void:
	text = str(amount)
	var col := Color(1.0, 0.82, 0.28) if big else Color(0.97, 0.96, 0.92)
	add_theme_color_override("font_color", col)
	add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 0.95))
	add_theme_font_size_override("font_size", 20 if big else 14)
	add_theme_constant_override("outline_size", 5 if big else 3)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	z_index = 30


func _process(delta: float) -> void:
	_t += delta
	_vy += RISE_G * delta
	position.y += _vy * delta
	if _t > FADE_FROM:
		var k := (_t - FADE_FROM) / maxf(LIFETIME - FADE_FROM, 0.001)
		modulate.a = clampf(1.0 - k, 0.0, 1.0)
	if _t >= LIFETIME:
		queue_free()
