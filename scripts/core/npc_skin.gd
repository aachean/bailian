class_name NpcSkin
extends Sprite2D
## NPC 的帧序列精灵：只播 idle 循环（NPC 是站桩说话的，不需要战斗动画）。
##
## 素材包（CraftPix 村民包）还带了 walk/attack/hurt/death，留着 —— 哪天要做
## 「会走动的 NPC」直接在这里加分支，调用方一行不用动。
##
## ── 对齐纪律（这个家族踩过三次坑）────────────────────────────
## 位置一律**从帧内容推**，不凭手感调：
##   村民帧 48x48、实测内容 y16~48（**脚贴帧底**，没有留白）→ 脚位 = 帧底。
## 和主角（帧底留白 22px）、怪（帧 32x64、小人居中偏下）都不一样，
## 所以别抄它们的位置数字。

const FRAME_H := 48.0
## 帧内小人的脚 y（村民包实测：脚贴帧底）
const FOOT_Y := 48.0

var _idle: Array[Texture2D] = []
var _clock := 0.0
var _fps := 6.0


## dir = 帧序列目录（如 res://assets/npcs/old_man）
## feet_y = **脚**落在父节点本地的 y（NPC 的碰撞/色块脚底在 +18，默认对齐它）
func setup(dir: String, feet_y := 18.0, px_scale := 1.5) -> bool:
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("NPC 帧序列目录不存在：%s" % dir)
		return false
	var list: Array = []
	for f in d.get_files():
		if f.begins_with("idle_") and f.ends_with(".png"):
			list.append([int(f.trim_prefix("idle_").trim_suffix(".png")), f])
	if list.is_empty():
		push_warning("NPC 帧序列目录里没有 idle_N.png：%s" % dir)
		return false
	list.sort_custom(func(a, b): return a[0] < b[0])
	for e in list:
		_idle.append(load(dir + "/" + str(e[1])))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(px_scale, px_scale)
	position = Vector2(0.0, feet_y - (FOOT_Y - FRAME_H * 0.5) * px_scale)
	texture = _idle[0]
	visible = true
	return true


## 静态单图模式（告示牌、雕像这类不会动的东西）：整张图 1:1，底边对齐 feet_y。
## 与帧序列模式共用同一个位置公式（脚在 feet_y），调用方不必区分。
func setup_static(path: String, feet_y := 18.0, px_scale := 1.0) -> bool:
	if not ResourceLoader.exists(path):
		push_warning("NPC 静态贴图不存在：%s" % path)
		return false
	var tex: Texture2D = load(path)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(px_scale, px_scale)
	texture = tex
	position = Vector2(0.0, feet_y - tex.get_height() * px_scale * 0.5)
	visible = true
	return true


func tick(delta: float) -> void:
	if _idle.size() < 2:
		return
	_clock += delta * _fps
	texture = _idle[int(_clock) % _idle.size()]
