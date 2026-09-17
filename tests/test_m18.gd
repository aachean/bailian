extends Node
## 《百炼》自动验收：**素材致谢面板**。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m18.tscn
##
## ── 这一组为什么必须存在 ────────────────────────────────────────
## 致谢面板不是装饰，是**授权义务**：村民素材（CraftPix）是 **OGA-BY 3.0**，
## 该许可要求署名出现在**玩家看得到的地方**。漏一行 = 授权链断了。
## 而「漏一行」这件事引擎不会报错 —— 界面照样打得开，只是少了个人名。
## 所以这里盯死三样：
##
##   · **四个人名一个都不能少**（素材入库时最容易只顾着接图、忘了登记）
##   · **来源链接在场**（OGA-BY 要的不只是名字，还有指向来源页的链接）
##   · **按 J 打开不会当场被同一次按键关掉**（主菜单按钮支持 J 触发，
##     两层用同一个键是这个项目反复踩过的一类坑）
##
## 文案表改名（UI_CHAR_BACK → UI_BACK）也在这里守一道：
## 那个 key 从「选人页专用」变成三处共用，改漏一处就是界面上一句英文 key。

const AUTHORS := ["Mattz Art", "DezrasDragons", "MoikMellah", "CraftPix.net"]
## 来源链接里必须出现的关键片段（许可要求「可追溯」）
const SOURCE_HINTS := [
	"xzany.itch.io/free-knight-2d-pixel-art",
	"opengameart.org/content/ranger-animated",
	"opengameart.org/content/goblin-corps-mv-platformer-set",
	"opengameart.org/content/villagers-sprite-sheets-pixel-art-pack",
]

var _pass := 0
var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》素材致谢面板自动验收 ═══")
	await _run()
	print("")
	if _fail == 0:
		print("═══ %d 通过 ／ 0 失败 ═══" % _pass)
	else:
		print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])
	get_tree().quit()


func _run() -> void:
	var mm: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(mm)
	await _pframes(8)

	# ── 1. 入口 ──────────────────────────────────────────────
	var btn: Button = mm.get_node_or_null("Panel/Box/Credits") as Button
	_check("1", "主菜单有「素材致谢」按钮", btn != null,
		"节点 Panel/Box/Credits %s" % ("存在" if btn != null else "**不存在**"))
	if btn == null:
		return
	_check("2", "按钮文字走 csv（不写死人话）", btn.text == tr("UI_CREDITS"),
		"按钮='%s'  tr('UI_CREDITS')='%s'" % [btn.text, tr("UI_CREDITS")])

	var panel: Node = mm.get_node_or_null("CreditsPanel")
	_check("3", "面板已实例化", panel != null, "节点 CreditsPanel %s" % str(panel != null))
	if panel == null:
		return

	# 关闭态：不该一上来就盖着主菜单
	var open_before: bool = panel.call("is_open")
	_check("4", "打开主菜单时面板是收起的", open_before == false,
		"is_open() = %s" % str(open_before))

	# ── 2. 打开（走真实入口）─────────────────────────────────
	mm.call("_on_credits")
	await get_tree().process_frame
	var open_after: bool = panel.call("is_open")
	_check("5", "点「素材致谢」后面板打开", open_after == true,
		"is_open() = %s" % str(open_after))

	# ── 3. 署名完整性（授权硬要求）───────────────────────────
	var body: String = panel.call("body_text")
	var missing_a := []
	for a in AUTHORS:
		if not body.contains(a):
			missing_a.append(a)
	_check("6", "四位作者全部署名", missing_a.is_empty(),
		"缺失: %s ／ 正文 %d 行" % [str(missing_a) if not missing_a.is_empty() else "无",
			body.split("\n").size()])

	var missing_s := []
	for h in SOURCE_HINTS:
		if not body.contains(h):
			missing_s.append(h)
	_check("7", "四条来源链接在场（OGA-BY 要求可追溯）", missing_s.is_empty(),
		"缺失: %s" % (str(missing_s) if not missing_s.is_empty() else "无"))

	# 许可名也要写出来 —— 只写作者不写许可，等于没说清「凭什么能用」
	var lic_ok := body.contains("CC0") and body.contains("OGA-BY 3.0") and body.contains("SIL OFL")
	_check("8", "标注了许可名（CC0 / OGA-BY 3.0 / SIL OFL）", lic_ok,
		"正文里 CC0=%s OGA-BY 3.0=%s SIL OFL=%s" % [
			str(body.contains("CC0")), str(body.contains("OGA-BY 3.0")),
			str(body.contains("SIL OFL"))])

	var back: Button = panel.get_node_or_null("Root/Panel/Back") as Button
	_check("9", "有返回按钮且文案走 csv", back != null and back.text == tr("UI_BACK"),
		"按钮=%s 文字='%s'  tr('UI_BACK')='%s'" % [
			str(back != null), back.text if back != null else "-", tr("UI_BACK")])

	var title: Label = panel.get_node_or_null("Root/Panel/Title") as Label
	_check("10", "标题走 csv", title != null and title.text == tr("UI_CREDITS"),
		"标题='%s'" % (title.text if title != null else "-"))

	# ── 4. 按键不吃自己 ──────────────────────────────────────
	# 打开之后至少活过一帧（真按 J 打开时，同一次按键不许把它关掉）
	await get_tree().process_frame
	var alive: bool = panel.call("is_open")
	_check("11", "打开后不会被同一次按键当场关掉", alive == true,
		"open() 后过了一帧 is_open() = %s" % str(alive))

	# ── 5. 关闭 ──────────────────────────────────────────────
	await _tap(KEY_ESCAPE)
	await get_tree().process_frame
	var closed: bool = panel.call("is_open")
	_check("12", "Esc 关闭面板", closed == false, "is_open() = %s" % str(closed))

	# 再开一次，用 J 关（只读面板没有别的操作，J 就是关闭）
	mm.call("_on_credits")
	await _pframes(2)
	await _tap(KEY_J)
	await get_tree().process_frame
	var closed2: bool = panel.call("is_open")
	_check("13", "J 也能关闭（不给「按了没反应」留位置）", closed2 == false,
		"is_open() = %s" % str(closed2))

	# 关掉之后主菜单本身还在（别把主菜单一起带走）
	_check("14", "关掉面板后主菜单仍在", mm.visible and is_instance_valid(mm),
		"主菜单 visible=%s" % str(mm.visible))


# ── 工具 ──────────────────────────────────────────────────────

func _check(id: String, desc: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  #%-9s %s\n              %s" % [id, desc, detail])
	else:
		_fail += 1
		print("  FAIL  #%-9s %s\n              %s" % [id, desc, detail])


## 注入**真实按键**。界面用 `InputEventKey` 匹配按键时，
## `InputEventAction` 打进去它收不到（静默返回，看起来像「按了没反应」）
func _tap(key: int) -> void:
	var down := InputEventKey.new()
	down.keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = key
	up.pressed = false
	Input.parse_input_event(up)


func _pframes(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
