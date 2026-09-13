extends Node
## 全局设置。目前只有一项：界面语言。
##
## 两个刻意的取舍：
##   1. 默认固定中文，**不跟随系统语言**。游戏的中文文案是主线，英文是翻译；
##      跟随系统会让英文系统的玩家看到一份完成度更低的界面。语言由玩家自己选。
##   2. 设置界面还没做。现在只留这一个入口 `set_language()`，
##      加上 `language_changed` 信号，等做设置界面时直接调用即可，界面自己刷新。
##
## 存档位置：user://settings.cfg

## 语言真的换了才发（重复设置同一个语言不发）
signal language_changed(locale: String)

## 支持的语言。值是语言自称 —— 语言选择器里应该显示"中文 / English"，
## 而不是把语言名再翻译一遍（把"英语"翻译成"English"是没用的）。
const SUPPORTED := {
	"zh_CN": "中文",
	"en": "English",
}

const DEFAULT_LOCALE := "zh_CN"
const CONFIG_PATH := "user://settings.cfg"
const CONFIG_SECTION := "ui"

var language: String = DEFAULT_LOCALE


func _ready() -> void:
	_load_config()
	_apply(language)


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


func _apply(code: String) -> void:
	TranslationServer.set_locale(code)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	var saved := str(cfg.get_value(CONFIG_SECTION, "language", DEFAULT_LOCALE))
	if SUPPORTED.has(saved):
		language = saved


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(CONFIG_SECTION, "language", language)
	cfg.save(CONFIG_PATH)
