extends CanvasLayer
## 设置面板：**背景音乐 / 音效 / 语言**。
##
## ── 为什么是一个独立场景，而不是塞进暂停菜单 ──────────────────
## 它有两个入口：游戏里（暂停菜单）和主菜单。用**同一份界面**，
## 否则迟早会漂成两套 —— 「主菜单能调音量、游戏里不能」，
## 或者两边默认值不一样。以后再加通用配置也只加一个地方。
##
## ── 为什么挂 CanvasLayer + `process_mode = ALWAYS` ────────────
## 从暂停菜单进来时游戏是**真暂停**的。节点一旦被暂停就收不到输入，
## 也观察不到暂停期间发生的变化 —— 界面会变成一张画（这个坑项目里踩过：
## 「暂停的节点观察不到暂停期间的变化」，先问「谁在这期间不跑」）。
## 与 HUD / 铁匠铺 / 死亡界面同一套约定。
##
## ── 暂停归调用方，本面板不碰 ──────────────────────────────────
## 它只是叠在暂停菜单（或主菜单）上面。关掉它之后该继续停着还是该跑，
## 是**调用方**的事 —— 这跟 `hud.close_all_panels()` 那次教训同源：
## 让路只管可见性，暂停归调用方。在这里多写一句 `paused = false`，
## 就会变成「关设置的同时把游戏也放跑了」。
##
## ── 关掉时留一个帧号印记 ──────────────────────────────────────
## `closed_at_frame()` 是给暂停菜单读的。原因见 `close()`。

const ROW_BGM := 0
const ROW_SFX := 1
const ROW_LANG := 2
## 键盘一次调多少（线性音量）。与滑条的 step 对齐
const STEP := 0.05
## 从静音恢复时给的值（上次调过的值丢了的话）
const UNMUTE_FALLBACK := 0.8

const CURSOR_MARK := "▶ "
const INDENT := "　"        # 全角空格：与光标标记同宽，换行不跳

const DIM := Color(0.6, 0.58, 0.54, 1)
const NORMAL := Color(0.9, 0.88, 0.84, 1)
const GOLD := Color(0.93, 0.84, 0.6, 1)

var _cursor := ROW_BGM
## 「界面正在把资源里的值写进控件」—— 防回环：
## 滑条变化 → 写设置 → 发信号 → 刷新滑条 → 又变化 …… 一圈圈转
var _syncing := false
## 上一次关掉的帧号。**给暂停菜单读的**，见 `close()`
var _closed_frame := -1
## 静音前记下的值，好恢复
var _last_bgm := GameSettings.DEFAULT_BGM
var _last_sfx := GameSettings.DEFAULT_SFX

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Panel/Title
@onready var _bgm_mark: Label = $Root/Panel/Rows/BgmRow/Mark
@onready var _bgm_name: Label = $Root/Panel/Rows/BgmRow/Name
@onready var _bgm_slider: HSlider = $Root/Panel/Rows/BgmRow/Slider
@onready var _bgm_value: Label = $Root/Panel/Rows/BgmRow/Value
@onready var _sfx_mark: Label = $Root/Panel/Rows/SfxRow/Mark
@onready var _sfx_name: Label = $Root/Panel/Rows/SfxRow/Name
@onready var _sfx_slider: HSlider = $Root/Panel/Rows/SfxRow/Slider
@onready var _sfx_value: Label = $Root/Panel/Rows/SfxRow/Value
@onready var _lang_mark: Label = $Root/Panel/Rows/LangRow/Mark
@onready var _lang_name: Label = $Root/Panel/Rows/LangRow/Name
@onready var _lang_btn: Button = $Root/Panel/Rows/LangRow/Lang
@onready var _hint: Label = $Root/Panel/Hint


func _ready() -> void:
	_root.visible = false
	_bgm_slider.value_changed.connect(_on_bgm_slider)
	_sfx_slider.value_changed.connect(_on_sfx_slider)
	_bgm_slider.drag_ended.connect(_on_bgm_drag_ended)
	_sfx_slider.drag_ended.connect(_on_sfx_drag_ended)
	_lang_btn.pressed.connect(_cycle_language)
	if not GameSettings.language_changed.is_connected(_on_language_changed):
		GameSettings.language_changed.connect(_on_language_changed)
	if not GameSettings.audio_changed.is_connected(_on_audio_changed):
		GameSettings.audio_changed.connect(_on_audio_changed)
	refresh()


# ── 开关 ───────────────────────────────────────────────────────

func is_open() -> bool:
	return _root.visible


## 上一次 `close()` 发生在哪一帧。
##
## **暂停菜单必须读它。** 设置面板是叠在暂停菜单上面的，两个节点都在
## `_unhandled_input` 里等 Esc：设置面板先收到、关掉自己之后，
## 暂停菜单再读 `is_open()` 已经是 false —— 于是**同一下 Esc 把两层一起关掉**。
## 这类「成败取决于两行的先后顺序」的坑项目里踩过（见 hud.close_all_panels），
## 所以这里不留猜测空间：关掉的那一刻留个帧号，暂停菜单对着比一下就行。
func closed_at_frame() -> int:
	return _closed_frame


func open() -> void:
	_cursor = ROW_BGM
	_root.visible = true
	refresh()


func close() -> void:
	_closed_frame = Engine.get_process_frames()
	_root.visible = false


# ── 输入 ───────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		# 吃掉这个事件：同一帧里别让下面那层（暂停菜单）也吃到
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				_move(-1)
			KEY_DOWN, KEY_S:
				_move(1)
			KEY_LEFT, KEY_A:
				_nudge(-STEP)
			KEY_RIGHT, KEY_D:
				_nudge(STEP)
			KEY_J, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate()
			_:
				return
		get_viewport().set_input_as_handled()


func _move(dir: int) -> void:
	_cursor = wrapi(_cursor + dir, 0, 3)
	refresh()


## ←→ 调整。语言那一行上「调整」就是换语言（没有中间量可调）
func _nudge(delta: float) -> void:
	match _cursor:
		ROW_BGM:
			GameSettings.set_bgm_volume(GameSettings.bgm_volume + delta)
		ROW_SFX:
			GameSettings.set_sfx_volume(GameSettings.sfx_volume + delta)
			_preview_sfx()
		ROW_LANG:
			_cycle_language()


## J 键。音量行上 = 静音开关，语言行上 = 换语言。
## **刻意不给「按了没反应」留位置** —— 那正是这个项目最不接受的一种失败
func _activate() -> void:
	match _cursor:
		ROW_BGM, ROW_SFX:
			_toggle_mute()
		ROW_LANG:
			_cycle_language()


func _toggle_mute() -> void:
	if _cursor == ROW_BGM:
		if GameSettings.bgm_volume > 0.001:
			_last_bgm = GameSettings.bgm_volume
			GameSettings.set_bgm_volume(0.0)
		else:
			GameSettings.set_bgm_volume(_last_bgm if _last_bgm > 0.001 else UNMUTE_FALLBACK)
		return
	if GameSettings.sfx_volume > 0.001:
		_last_sfx = GameSettings.sfx_volume
		GameSettings.set_sfx_volume(0.0)
	else:
		GameSettings.set_sfx_volume(_last_sfx if _last_sfx > 0.001 else UNMUTE_FALLBACK)
		_preview_sfx()


func _cycle_language() -> void:
	var codes := GameSettings.SUPPORTED.keys()
	var i := codes.find(GameSettings.language)
	GameSettings.set_language(str(codes[(i + 1) % codes.size()]))


## 调音效音量时**当场给一声**。
## 不给的话就是在调一个听不见的东西 —— 玩家只能靠数字猜。
## 背景音乐那行没有可试听的对象（游戏里还没有 BGM），刻意不响，
## 也不假装响一声
func _preview_sfx() -> void:
	Audio.play(&"pickup")


# ── 控件回调 ───────────────────────────────────────────────────

func _on_bgm_slider(v: float) -> void:
	if _syncing:
		return
	GameSettings.set_bgm_volume(v / 100.0)


func _on_sfx_slider(v: float) -> void:
	if _syncing:
		return
	GameSettings.set_sfx_volume(v / 100.0)


func _on_bgm_drag_ended(_changed: bool) -> void:
	pass          # BGM 没有可试听的对象，这里刻意什么都不做


func _on_sfx_drag_ended(_changed: bool) -> void:
	_preview_sfx()


## 参数必须留着：Godot 按参数个数严格匹配信号连接，少一个会「连上了但一调用就报错」，
## 界面静默不刷新（M1 的语言切换用例抓到过这个家族）
func _on_language_changed(_locale: String = "") -> void:
	refresh()


func _on_audio_changed(_bgm: float, _sfx: float) -> void:
	refresh()


# ── 绘制 ───────────────────────────────────────────────────────

func refresh() -> void:
	_title.text = tr("UI_SETTINGS_TITLE")
	_bgm_name.text = tr("UI_SETTINGS_BGM")
	_sfx_name.text = tr("UI_SETTINGS_SFX")
	_lang_name.text = tr("UI_SETTINGS_LANGUAGE")
	_hint.text = tr("UI_SETTINGS_HINT")
	# 两头带箭头：截图上一眼就看得出这一行是**能改的**（与 ←→ / J 的提示呼应）。
	# 光写「中文」与旁边的静态文字长得一模一样，玩家不会去点它
	_lang_btn.text = "◀　%s　▶" % tr(GameSettings.SUPPORTED[GameSettings.language])

	_bgm_mark.text = CURSOR_MARK if _cursor == ROW_BGM else INDENT
	_sfx_mark.text = CURSOR_MARK if _cursor == ROW_SFX else INDENT
	_lang_mark.text = CURSOR_MARK if _cursor == ROW_LANG else INDENT
	_bgm_name.modulate = GOLD if _cursor == ROW_BGM else NORMAL
	_sfx_name.modulate = GOLD if _cursor == ROW_SFX else NORMAL
	_lang_name.modulate = GOLD if _cursor == ROW_LANG else NORMAL

	_syncing = true
	_bgm_slider.value = round(GameSettings.bgm_volume * 100.0)
	_sfx_slider.value = round(GameSettings.sfx_volume * 100.0)
	_syncing = false
	_bgm_value.text = _percent(GameSettings.bgm_volume)
	_sfx_value.text = _percent(GameSettings.sfx_volume)


## 音量写成百分比。**0 写「静音」而不是「0%」** ——
## 对玩家来说那两句话不是一回事（0% 可能只是「调小了」，静音是「确定不想听」）
func _percent(v: float) -> String:
	if v <= 0.001:
		return tr("UI_SETTINGS_MUTED")
	return "%d%%" % int(round(v * 100.0))


# ── 给断言看的 ─────────────────────────────────────────────────

## 三行现在显示成什么（拼在一起，给翻译泄漏探针扫）
func row_texts() -> Array[String]:
	return [
		"%s %s" % [_bgm_name.text, _bgm_value.text],
		"%s %s" % [_sfx_name.text, _sfx_value.text],
		"%s %s" % [_lang_name.text, _lang_btn.text],
	]


## 光标停在第几行（0 起）
func cursor() -> int:
	return _cursor
