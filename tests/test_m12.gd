extends Node
## 《百炼》M3 增量 10 自动验收：**暂停菜单的两个新按钮 + 设置面板**。
##
## 跑法（无头）：
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/test_m12.tscn
##
## 前情：这一版补的是神的原话 ——
##   「进副本后，按下 esc 后跳出的面板需要加**回到城镇**和**设置**两个按钮，
##     设置里面用于放一些背景音乐、音效、语言以及后续的通用配置等，
##     游戏主界面也同理，要有个设置」
##
## 断言分三块，每块盯一类**只有截图或断言才抓得到**的失败：
##   · 按钮层 —— 画出来了、**接上动作了没有**（没接的按钮看着像能点，最静默）
##   · 状态层 —— 「在城镇里不该给回城」「设置开着时 Esc 只关一层」
##   · 生效层 —— 音量真的落到**引擎的总线**上了没有（改个变量也能骗过眼睛）
##
## 本测试根节点**冒充副本根节点**：暂停菜单用「当前场景能不能 `restart()`」
## 判「这是副本还是安全区」（与死亡界面同一套判据），定义了 restart 才是副本。
## 这个手法照 test_m9 —— 它也靠同一个方法让死亡界面的「重新开始」跑通。

const TOWN := preload("res://scenes/stages/town.tscn")

const SETTINGS_PATH := "user://settings.cfg"

var _pass := 0
var _fail := 0
var _bak_settings: PackedByteArray = PackedByteArray()
var _had_settings := false

## 冒充副本根节点用。本测试不真的调它，只让 `has_method("restart")` 成立
var _restart_called := false

var _town: Node
var _player: Node
var _pm: Node


func restart() -> void:
	_restart_called = true


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("═══ 《百炼》暂停菜单 + 设置面板 自动验收 ═══")

	# 设置是**玩家真正在用的那一份**（user://settings.cfg）—— 先备份再动，
	# 与 SaveGuard 同样的理由：跑一次回归不能把神的音量调没了
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_bak_settings = FileAccess.get_file_as_bytes(SETTINGS_PATH)

	_town = TOWN.instantiate()
	add_child(_town)
	await _pframes(6)
	_player = _town.get_node("Player")
	_pm = _player.get_node("PauseMenu")

	await _t1_two_new_buttons()
	await _t2_safe_zone_hides_town()
	await _t3_settings_opens_over_pause()
	await _t4_one_esc_closes_one_layer()
	await _t5_volume_reaches_the_bus()
	await _t6_keyboard_works_while_paused()
	await _t7_mute_toggle_and_label()
	await _t8_no_translation_key_leak()
	await _t9_volume_is_persisted()
	await _t10_safe_zone_is_not_about_restart()

	_restore_settings()
	print("")
	print("═══ %d 通过 ／ %d 失败 ═══" % [_pass, _fail])

	Audio.stop_all()
	_town.queue_free()
	await _pframes(2)
	get_tree().paused = false          # 安全网：绝不能带着暂停退出
	get_tree().quit(0 if _fail == 0 else 1)


# ── 工具 ───────────────────────────────────────────────────────

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


## 注入一次**真实按键**。设置面板按的是具体键位（KEY_J / KEY_LEFT），
## 用 InputEventAction 注入它们收不到 —— 事件类型对不上，界面在自己那一层
## 就静默返回了（test_m3 的铁匠铺踩过这个坑）
func _tap_key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ev.strength = 1.0
	Input.parse_input_event(ev)


func _release(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)


func _sp() -> Node:
	return _pm.call("settings_panel")


func _restore_settings() -> void:
	if _had_settings:
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_bak_settings)
			f.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


## 用 Esc 真的开一次暂停菜单（不走 toggle()，那样测不到按键那一段）
func _open_pause_by_key() -> void:
	_press("ui_cancel")
	await _pframes(4)
	_release("ui_cancel")
	await _pframes(2)


func _close_pause_by_key() -> void:
	_press("ui_cancel")
	await _pframes(4)
	_release("ui_cancel")
	await _pframes(2)


# ── 1. 两个新按钮 ──────────────────────────────────────────────

func _t1_two_new_buttons() -> void:
	await _open_pause_by_key()
	var town_btn := _pm.call("button", &"town") as Button
	var set_btn := _pm.call("button", &"settings") as Button
	var rows: Array = _pm.call("row_texts")

	var town_wired: bool = bool(_pm.call("is_wired", town_btn))
	var set_wired: bool = bool(_pm.call("is_wired", set_btn))
	# 「回到城镇」必须**自己说清代价** —— 它跟死亡界面的「返回城镇」是同一件事
	# （换场景 = 世界重置，这一趟不算数），所以文案不能跟那边一模一样、
	# 光写「返回城镇」四个字。这是「不能静默丢进度」那条规矩的落点
	var warns: bool = tr("UI_PAUSE_TOWN") != tr("UI_DEATH_TOWN")
	var no_key_leak := not _has_key_leak(rows)
	# 在副本里（本测试根节点有 restart）这一项**必须看得见**，否则等于白加
	var shown: bool = bool(_pm.call("town_visible"))
	await _close_pause_by_key()

	_check("1", "暂停菜单多了「回到城镇」与「设置」：都接上动作、且回城那行写明了代价",
		town_wired and set_wired and warns and no_key_leak and shown,
		"回城按钮接了动作=%s　设置按钮接了动作=%s　文案「%s」（死亡界面那边是「%s」）=%s　副本里可见=%s　文本无 key 泄漏=%s" % [
			str(town_wired), str(set_wired), tr("UI_PAUSE_TOWN"), tr("UI_DEATH_TOWN"),
			str(warns), str(shown), str(no_key_leak)])


# ── 2. 安全区里不给「回到城镇」 ────────────────────────────────

## 人在城镇里点「回到城镇」等于什么都没发生 ——
## 而**按了看不出效果**是这个项目最不接受的一种失败。
##
## ── 这条断言一开始是【假绿】的，写清楚免得再被骗一次 ──────────
## 第一版判据写成「当前场景能不能 `restart()`」（照死亡界面找当前关卡的做法），
## 测试拿一个光秃秃的 `Node` 冒充城镇 —— 它没有 restart，于是绿了。
## 可**城镇与副本共用同一个根脚本 `stage.gd`**，`restart()` 就在里面：
## 真游戏里那个判据把城镇也判成副本，「回到城镇」在城镇里照样显示。
## 断言绿的理由是错的，产品是坏的。
##
## 现在的判据是**场景文件路径**，所以冒充城镇必须给一个真的城镇路径：
## `Node.scene_file_path` 是可写的（引擎实例化一个 PackedScene 时就是这么设的），
## 直接设成城镇路径就等价于「当前场景是那份 town.tscn」。
## 另外**直接验规则本身**的两个分支 —— 端到端那一头没法真的换场景
## （`change_scene_to_file` 会把测试自己整个换掉，测试当场就死）
func _t2_safe_zone_hides_town() -> void:
	var real_scene := get_tree().current_scene

	# 规则本身：城镇算安全区，副本不算
	var rule_ok: bool = bool(_pm.call("is_safe_zone", "res://scenes/stages/town.tscn")) \
		and not bool(_pm.call("is_safe_zone", "res://scenes/stages/lichang.tscn"))

	# 副本里（本测试场景不是城镇）→ 该看得见
	await _open_pause_by_key()
	var in_dungeon: bool = bool(_pm.call("town_visible"))
	var dungeon_rows: int = (_pm.call("row_texts") as Array).size()
	await _close_pause_by_key()

	# 冒充城镇。挂 **root** 下：`current_scene` 的 setter 要求父节点就是 root，
	# 否则一句 `Condition ... is true` 静默拒绝（赋值不生效、只留一行 ERROR）
	var fake_town := Node.new()
	fake_town.name = "FakeTown"
	fake_town.scene_file_path = "res://scenes/stages/town.tscn"
	get_tree().root.add_child(fake_town)
	get_tree().current_scene = fake_town

	await _open_pause_by_key()
	var in_town: bool = bool(_pm.call("town_visible"))
	var town_rows: int = (_pm.call("row_texts") as Array).size()
	await _close_pause_by_key()

	get_tree().current_scene = real_scene           # 还回去，后面几条还要用
	fake_town.queue_free()
	await _pframes(2)

	_check("2", "安全区（城镇）里不显示「回到城镇」，副本里显示；光标行数跟着少一行",
		rule_ok and in_dungeon and not in_town and dungeon_rows == 5 and town_rows == 4,
		"规则（城镇=安全区、砺场≠安全区）=%s　副本里可见=%s（%d 行）　城镇里可见=%s（%d 行，应该是 4 —— 藏起来的行光标也不该停上去）" % [
			str(rule_ok), str(in_dungeon), dungeon_rows, str(in_town), town_rows])


# ── 3~4. 设置叠在暂停菜单上；Esc 只关一层 ────────────────────

func _t3_settings_opens_over_pause() -> void:
	await _open_pause_by_key()
	var paused_before: bool = get_tree().paused
	var set_btn := _pm.call("button", &"settings") as Button
	set_btn.pressed.emit()
	await _pframes(3)
	var sp := _sp()
	var sp_open: bool = bool(sp.call("is_open"))
	var pm_still: bool = bool(_pm.call("is_open"))
	var still_paused: bool = get_tree().paused
	# 面板里的读数得跟资源对得上（打开时就该是当前值，不是默认值）
	var rows: Array = sp.call("row_texts")
	var shown: String = "　".join(rows)
	# 先存进局部变量再拼 detail —— 这里求值发生在下面关掉之后，
	# 直接写过去会打出一句与事实相反的话（这个坑踩过）
	_check("3", "点「设置」把面板叫出来：暂停菜单还在、游戏仍然暂停",
		paused_before and sp_open and pm_still and still_paused,
		"打开前已暂停=%s　设置面板开着=%s　暂停菜单还开着=%s　仍然暂停=%s　面板三行：%s" % [
			str(paused_before), str(sp_open), str(pm_still), str(still_paused), shown])


## **一下 Esc 只关一层。**
## 设置面板叠在暂停菜单上面，两个节点都在 `_unhandled_input` 里等 Esc ——
## 设置面板先关掉自己之后，暂停菜单再读 `is_open()` 已经是 false，
## 于是同一下 Esc 把两层一起关掉、游戏直接跑起来。
## 这条断言盯的就是那个瞬间（做法是留一个「刚刚关掉的帧号」，见 settings_panel.close）
func _t4_one_esc_closes_one_layer() -> void:
	var sp := _sp()
	_tap_key(KEY_ESCAPE)
	await _pframes(4)
	var sp_closed: bool = not bool(sp.call("is_open"))
	var pm_open: bool = bool(_pm.call("is_open"))
	var still_paused: bool = get_tree().paused
	await _close_pause_by_key()
	var all_closed: bool = (not bool(_pm.call("is_open"))) and (not get_tree().paused)

	_check("4", "设置面板开着时按 Esc：只关设置这一层，暂停菜单与暂停状态都留着",
		sp_closed and pm_open and still_paused and all_closed,
		"设置关掉=%s　暂停菜单还开着=%s　仍然暂停=%s　再按一次 Esc 才全关=%s" % [
			str(sp_closed), str(pm_open), str(still_paused), str(all_closed)])


# ── 5. 音量真的落到引擎上 ──────────────────────────────────────

## 断言要验的是**总线上的 dB**，不是 `GameSettings.sfx_volume` 这个变量 ——
## 变量改了、总线没动的话，玩家听到的音量一点没变，而断言看着是绿的
func _t5_volume_reaches_the_bus() -> void:
	var orig_bgm := GameSettings.bgm_volume
	var orig_sfx := GameSettings.sfx_volume

	var sfx_bus := AudioServer.get_bus_index(GameSettings.SFX_BUS)
	var bgm_bus := AudioServer.get_bus_index(GameSettings.BGM_BUS)

	GameSettings.set_sfx_volume(0.5)
	var half := GameSettings.bus_db(GameSettings.SFX_BUS)
	GameSettings.set_bgm_volume(0.25)
	var quarter := GameSettings.bus_db(GameSettings.BGM_BUS)
	GameSettings.set_sfx_volume(0.0)
	var muted := GameSettings.bus_db(GameSettings.SFX_BUS)
	GameSettings.set_sfx_volume(1.0)
	var full := GameSettings.bus_db(GameSettings.SFX_BUS)

	var half_ok := absf(half - linear_to_db(0.5)) < 0.02
	var quarter_ok := absf(quarter - linear_to_db(0.25)) < 0.02
	# 归零必须夹到 MUTE_DB，不能是 linear_to_db(0) = -inf
	var muted_ok := is_equal_approx(muted, GameSettings.MUTE_DB)
	var full_ok := absf(full) < 0.02

	# 播放池真的挂在那条总线上吗（挂错了的话音量条根本管不着它）
	var audio_bus_ok := true
	for p in Audio.get_children():
		if p is AudioStreamPlayer and (p as AudioStreamPlayer).bus != GameSettings.SFX_BUS:
			audio_bus_ok = false

	GameSettings.set_bgm_volume(orig_bgm)
	GameSettings.set_sfx_volume(orig_sfx)

	_check("5", "音量落到音频总线上（不是只改了个变量）；播放池挂在「音效」总线上",
		sfx_bus >= 0 and bgm_bus >= 0 and half_ok and quarter_ok and muted_ok \
			and full_ok and audio_bus_ok,
		"音效 50%%→%.2fdB（期望 %.2f）　音乐 25%%→%.2fdB（期望 %.2f）　归零→%.0fdB（期望 %.0f，不是 -inf）　满→%.2fdB　播放池挂对总线=%s" % [
			half, linear_to_db(0.5), quarter, linear_to_db(0.25),
			muted, GameSettings.MUTE_DB, full, str(audio_bus_ok)])


# ── 6~7. 暂停中键盘可用；静音开关 ──────────────────────────────

## 「暂停的节点观察不到暂停期间的变化」—— 这个坑项目里踩过。
## 设置面板是 `process_mode = ALWAYS`，所以**暂停中也要收得到键盘**。
## 这条在真暂停下注入真实按键：光标要动、音量要动，而暂停状态不能被碰
func _t6_keyboard_works_while_paused() -> void:
	await _open_pause_by_key()
	(_pm.call("button", &"settings") as Button).pressed.emit()
	await _pframes(3)
	var sp := _sp()
	GameSettings.set_sfx_volume(0.6)
	await _pframes(1)

	var before_vol := GameSettings.sfx_volume
	var before_db := GameSettings.bus_db(GameSettings.SFX_BUS)
	_tap_key(KEY_DOWN)                     # 光标：背景音乐 → 音效
	await _pframes(2)
	var cur := int(sp.call("cursor"))
	_tap_key(KEY_LEFT)                     # 调小一格
	await _pframes(2)
	_tap_key(KEY_LEFT)
	await _pframes(2)
	var after_vol := GameSettings.sfx_volume
	var after_db := GameSettings.bus_db(GameSettings.SFX_BUS)
	var still_paused: bool = get_tree().paused

	_tap_key(KEY_ESCAPE)
	await _pframes(3)
	await _close_pause_by_key()

	_check("6", "设置面板在**真暂停**下收得到键盘：光标动、音量跟着变，而暂停不被碰",
		cur == 1 and after_vol < before_vol and after_db < before_db and still_paused,
		"光标 0→%d（期望 1）　音量 %.2f→%.2f　总线 %.2f→%.2fdB　期间仍然暂停=%s" % [
			cur, before_vol, after_vol, before_db, after_db, str(still_paused)])


## J 在音量行上是静音开关。**不能按了没反应** ——
## 所以除了数值，还要求那一行写出来「静音」（不是「0%」：
## 对玩家来说「调小了」和「确定不想听」不是一回事）
func _t7_mute_toggle_and_label() -> void:
	await _open_pause_by_key()
	(_pm.call("button", &"settings") as Button).pressed.emit()
	await _pframes(3)
	var sp := _sp()
	GameSettings.set_sfx_volume(0.4)
	_tap_key(KEY_DOWN)                     # 光标移到「音效」
	await _pframes(2)

	_tap_key(KEY_J)                        # 静音
	await _pframes(2)
	var muted_vol := GameSettings.sfx_volume
	var muted_db := GameSettings.bus_db(GameSettings.SFX_BUS)
	var muted_label: String = str((sp.call("row_texts") as Array)[1])

	_tap_key(KEY_J)                        # 再按一次恢复
	await _pframes(2)
	var back_vol := GameSettings.sfx_volume
	var back_db := GameSettings.bus_db(GameSettings.SFX_BUS)

	_tap_key(KEY_ESCAPE)
	await _pframes(3)
	await _close_pause_by_key()

	_check("7", "J 在音量行上是静音开关：归零夹到 MUTE_DB、那一行写出「静音」，再按恢复",
		is_zero_approx(muted_vol) and is_equal_approx(muted_db, GameSettings.MUTE_DB) \
			and muted_label.contains(tr("UI_SETTINGS_MUTED")) \
			and absf(back_vol - 0.4) < 0.001 and absf(back_db - linear_to_db(0.4)) < 0.05,
		"静音后 %.2f（总线 %.0fdB，期望 %.0f）　那一行=\"%s\"　再按恢复 %.2f（总线 %.2fdB）" % [
			muted_vol, muted_db, GameSettings.MUTE_DB, muted_label, back_vol, back_db])


# ── 8. 翻译泄漏探针 ────────────────────────────────────────────

## 漏翻 / 拼错 key **不报任何错**，界面上就显示 "UI_PAUSE_TOWN" 这种字样 ——
## 只有截图和断言抓得到。暂停菜单与设置面板都是这一版新写的文本，必须过一遍
func _t8_no_translation_key_leak() -> void:
	await _open_pause_by_key()
	var pm_rows: Array = _pm.call("row_texts")
	(_pm.call("button", &"settings") as Button).pressed.emit()
	await _pframes(3)
	var sp_rows: Array = _sp().call("row_texts")
	var sp_nodes := _collect_labels(_sp())
	_tap_key(KEY_ESCAPE)
	await _pframes(3)
	await _close_pause_by_key()

	var leaks := _find_key_leaks(pm_rows + sp_rows + sp_nodes)
	_check("8", "暂停菜单与设置面板上都不出现翻译 key 本身（漏翻是静默失败，只能这么抓）",
		leaks.is_empty(),
		"扫了 %d 段文本　泄漏的 key：%s" % [
			pm_rows.size() + sp_rows.size() + sp_nodes.size(),
			"无" if leaks.is_empty() else ", ".join(leaks)])


func _has_key_leak(texts: Array) -> bool:
	return not _find_key_leaks(texts).is_empty()


func _find_key_leaks(texts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.new()
	re.compile("(UI|PANEL|HUD|ITEM|SLOT|STAT)_[A-Z_]+")
	for t in texts:
		for m in re.search_all(str(t)):
			out.append(m.get_string())
	return out


func _collect_labels(node: Node) -> Array:
	var out: Array = []
	if node is Label:
		out.append((node as Label).text)
	if node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		out.append_array(_collect_labels(c))
	return out


# ── 9. 音量落盘 ────────────────────────────────────────────────

## 不落盘的话，重启游戏音量就白调了 —— 而这件事**只有重开一次才知道**，
## 所以这里直接读文件，别等下次运行
func _t9_volume_is_persisted() -> void:
	GameSettings.set_bgm_volume(0.35)
	GameSettings.set_sfx_volume(0.65)
	var cfg := ConfigFile.new()
	var loaded := cfg.load(SETTINGS_PATH)
	var bgm := float(cfg.get_value(GameSettings.AUDIO_SECTION, "bgm", -1.0))
	var sfx := float(cfg.get_value(GameSettings.AUDIO_SECTION, "sfx", -1.0))
	var lang := str(cfg.get_value(GameSettings.CONFIG_SECTION, "language", ""))
	_check("9", "音量与语言都写进了 user://settings.cfg（重启之后还在）",
		loaded == OK and absf(bgm - 0.35) < 0.001 and absf(sfx - 0.65) < 0.001 \
			and lang == GameSettings.language,
		"读文件：音乐 %.2f（期望 0.35）　音效 %.2f（期望 0.65）　语言 %s" % [bgm, sfx, lang])


# ── 10. 给「假绿」事故留的守门人 ────────────────────────────────

## **这一条存在的唯一理由是：上一版就是假的绿。**
##
## 第一版把「是不是城镇」判成「当前场景能不能 `restart()`」（照死亡界面找当前关卡的做法），
## 断言拿一个光秃秃的 `Node` 冒充城镇，它没有 restart，于是绿了。
## 可**城镇与副本共用同一个根脚本 `stage.gd`**，`restart()` 就在里头 ——
## 真游戏里那个判据把城镇也判成副本，「回到城镇」在城镇里照常显示。
##
## 这里直接把两个事实同时钉住：**城镇确实有 restart()，但它仍然算安全区**。
## 谁要是把 `is_safe_zone` 改回看方法名，这条当场红
func _t10_safe_zone_is_not_about_restart() -> void:
	var town := TOWN.instantiate()
	var town_path: String = town.scene_file_path
	var town_has_restart: bool = town.has_method("restart")
	town.free()

	var dungeon_path := "res://scenes/stages/lichang.tscn"
	var town_safe: bool = bool(_pm.call("is_safe_zone", town_path))
	var dungeon_safe: bool = bool(_pm.call("is_safe_zone", dungeon_path))

	_check("10", "「是不是城镇」不能靠「有没有 restart()」判 —— 两者共用同一个根脚本",
		town_has_restart and town_safe and not dungeon_safe,
		"城镇带 restart()=%s，却仍算安全区=%s；砺场（同一个根脚本）不算安全区=%s" % [
			str(town_has_restart), str(town_safe), str(dungeon_safe)])
