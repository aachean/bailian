extends Node
## 《百炼》自动验收：**鼠标点击映射**（第 4 批 4b：商店两栏 + 舆图页签/行）。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m21.tscn
##
## ── 为什么单开一组 ─────────────────────────────────────────────
## 鼠标点击是 UI 层行为：**截图拍不出来**（画面上跟没做时一模一样）、
## **无头也点不了**（没有真实指针）。放着不管的话，整条链就只能靠人肉点 ——
## 而 4b 里「行号 → 列表绝对索引 → 确认」这一步恰好最容易错，
## 错了又最难发现（点错一行 = 买错一件东西 / 进错一个副本）。
## 所以 4b 把这条链抽成了 `_click_*` 具名函数，这一组直接调它们。
## 铁律：能自动判定的一律交给 `tests/`，交付清单只留手感。
##
## ── 这一组盯的五件事 ───────────────────────────────────────────
## 1. **分级口径**：商店是「花钱不可逆」→ 两步（点一次只选中、再点同一行才买）；
##    舆图进副本是导航 → 单击即生效。写反了就是「误点买掉一万块」或「点了没反应」。
## 2. **两栏的索引换算不一样**（本批唯一的复杂点）：左栏没有滚动窗口，
##    行号**就是**绝对索引；右栏有 `_bp_top` 滚动窗口，要加上窗口顶 + 左栏长度。
##    **右栏必须让 `_bp_top` 真的大于 0 才算走过这条路** —— `_bp_top=0` 时
##    两栏的算式恰好等价，那种「怎么算都对」的绿是假绿。
## 3. **点空行忽略**：货架没抽满 / 制书不满 8 行时，那些行后面没有东西可买。
## 4. **舆图不可选的行点不进去**：键盘光标本来就到不了未解锁的行，
##    鼠标若能点进去，就等于给了一道后门。
## 5. **左栏条目正好顶到 11 行上限**时越界判定仍然对 ——
##    边界上差一个是这类代码最常见的错（`>=` 写成 `>`）。
##
## ── 测不到的一条（记下来，别当它已经验过）──────────────────────
## 舆图「点可选行 → 真的进副本」会走 `change_scene_to_file`：测试节点当场被释放，
## 汇总表根本打不出来（会显示成「没跑完」，那是假警报）。
## 所以 `_click_atlas_row` 只验「守卫拦不拦 / 光标落对没有」，
## **进场那一步只有实玩能验**。

const ROOM := preload("res://scenes/stages/test_room.tscn")

var _pass := 0
var _fail := 0
var _shop: Node
var _atlas: Node


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》鼠标点击映射自动验收（4b：商店 / 舆图）═══")

	var room := ROOM.instantiate()
	add_child(room)
	await _pframes(5)
	var player := room.get_node("Player")
	_shop = player.get_node_or_null("ShopPanel")
	_atlas = player.get_node_or_null("Atlas")
	if _shop == null or _atlas == null:
		_check("0", "两个面板都找得到", false,
			"ShopPanel=%s　Atlas=%s" % [str(_shop != null), str(_atlas != null)])
		_done()
		return

	await _t1_shop_left_first_click_selects()
	await _t2_shop_left_second_click_buys()
	await _t3_shop_left_empty_row_ignored()
	await _t4_shop_right_column_with_scroll()
	await _t5_shop_right_empty_row_ignored()
	await _t6_atlas_tab_switches_map()
	await _t7_atlas_locked_row_ignored()
	await _t8_atlas_out_of_range_ignored()

	_done()


# ── 1~3. 商店左栏 ───────────────────────────────────────────────

## 两步的第一半：**只选中，不许买东西**。这一步写成了「一点就买」，
## 屏幕上完全看不出来（选中标记本来就会跟着走），只有元宝和背包能作证
func _t1_shop_left_first_click_selects() -> void:
	_prep_shop()
	var gold0 := PlayerState.gold
	var bag0 := PlayerState.bag.size()
	_shop.call("_click_shop", 0, 3)
	var cur := int(_shop.get("_cursor"))
	_check("1", "商店左栏：点一行还没选过的 = **只选中**，元宝和背包都不动",
		cur == 3 and PlayerState.gold == gold0 and PlayerState.bag.size() == bag0,
		"光标 →%d（期望 3）　元宝 %d（期望 %d）　背包 %d 件（期望 %d）" % [
			cur, PlayerState.gold, gold0, PlayerState.bag.size(), bag0])


## 两步的第二半：点**已经选中的同一行**才真买。
## 买哪一行不写死下标 —— 从 `_left_entries()` 里找 `item_hp`（尾部固定四行之一），
## 位置若被人挪了，这一条跟着挪而不是变红（顺序自有 test_m20 #14 去卡）
func _t2_shop_left_second_click_buys() -> void:
	_prep_shop()
	var entries: Array = _shop.call("_left_entries")
	var i := entries.find("item_hp")
	if i < 0:
		_check("2", "商店左栏确认购买", false, "左栏里没有 item_hp 行")
		return
	var before := PlayerState.potion_charges(PlayerState.POTION_HP)
	_shop.call("_click_shop", 0, i)                    # 第一次：选中
	var cur_sel := int(_shop.get("_cursor"))
	var gold_sel := PlayerState.gold
	_shop.call("_click_shop", 0, i)                    # 第二次：确认
	var gained := PlayerState.potion_charges(PlayerState.POTION_HP) - before
	_check("2", "商店左栏：再点同一行才真买（元宝 500→440、回血符 +3 次）",
		cur_sel == i and gold_sel == 500 and PlayerState.gold == 440 \
			and gained == PlayerState.POTION_CHARGES,
		"点一次后：光标=%d　元宝=%d（两个都该没动）　｜　点两次后：元宝=%d　次数 +%d（该 +%d）" % [
			cur_sel, gold_sel, PlayerState.gold, gained, PlayerState.POTION_CHARGES])


## 空行忽略：只抽到 2 件货架 → 左栏 6 条，第 7 行（下标 6）还在屏上但后面没有东西。
## 点它必须**无声地什么都不做**（不是报错、不是把光标移过去）
func _t3_shop_left_empty_row_ignored() -> void:
	_prep_shop(true)
	var left_n: int = _shop.call("_left_entries").size()
	_shop.call("_click_shop", 0, left_n + 1)
	var cur := int(_shop.get("_cursor"))
	_check("3", "商店左栏：点空行（货架没抽满）= 忽略，光标不动",
		cur == 0, "左栏 %d 条　点了第 %d 行 → 光标 = %d（必须还是 0）" % [
			left_n, left_n + 1, cur])


# ── 4~5. 商店右栏（制书，有滚动窗口）─────────────────────────────

## **本批唯一真正的复杂点**。把制书塞到 20 本，好让 `_bp_top` 真的被顶起来
## （真实玩法是每期 8 本、窗口 8 行，正好不滚 —— 也就是这条路平时根本走不到，
## 而窗口是活的：哪天真把 roll 数调大，就得靠这一条兜住）。
##
## 断言取的是**语义**而不是算式：先记下第 0 行此刻显示的是哪本书，
## 再点它，然后要求光标落在那本书上。若只比 `left.size() + _bp_top + r`，
## 那就是拿实现算给实现看，永远绿
func _t4_shop_right_column_with_scroll() -> void:
	_prep_shop()
	var pool: Array = []
	for t in [ItemData.Tier.RARE, ItemData.Tier.EPIC, ItemData.Tier.LEGENDARY]:
		pool.append_array(GameProgress.drop_pool(t))
	if pool.size() < 20:
		_check("4", "商店右栏索引换算", false, "制书池只有 %d 本，凑不出 20" % pool.size())
		return
	PlayerState.shop_bp_offers = pool.slice(0, 20)
	var left_n: int = _shop.call("_left_entries").size()
	# 光标先摆进右栏靠后处 → refresh() 会把 _bp_top 顶到非 0
	_shop.set("_cursor", left_n + 15)
	_shop.call("refresh")
	var top := int(_shop.get("_bp_top"))
	if top <= 0:
		_check("4", "商店右栏索引换算", false,
			"_bp_top 仍是 0 —— 这条会退化成假绿（20 本配 8 行窗口不该为 0）")
		return
	# 第 0 行此刻显示的是哪本书
	var rows: Array = _shop.get("_bp_rows")
	var shown := ((rows[0] as HBoxContainer).get_child(1) as Label).text
	# 光标挪回左栏：制造「这一行还没被选中」。窗口不动（refresh 对 _bp_top 只夹紧）
	_shop.set("_cursor", 0)
	_shop.call("refresh")
	_shop.call("_click_shop", 1, 0)
	var cur := int(_shop.get("_cursor"))
	var bp_i := cur - left_n
	var bps: Array = _shop.call("_bp_list")
	var target: ItemData = null
	if bp_i >= 0 and bp_i < bps.size():
		target = load(str(bps[bp_i])) as ItemData
	var hit: bool = target != null and tr(target.name_key) in shown
	_check("4", "商店右栏：点第 0 行 = 选中**那一行显示的那本书**（窗口顶≠0 时也对）",
		hit, "窗口顶 _bp_top=%d　第 0 行显示「%s」　点后光标=%d → 制书序 #%d = %s" % [
			top, shown, cur, bp_i, tr(target.name_key) if target != null else "?"])


## 制书不满 8 行时，后几行是空的 —— 点它们必须忽略
func _t5_shop_right_empty_row_ignored() -> void:
	_prep_shop()
	var pool: Array = GameProgress.drop_pool(ItemData.Tier.RARE)
	if pool.size() < 5:
		_check("5", "商店右栏点空行", false, "制书池不足 5 本")
		return
	PlayerState.shop_bp_offers = pool.slice(0, 5)
	_shop.set("_cursor", 0)
	_shop.set("_bp_top", 0)
	_shop.call("refresh")
	_shop.call("_click_shop", 1, 6)          # 只有 5 本，第 6 行是空的
	var cur := int(_shop.get("_cursor"))
	_check("5", "商店右栏：点空行（制书不满 8 行）= 忽略，光标不动",
		cur == 0, "制书 5 本　点了第 6 行 → 光标 = %d（必须还是 0）" % cur)


# ── 6~8. 舆图 ───────────────────────────────────────────────────

## 换地图**单击即生效**（换个看法，不带走任何东西）。
## `_switch_map` 收的是**增量**不是目标下标，`_click_tab` 得自己减 ——
## 减错了会跳到别的图上，而那是「点第一章跳到第二章」这种一眼看不出的错
func _t6_atlas_tab_switches_map() -> void:
	var ms := GameProgress.maps()
	if ms.size() < 2:
		_check("6", "舆图页签切换地图", false, "地图不足 2 张（%d），测不了" % ms.size())
		return
	_atlas.call("_build")
	var idx0 := int(_atlas.get("_map_idx"))
	var other := (idx0 + 1) % ms.size()
	_atlas.call("_click_tab", other)
	var idx1 := int(_atlas.get("_map_idx"))
	_check("6", "舆图：点另一张地图的页签 = 换过去（单击即生效）",
		idx1 == other, "共 %d 张图　_map_idx %d → %d（点了第 %d 张）" % [
			ms.size(), idx0, idx1, other])


## 未解锁的行**整行忽略**。键盘光标本来就绕开它们，鼠标也不许点进去 ——
## 否则 `_activate()` 之外就多了一条「随便点一行」的路径。
##
## 光标先摆在**最后一行（回安全区，可选）**：若摆在 0 而锁行正好也是 0，
## 断言「光标还是 0」就成了永远绿的废话
func _t7_atlas_locked_row_ignored() -> void:
	_atlas.call("_build")
	var rows: Array = _atlas.get("_rows")
	if rows.size() < 2:
		_check("7", "舆图不可选行", false, "行数只有 %d，测不了" % rows.size())
		return
	var locked_i := -1
	for i in rows.size():
		if not bool(rows[i].get("sel", false)):
			locked_i = i
			break
	if locked_i < 0:
		_check("7", "舆图不可选行", false, "这张地图没有不可选的行，测不了")
		return
	var last := rows.size() - 1
	_atlas.set("_cursor", last)
	_atlas.call("_click_atlas_row", locked_i)
	var cur := int(_atlas.get("_cursor"))
	_check("7", "舆图：点未解锁的行 = 整行忽略（光标不动）",
		cur == last, "共 %d 行　点了第 %d 行（不可选）→ 光标 = %d（该留在第 %d 行）" % [
			rows.size(), locked_i, cur, last])


## 越界（点到面板外 / 空行）忽略
func _t8_atlas_out_of_range_ignored() -> void:
	_atlas.call("_build")
	var rows: Array = _atlas.get("_rows")
	var last := rows.size() - 1
	_atlas.set("_cursor", last)
	_atlas.call("_click_atlas_row", rows.size() + 5)
	_atlas.call("_click_atlas_row", -1)
	var cur := int(_atlas.get("_cursor"))
	_check("8", "舆图：点越界的行号 = 忽略（光标不动）",
		cur == last, "共 %d 行　点了 %d 和 -1 → 光标 = %d（该留在第 %d 行）" % [
			rows.size(), rows.size() + 5, cur, last])


# ── 工具 ─────────────────────────────────────────────────────────

## 摆一个「可点」的商店状态：7 件货架（或 2 件）+ 500 元宝。
##
## **不调 `open()`**：`_click_shop` 和 `refresh()` 都不看可见性，
## 而 `open()` 会暂停场景树、还要拉 HUD 让路 —— 在这一组里纯属噪声
func _prep_shop(few_offers: bool = false) -> void:
	PlayerState.reset_for_new_game()
	PlayerState.gold = 500
	var offers: Array = []
	for t in [ItemData.Tier.COMMON, ItemData.Tier.FINE, ItemData.Tier.UNCOMMON]:
		offers.append_array(GameProgress.drop_pool(t))
	PlayerState.shop_offers = offers.slice(0, 2 if few_offers else 7)
	PlayerState.shop_bp_offers = []
	_shop.set("_cursor", 0)
	_shop.set("_bp_top", 0)
	_shop.call("refresh")


func _done() -> void:
	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().paused = false          # 安全网：绝不能带着暂停退出
	get_tree().quit(0 if _fail == 0 else 1)


func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-3s %s\n              %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-3s %s\n              %s" % [id, desc, detail])


func _pframes(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
