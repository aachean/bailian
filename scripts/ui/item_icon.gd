class_name ItemIcon
extends Control
## 程序化装备图标 —— 不引图片资源，按部位画形状、按品质上色。
##
## ── 为什么用画的而不是贴图 ────────────────────────────────────
## 整个项目现在都是色块（M3 还没接美术），一个 16×16 的图标不值得引一整套
## 贴图管线；矢量形状还能按品质直接改色、任意缩放不糊。
## 三处共用同一套图标：背包面板、地上掉落物、以后要加的铁砧 / 商店。
##
## ── 形状 = 部位，颜色 = 品质 ──────────────────────────────────
## 剑 / 盔 / 甲 / 坠四种轮廓，一眼分得出是什么；
## 颜色直接取 ItemData.tier_color()，和地上掉落物、面板文字是同一个色源 ——
## 一件紫装在三个地方必须是同一个紫。

## 设计基准尺寸。控件多大都行，_draw() 里按 size 等比缩放
const DESIGN := 16.0

## 精铁碎片（不是装备的掉落物）的颜色
const SHARD_COLOR := Color(0.55, 0.78, 0.9)
## 空装备槽的框线颜色
const EMPTY_COLOR := Color(0.36, 0.33, 0.29)

## 装备资源路径。空 = 不是装备（地上掉落物画碎片、面板里画空框）
var item_path: String = ""
## true = 没装备时画一个空格子轮廓（面板用），而不是碎片
var empty_frame: bool = false

var _item: ItemData = null


## 设置图标内容。传空串 = 无装备
func set_item_path(path: String) -> void:
	item_path = path
	_item = load(path) as ItemData if not path.is_empty() else null
	queue_redraw()


func set_item(it: ItemData) -> void:
	_item = it
	item_path = "" if it == null else it.resource_path
	queue_redraw()


func item() -> ItemData:
	return _item


func _draw() -> void:
	var k := minf(size.x, size.y) / DESIGN
	if k <= 0.0:
		return
	if _item == null:
		if empty_frame:
			draw_rect(Rect2(Vector2(2, 2) * k, Vector2(12, 12) * k),
				EMPTY_COLOR, false, maxf(1.0, k))
		else:
			_draw_shard(k)
		return
	var base := _item.tier_color()
	var hi := base.lightened(0.4)
	var dark := base.darkened(0.55)
	match _item.slot:
		ItemData.Slot.HELM:
			_draw_helm(k, base, hi, dark)
		ItemData.Slot.ARMOR:
			_draw_armor(k, base, hi, dark)
		ItemData.Slot.TRINKET:
			_draw_trinket(k, base, hi, dark)
		_:
			_draw_sword(k, base, hi, dark)


## 精铁碎片：一颗小八角粒
func _draw_shard(k: float) -> void:
	draw_colored_polygon(_poly([
		Vector2(5, 1), Vector2(11, 1), Vector2(15, 5), Vector2(15, 11),
		Vector2(11, 15), Vector2(5, 15), Vector2(1, 11), Vector2(1, 5),
	], k), SHARD_COLOR)


## 剑：亮剑身（主体）+ 细护手 + 短柄。
## 护手必须【细】—— 先画成 8×2 的粗横条时，整体轮廓活像一个图钉
func _draw_sword(k: float, base: Color, hi: Color, dark: Color) -> void:
	# 剑身：宽 4、高 10，占满上半部
	draw_colored_polygon(_poly([
		Vector2(6, 0.5), Vector2(10, 0.5), Vector2(10, 10.5), Vector2(6, 10.5),
	], k), base)
	# 剑尖
	draw_colored_polygon(_poly([Vector2(6, 0.5), Vector2(8, -1.2), Vector2(10, 0.5)], k), base)
	# 中脊：提亮一条，剑身才不是一块死色
	draw_rect(_rect(7.3, 1.6, 8.7, 10.0, k), hi)
	# 护手：细横条
	draw_rect(_rect(4.2, 10.5, 11.8, 11.9, k), base)
	# 柄 + 柄尾
	draw_rect(_rect(6.9, 11.9, 9.1, 15.0, k), dark)
	draw_rect(_rect(6.2, 15.0, 9.8, 15.8, k), base)


## 头盔：穹顶 + 面甲横缝
func _draw_helm(k: float, base: Color, hi: Color, dark: Color) -> void:
	draw_colored_polygon(_poly([
		Vector2(2.5, 14), Vector2(2.5, 7), Vector2(4.5, 3.5),
		Vector2(8, 1.5), Vector2(11.5, 3.5), Vector2(13.5, 7), Vector2(13.5, 14),
	], k), base)
	draw_rect(_rect(8, 6.5, 13.5, 9, k), dark)      # 面甲缝
	draw_rect(_rect(2.5, 11, 6, 12.5, k), dark)     # 另一侧的缝
	draw_rect(_rect(2.5, 14, 13.5, 15.5, k), hi)    # 底沿


## 护甲：盾形胸甲 + 中脊
func _draw_armor(k: float, base: Color, hi: Color, dark: Color) -> void:
	draw_colored_polygon(_poly([
		Vector2(2.5, 2.5), Vector2(13.5, 2.5), Vector2(13.5, 9),
		Vector2(8, 15), Vector2(2.5, 9),
	], k), base)
	draw_colored_polygon(_poly([
		Vector2(7, 4), Vector2(9, 4), Vector2(9, 10.5), Vector2(8, 12), Vector2(7, 10.5),
	], k), dark)
	draw_colored_polygon(_poly([
		Vector2(2.5, 2.5), Vector2(13.5, 2.5), Vector2(13.5, 4), Vector2(2.5, 4),
	], k), hi)


## 饰品：菱形宝石 + 内芯
func _draw_trinket(k: float, base: Color, hi: Color, dark: Color) -> void:
	draw_colored_polygon(_poly([
		Vector2(8, 0.5), Vector2(15, 8), Vector2(8, 15.5), Vector2(1, 8),
	], k), base)
	draw_colored_polygon(_poly([
		Vector2(8, 4), Vector2(12, 8), Vector2(8, 12), Vector2(4, 8),
	], k), hi)
	draw_colored_polygon(_poly([
		Vector2(8, 6.5), Vector2(9.5, 8), Vector2(8, 9.5), Vector2(6.5, 8),
	], k), dark)


func _poly(pts: Array, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.x, p.y) * k)
	return out


func _rect(x0: float, y0: float, x1: float, y1: float, k: float) -> Rect2:
	return Rect2(Vector2(x0, y0) * k, Vector2(x1 - x0, y1 - y0) * k)
