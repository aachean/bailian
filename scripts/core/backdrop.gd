extends Node2D
## 场景背景：天空（固定）+ 远景 + 中景（两层视差）。
##
## 用法：作为场景里最底层节点挂上，设 theme，其余自洽。
##     grass 砺场 / stone 断淬渠 / sand 炉喉 / town 城镇 / title 主菜单
##
## ── 为什么是 Sprite2D 而不是 TextureRect ─────────────────────
## 先用 TextureRect + STRETCH_TILE 做过一版：**Control 挂在 Node2D 下时
## size 行为不可靠**（贴图宽度会把框压回去，视差负偏移处露一大块清屏色）。
## 换成 Sprite2D + `region_enabled` + `texture_repeat` 之后平铺由纹理 wrap
## 直接负责，不依赖任何 Control 布局 —— 这是无限平铺的标准解法。
##
## ── 为什么不用 region + texture_repeat ──────────────────────
## Godot 4 里 Sprite2D 的 region_rect 越界不会 wrap（试过，直接变黑洞）。
## 贴图本来就拼了两个周期（1920 宽），平移范围 [-960, 0] 足以盖住 640 的视口，
## 所以移动整张精灵最简单也最可靠。

## 背景主题（assets/backgrounds/<theme>/）
@export var theme: StringName = &"grass"

## 视口尺寸（游戏固定 640x360）
const VIEW := Vector2(640.0, 360.0)
## 平铺周期（生成脚本：一个周期 960，图里拼了两遍 = 1920）
const TILE_W := 960.0
## 视差系数：越小越远
const FACTOR_FAR := 0.25
const FACTOR_MID := 0.5

var _sky: Sprite2D
var _far: Sprite2D
var _mid: Sprite2D
var _cam: Camera2D


func _ready() -> void:
	z_index = -100          # 压在所有地形/角色之下
	var base := "res://assets/backgrounds/%s/" % theme

	_sky = Sprite2D.new()
	_sky.name = "Sky"
	_sky.texture = load(base + "sky.png")
	_sky.centered = false
	add_child(_sky)

	_far = _tile_sprite("Far", base + "far.png")
	_mid = _tile_sprite("Mid", base + "mid.png")


## 平铺层：贴图 1920 宽（生成脚本拼了两个 960 周期），靠平移整张图做视差
func _tile_sprite(n: String, path: String) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.name = n
	sp.texture = load(path)
	sp.centered = false
	sp.position = Vector2.ZERO
	add_child(sp)
	return sp


func _process(_delta: float) -> void:
	if _cam == null:
		_cam = get_viewport().get_camera_2d()
		if _cam == null:
			return
	# 相机左边界的世界 x —— 视差按它算（用中心会让贴图相位差半屏）
	var c := _cam.get_screen_center_position()
	var left := c.x - VIEW.x * 0.5
	var top := c.y - VIEW.y * 0.5
	# **背景层要跟着相机走**：它们是「贴在屏幕上的布景」，不是世界里的物体。
	# 用世界坐标摆会随相机越走越偏（相机到 x=905 时，画在 0-640 的天空只剩 55px 在屏幕里）。
	# 天空完全跟随；远景/中景在跟随的基础上再按视差系数退后一点
	_sky.position = Vector2(left, top)
	_far.position = Vector2(left - fposmod(left * FACTOR_FAR, TILE_W), top)
	_mid.position = Vector2(left - fposmod(left * FACTOR_MID, TILE_W), top)
