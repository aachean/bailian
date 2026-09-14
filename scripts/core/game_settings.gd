extends Node
## 全局设置：**界面语言 + 背景音乐音量 + 音效音量**。
##
## ── 为什么语言默认固定中文，不跟随系统 ────────────────────────
## 游戏的中文文案是主线，英文是翻译；跟随系统会让英文系统的玩家
## 看到一份完成度更低的界面。语言由玩家自己选。
##
## ── 音量为什么走音频总线，而不是给每个 player 乘系数 ──────────
## 总线是引擎自己做的乘法：`Audio` 那边四声各自的响度差（空挥 < 命中 <
## 拾取 < 受击）写在播放端、管住「这几声之间的比例」；总线管住
## 「整体多大」—— 两件事分开，调其中一个不会把另一个碰坏。
## 给每个 player 乘一个全局系数也能用，但每加一声都要记得乘，
## 漏一个就是「这一声不受音量条控制」的静默 bug。
##
## ── 总线是程序化建的，没有 default_bus_layout.tres ────────────
## 手写那个 .tres 要记住每个 props 的名字与顺序，写错**不报错**、
## 只是总线没出来（这个项目在「静默失败」上吃过太多亏）。
## `_ensure_buses()` 每次启动都补一遍，缺了就加，幂等。
##
## 存档位置：user://settings.cfg

## 语言真的换了才发（重复设置同一个语言不发）
signal language_changed(locale: String)
## 音量变了。带当前值（0~1 线性）—— 设置界面靠它刷新，不用自己记一份
signal audio_changed(bgm: float, sfx: float)

## 支持的语言。值是语言自称 —— 语言选择器里应该显示"中文 / English"，
## 而不是把语言名再翻译一遍（把"英语"翻译成"English"是没用的）。
const SUPPORTED := {
	"zh_CN": "中文",
	"en": "English",
}

const DEFAULT_LOCALE := "zh_CN"
const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "ui"
const AUDIO_SECTION := "audio"

## 背景音乐总线。现在**还没有任何东西挂上去**（游戏里没有 BGM 素材）——
## 先把总线与设置项备好，加音乐时只要让播放器挂到这条总线上，
## 音量条当场就管得住它，不用回来改设置界面
const BGM_BUS := &"BGM"
## 音效总线。`Audio` 的播放池挂在这条上
const SFX_BUS := &"SFX"
## 音量归零时给总线的值。**不能用 linear_to_db(0)** —— 那是 -inf，
## 有些平台会把它当非法值，宁可夹到一个足够低的确定值
const MUTE_DB := -80.0

const DEFAULT_BGM := 0.8
const DEFAULT_SFX := 1.0

var language: String = DEFAULT_LOCALE
var bgm_volume: float = DEFAULT_BGM
var sfx_volume: float = DEFAULT_SFX


func _ready() -> void:
	_load_config()
	_ensure_buses()
	_apply(language)
	_apply_audio()


# ── 语言 ───────────────────────────────────────────────────────

## 设置界面调这个。未知的语言码会被拒绝并留下警告，不会静默改写。
func set_language(code: String) -> void:
	if not SUPPORTED.has(code):
		push_warning("GameSettings: 不支持的语言 %s" % code)
		return
	if code == language:
		return
	language = code
	_apply(code)
	_save_config()
	language_changed.emit(code)


## 供设置界面列出可选项：[{"code": "zh_CN", "name": "中文"}, ...]
func options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for code in SUPPORTED:
		out.append({"code": code, "name": SUPPORTED[code]})
	return out


# ── 音量 ───────────────────────────────────────────────────────

## 设背景音乐音量（0~1 线性）。越界一律夹回来，不静默写进档里
func set_bgm_volume(v: float) -> void:
	var nv := clampf(v, 0.0, 1.0)
	if is_equal_approx(nv, bgm_volume):
		return
	bgm_volume = nv
	_apply_audio()
	_save_config()
	audio_changed.emit(bgm_volume, sfx_volume)


## 设音效音量（0~1 线性）
func set_sfx_volume(v: float) -> void:
	var nv := clampf(v, 0.0, 1.0)
	if is_equal_approx(nv, sfx_volume):
		return
	sfx_volume = nv
	_apply_audio()
	_save_config()
	audio_changed.emit(bgm_volume, sfx_volume)


## 线性音量 → 总线用的 dB
func volume_db(v: float) -> float:
	return MUTE_DB if v <= 0.001 else linear_to_db(v)


## 某条总线现在实际的音量（dB）。**给断言用的读数口** ——
## 断言要验的是「音量真的落到引擎上了」，不是「变量改了」
func bus_db(bus_name: StringName) -> float:
	var i := AudioServer.get_bus_index(bus_name)
	return 0.0 if i < 0 else AudioServer.get_bus_volume_db(i)


# ── 内部 ───────────────────────────────────────────────────────

func _apply(code: String) -> void:
	TranslationServer.set_locale(code)


func _apply_audio() -> void:
	_set_bus_db(BGM_BUS, volume_db(bgm_volume))
	_set_bus_db(SFX_BUS, volume_db(sfx_volume))


func _set_bus_db(bus_name: StringName, db: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, db)


## 缺哪条总线就补哪条。幂等，每次启动跑一遍
func _ensure_buses() -> void:
	for bus_name in [BGM_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	var saved := str(cfg.get_value(CONFIG_SECTION, "language", DEFAULT_LOCALE))
	if SUPPORTED.has(saved):
		language = saved
	bgm_volume = clampf(float(cfg.get_value(AUDIO_SECTION, "bgm", DEFAULT_BGM)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value(AUDIO_SECTION, "sfx", DEFAULT_SFX)), 0.0, 1.0)


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(CONFIG_SECTION, "language", language)
	cfg.set_value(AUDIO_SECTION, "bgm", bgm_volume)
	cfg.set_value(AUDIO_SECTION, "sfx", sfx_volume)
	cfg.save(CONFIG_PATH)
