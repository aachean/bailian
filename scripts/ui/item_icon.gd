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
## 八种轮廓：剑/刀/弓/杖 + 盔/胸甲/护腿/靴 + 戒/项链/镯，一眼分得出是什么；
## 颜色直接取 ItemData.tier_color()，和地上掉落物、面板文字是同一个色源 ——
## 一件紫装在三个地方必须是同一个紫。

## 设计基准尺寸。控件多大都行，_draw() 里按 size 等比缩放
const DESIGN := 16.0

## 精铁碎片（不是装备的掉落物）的颜色
const SHARD_COLOR := Color(0.55, 0.78, 0.9)
## 空装备槽的框线颜色
const EMPTY_COLOR := Color(0.36, 0.33, 0.29)
## 元宝的颜色（金）。药水的颜色只在这一处定义 —— 地上的、面板里的、飘字必须同色
const GOLD_COLOR := Color(0.95, 0.78, 0.3)
const HEAL_COLOR := Color(0.88, 0.32, 0.3)
const MANA_COLOR := Color(0.4, 0.6, 0.95)

## 非装备形态：&"" 默认（碎片 / 装备），&"gold" 元宝，
## &"potion_hp"/&"potion_mp" 药水，&"supply" 补给包（两个瓶子并排）。
## 为什么进 ItemIcon 而不是另写一个图标类：三种新形态同样要「地上、面板两处同形同色」，
## 分家的话迟早漂移 —— 与「同一件装备四处同形同色」是同一条纪律
var kind: StringName = &""
## 材料掉落物用的辅助标识（哪种材料，决定矿石颜色）。非材料的图标不用它
var kind_hint: StringName = &""

## **本角色用不了**（非本职业的武器）→ 整体压暗 + 一道斜杠。
##
## 为什么必须有：掉落**不按职业过滤**（ADR-0025 §2）是刻意的设计 ——
## 别的职业的武器是经济来源。代价是加满 4 职业之后，**任意角色只有 1/4 的武器能用**，
## 也就是说「这东西我用不了」从偶发变成常态。而在此之前，玩家要**按下 J**
## 才会看到那句提示 —— 列表上什么都没有。那是本项目最不接受的一种失败。
##
## 为什么是斜杠：16px 上「压暗」只说「这里有点不对」，说不清是没穿、已卖还是等级不够。
## 斜杠说的是「现在不能用」，与详情栏那句人话配起来才完整。
var locked := false

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
	match kind:
		&"gold":
			_draw_gold(k)
			return
		&"potion_hp":
			_draw_potion(k, HEAL_COLOR)
			return
		&"potion_mp":
			_draw_potion(k, MANA_COLOR)
			return
		&"supply":
			_draw_supply(k)
			return
		&"revive":
			_draw_revive(k)
			return
		&"material":
			_draw_ore(k)
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
	if locked:
		# 压暗**在源头改**：八种部位形状 + 四种武器各自算色，
		# 在出口处改一处就够（与 SkillIcon.dim 同一手法，不去动十二个绘制函数）。
		# **只压 25%，不能更多**：第一版压了 45%，截图里那把刀糊成一个灰团 ——
		# 而「八种轮廓必须两两可辨」是这里的老规矩，认不出形状就等于把
		# 「这是什么」也一起删掉了。信号由斜杠给，压暗只负责「它和别的不一样」
		base = base.darkened(0.25)
		hi = hi.darkened(0.25)
		dark = dark.darkened(0.25)
	# 形状 = 部位（v2 八槽），颜色 = 品质（六档）。
	# **八种轮廓必须两两可辨** —— 认不出形状时，「这件穿哪儿」就只能读文字，
	# 而装备栏的一行本来就只有 16px 宽的位置放图标
	match _item.slot:
		ItemData.Slot.HELM:
			_draw_helm(k, base, hi, dark)
		ItemData.Slot.CHEST:
			_draw_chest(k, base, hi, dark)
		ItemData.Slot.LEGS:
			_draw_legs(k, base, hi, dark)
		ItemData.Slot.BOOTS:
			_draw_boots(k, base, hi, dark)
		ItemData.Slot.RING:
			_draw_ring(k, base, hi)
		ItemData.Slot.NECKLACE:
			_draw_necklace(k, base, hi)
		ItemData.Slot.BRACELET:
			_draw_bracelet(k, base, hi)
		_:
			# 武器按类型分家（v2 四种）：弓画弓、刀画单刃、杖画杆加宝珠，其余画剑 ——
			# 背包里铁剑和逐风弓得一眼分得出，不然装备门提示都像在说谎
			match _item.weapon_type:
				&"bow":
					_draw_bow(k, base, hi)
				&"blade":
					_draw_blade(k, base, hi, dark)
				&"staff":
					_draw_staff(k, base, hi, dark)
				_:
					_draw_sword(k, base, hi, dark)
	if locked:
		_draw_locked(k)


## 「用不了」的斜杠。**先垫一道深色再画暖红** ——
## 不垫底的话，画在浅色图标上（传说黄、至尊红）这根线会糊掉，
## 而这一条恰恰是最需要「一眼看得见」的
func _draw_locked(k: float) -> void:
	draw_line(Vector2(2.5, 13.5) * k, Vector2(13.5, 2.5) * k,
		Color(0.1, 0.08, 0.08, 0.9), maxf(2.0, 2.8 * k))
	draw_line(Vector2(2.5, 13.5) * k, Vector2(13.5, 2.5) * k,
		Color(0.98, 0.46, 0.4), maxf(1.1, 1.5 * k))


## 弓：一段弧 + 弦 + 搭着的箭杆
func _draw_bow(k: float, base: Color, hi: Color) -> void:
	# 弓身：右弯的弧（八个近似点，draw_arc 的粗细随缩放）
	var pts := PackedVector2Array()
	for i in 9:
		var a := -1.25 + 2.5 * float(i) / 8.0
		pts.append(Vector2(4.0 + 5.0 * cos(a), 8.0 + 7.0 * sin(a)) * k)
	for i in pts.size() - 1:
		draw_line(pts[i], pts[i + 1], base, maxf(1.6, 1.6 * k))
	# 弦
	draw_line(pts[0], pts[pts.size() - 1], hi, maxf(1.0, k))
	# 搭着的箭
	draw_line(Vector2(1.5, 8.0) * k, Vector2(13.0, 8.0) * k, hi, maxf(1.2, 1.2 * k))
	draw_colored_polygon(PackedVector2Array([
		Vector2(15, 8) * k, Vector2(12, 6.2) * k, Vector2(12, 9.8) * k,
	]), hi)


## 精铁碎片：一颗小八角粒
func _draw_shard(k: float) -> void:
	draw_colored_polygon(_poly([
		Vector2(5, 1), Vector2(11, 1), Vector2(15, 5), Vector2(15, 11),
		Vector2(11, 15), Vector2(5, 15), Vector2(1, 11), Vector2(1, 5),
	], k), SHARD_COLOR)


## 元宝：金锭——梯形底座 + 顶上一颗鼓包，一眼「值钱」
## 材料（掉落物）：矿石 / 晶体。五种材料一个形状、颜色区分 ——
## 地上认出「这是料」比认出「是哪种料」更要紧，颜色是第二层信息
func _draw_ore(k: float) -> void:
	var c := Color(0.75, 0.72, 0.62, 1)      # 默认（精铁）土金
	match kind_hint:
		&"mat_black_iron":   c = Color(0.45, 0.45, 0.52, 1)
		&"mat_sky_crystal":  c = Color(0.45, 0.7, 0.95, 1)
		&"mat_dragon_soul":  c = Color(0.9, 0.4, 0.35, 1)
		&"mat_taichu":       c = Color(0.95, 0.85, 0.4, 1)
	var dark := c.darkened(0.4)
	var hi := c.lightened(0.35)
	draw_colored_polygon(_poly([
		Vector2(8, 1.5), Vector2(14.5, 6), Vector2(12, 14), Vector2(4, 14),
		Vector2(1.5, 6),
	], k), c)
	draw_colored_polygon(_poly([
		Vector2(8, 4), Vector2(11.5, 6.5), Vector2(10, 11.5), Vector2(6, 11.5),
		Vector2(4.5, 6.5),
	], k), dark)
	draw_colored_polygon(_poly([
		Vector2(8, 2.5), Vector2(13, 6), Vector2(8, 6),
	], k), hi)


func _draw_gold(k: float) -> void:
	var dark := GOLD_COLOR.darkened(0.35)
	var hi := GOLD_COLOR.lightened(0.35)
	draw_colored_polygon(_poly([
		Vector2(2, 10), Vector2(14, 10), Vector2(12.5, 15), Vector2(3.5, 15),
	], k), GOLD_COLOR)
	draw_colored_polygon(_poly([
		Vector2(5, 5), Vector2(11, 5), Vector2(14, 10), Vector2(2, 10),
	], k), dark)
	draw_colored_polygon(_poly([
		Vector2(8, 1.5), Vector2(11.5, 5), Vector2(4.5, 5),
	], k), hi)


## 药水：细颈圆瓶 + 瓶塞。回血红、回蓝蓝（形状相同，只换色 —— 玩家学一次就认识）
func _draw_potion(k: float, liquid: Color) -> void:
	var glass := Color(0.85, 0.87, 0.9, 0.9)
	var dark := liquid.darkened(0.4)
	draw_rect(_rect(6.6, 1.2, 9.4, 3.4, k), dark)             # 瓶塞
	draw_rect(_rect(6.9, 3.4, 9.1, 6.5, k), glass)            # 瓶颈
	draw_colored_polygon(_poly([                               # 瓶身（圆·八边形近似）
		Vector2(3.5, 10), Vector2(5, 6.6), Vector2(11, 6.6), Vector2(12.5, 10),
		Vector2(12.5, 12), Vector2(10.5, 14.6), Vector2(5.5, 14.6), Vector2(3.5, 12),
	], k), liquid)
	draw_rect(_rect(5.4, 7.6, 7.0, 12.5, k), glass.lightened(0.3))  # 高光


## 补给包：**一大一小两个瓶子并排**（血 + 蓝）。
## 为什么不借回血符的瓶子：商店左栏里「回血符」和「补给包」就挨着放，
## 同一个图标会让玩家每次都读错一行 —— 而行数一旦读错，买错东西只是时间问题。
## 形状复用 `_draw_potion`，靠 `draw_set_transform` 缩小挪位（0.62 是「两个瓶子
## 塞进 16 宽的设计盒」能取的最大值：9 × 0.62 × 2 = 11.2 < 16）
func _draw_supply(k: float) -> void:
	draw_set_transform(Vector2(-2.5, 3.0), 0.0, Vector2(0.62, 0.62))
	_draw_potion(k, HEAL_COLOR)
	draw_set_transform(Vector2(7.5, 3.0), 0.0, Vector2(0.62, 0.62))
	_draw_potion(k, MANA_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)      # 复位，别影响后续绘制


## 还魂丹：一颗圆丹 + 高光 + 暗边。
## **不借回血符的瓶子** —— 商店左栏里它就和回血符上下挨着，
## 两个红瓶子同屏 = 每次买丹都在赌自己没看错行
func _draw_revive(k: float) -> void:
	var body := Color(0.95, 0.45, 0.45)
	draw_circle(Vector2(8, 9) * k, 5.6 * k, body)
	draw_arc(Vector2(8, 9) * k, 5.6 * k, 0.0, TAU, 20, body.darkened(0.45), maxf(1.0, k))
	draw_circle(Vector2(6.0, 6.9) * k, 1.7 * k, body.lightened(0.6))


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


## 胸甲：盾形躯干 + 中脊（原 _draw_armor，v2 槽位改名）
func _draw_chest(k: float, base: Color, hi: Color, dark: Color) -> void:
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


## 护腿：腰带 + 两条收窄的腿甲（宽度收在中间，与胸甲的整块轮廓分得开）
func _draw_legs(k: float, base: Color, hi: Color, dark: Color) -> void:
	draw_rect(_rect(3.0, 1.6, 13.0, 3.6, k), dark)                    # 腰带
	draw_colored_polygon(_poly([
		Vector2(3.4, 3.6), Vector2(7.2, 3.6), Vector2(6.6, 14.6), Vector2(4.0, 14.6),
	], k), base)
	draw_colored_polygon(_poly([
		Vector2(8.8, 3.6), Vector2(12.6, 3.6), Vector2(12.0, 14.6), Vector2(9.4, 14.6),
	], k), base)
	draw_rect(_rect(3.4, 3.6, 7.2, 4.8, k), hi)
	draw_rect(_rect(8.8, 3.6, 12.6, 4.8, k), hi)


## 靴子：两只 L 形靴（靴筒 + 外翻的靴头）+ 鞋底
func _draw_boots(k: float, base: Color, hi: Color, dark: Color) -> void:
	draw_colored_polygon(_poly([
		Vector2(1.6, 3.6), Vector2(6.0, 3.6), Vector2(6.0, 12.4), Vector2(1.6, 12.4),
	], k), base)
	draw_colored_polygon(_poly([
		Vector2(1.6, 12.4), Vector2(6.0, 12.4), Vector2(6.0, 14.4), Vector2(0.8, 14.4),
	], k), base)
	draw_rect(_rect(1.6, 3.6, 6.0, 4.8, k), hi)
	draw_colored_polygon(_poly([
		Vector2(10.0, 3.6), Vector2(14.4, 3.6), Vector2(14.4, 12.4), Vector2(10.0, 12.4),
	], k), base)
	draw_colored_polygon(_poly([
		Vector2(10.0, 12.4), Vector2(14.4, 12.4), Vector2(15.2, 14.4), Vector2(10.0, 14.4),
	], k), base)
	draw_rect(_rect(10.0, 3.6, 14.4, 4.8, k), hi)
	draw_rect(_rect(0.8, 14.2, 15.2, 15.5, k), dark)                  # 鞋底


## 戒指：细环 + 顶上一颗宝石（环细、宝石小，与手镯的粗开口环分得开）
func _draw_ring(k: float, base: Color, hi: Color) -> void:
	draw_polyline(_circle(8.0, 10.0, 4.8, 14, k), base, maxf(1.6, 1.6 * k))
	draw_colored_polygon(_poly([
		Vector2(8, 0.8), Vector2(11.2, 4.4), Vector2(8, 7.6), Vector2(4.8, 4.4),
	], k), hi)


## 项链：V 形细链 + 一个坠子
func _draw_necklace(k: float, base: Color, hi: Color) -> void:
	draw_polyline(_poly([
		Vector2(1.0, 2.0), Vector2(4.4, 6.4), Vector2(8.0, 8.6),
		Vector2(11.6, 6.4), Vector2(15.0, 2.0),
	], k), base, maxf(1.3, 1.3 * k))
	draw_colored_polygon(_poly([
		Vector2(8, 8.6), Vector2(11.0, 11.6), Vector2(8, 15.2), Vector2(5.0, 11.6),
	], k), hi)


## 手镯：粗的开口环（两端各一段端头，一眼区别于戒指的细闭环）
func _draw_bracelet(k: float, base: Color, hi: Color) -> void:
	draw_polyline(_circle(8.0, 8.6, 5.4, 16, k), base, maxf(2.0, 2.0 * k))
	draw_rect(_rect(1.8, 3.4, 4.8, 5.4, k), hi)
	draw_rect(_rect(11.2, 3.4, 14.2, 5.4, k), hi)


## 刀：单刃、刀背带弧（与剑的直身双刃一眼分得出）
func _draw_blade(k: float, base: Color, hi: Color, dark: Color) -> void:
	draw_colored_polygon(_poly([
		Vector2(6.0, 1.0), Vector2(9.0, 0.5), Vector2(11.6, 10.8), Vector2(7.6, 10.8),
	], k), base)
	draw_colored_polygon(_poly([
		Vector2(9.0, 0.5), Vector2(11.6, 10.8), Vector2(12.5, 10.4),
	], k), hi)
	draw_rect(_rect(4.6, 10.8, 13.4, 12.2, k), dark)                  # 护手
	draw_rect(_rect(7.2, 12.2, 10.0, 15.6, k), dark)                  # 柄


## 法杖：长杆 + 顶端宝珠
func _draw_staff(k: float, base: Color, hi: Color, dark: Color) -> void:
	draw_rect(_rect(7.1, 4.2, 8.9, 15.6, k), dark)                    # 杆
	draw_colored_polygon(_poly([
		Vector2(8, 0.4), Vector2(11.6, 3.6), Vector2(8, 6.8), Vector2(4.4, 3.6),
	], k), base)
	draw_colored_polygon(_poly([
		Vector2(8, 2.0), Vector2(10.2, 3.6), Vector2(8, 5.2), Vector2(5.8, 3.6),
	], k), hi)


## 圆（n 边形近似），直接乘好 k —— 给 draw_polyline 用的折线
func _circle(cx: float, cy: float, r: float, n: int, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		out.append(Vector2(cx + r * cos(a), cy + r * sin(a)) * k)
	return out


func _poly(pts: Array, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.x, p.y) * k)
	return out


func _rect(x0: float, y0: float, x1: float, y1: float, k: float) -> Rect2:
	return Rect2(Vector2(x0, y0) * k, Vector2(x1 - x0, y1 - y0) * k)
