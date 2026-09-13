extends Label
## 左上角的操作提示。
##
## 文案全部来自 data/i18n/ui.csv，按 key 取 —— 不在场景里写死，
## 也不把中文直接编码进代码。换语言时整块重排一次，因为中英文长度差很多。

## 显示顺序。key 必须存在于 data/i18n/ui.csv，写错了会直接显示成 key 本身。
const LINES := [
	"UI_HINT_TITLE",
	"UI_HINT_MOVE",
	"UI_HINT_JUMP",
	"UI_HINT_ATTACK",
	"UI_HINT_DODGE",
	"UI_HINT_ENEMY",
]


func _ready() -> void:
	# 文本由这里统一 tr()，关掉 Label 自己的自动翻译，否则会被译两遍
	auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED
	if not GameSettings.language_changed.is_connected(_refresh):
		GameSettings.language_changed.connect(_refresh)
	_refresh()


## 参数是 language_changed 带过来的语言码，这里用不上 —— 当前语言直接问
## TranslationServer。但参数**必须留着**：Godot 连信号时按参数个数严格匹配，
## 少一个就会「连接成功但调用时报错」，界面静默不刷新。
func _refresh(_locale: String = "") -> void:
	var lines := PackedStringArray()
	for key in LINES:
		lines.append(tr(key))
	text = "\n".join(lines)
