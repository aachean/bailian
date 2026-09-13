extends CanvasLayer
## 对话框（造梦西游式）：屏幕底部一条，说话人 + 台词 + 「J 继续」。
##
## ── 打开时真暂停 ──────────────────────────────────────────────
## 剧情期间不该被怪打。与装备背包、暂停菜单同一套机制
## （process_mode = ALWAYS + 暂停场景树）—— 这是第三次用同一个套路，
## 说明它已经成了这个项目里「模态界面」的标准做法。
##
## ── 打字机 ────────────────────────────────────────────────────
## 台词逐字显出来。按 J：没显完就立刻显完，显完了才翻页 ——
## 急着看下一句的玩家不该被逼着等字打完。这是文字冒险的默认手感，不用发明新的。

signal finished(data: DialogueData)

## 打字机速度：每帧显几个字（换算成 60fps 基准，所以和物理帧率无关）
const CHARS_PER_FRAME := 0.8

var _data: DialogueData = null
var _index := 0
var _progress := 0.0
var _open := false
## 对话期间把 HUD 收起来 —— 技能栏正好在左下角，跟对话框抢同一块地方；
## 剧情过场也不该让血条和经验条挤在旁边（造梦西游对话时 HUD 也是淡出的）
var _hud: CanvasLayer = null

@onready var _root: Control = $Root
@onready var _speaker: Label = $Root/Panel/Speaker
@onready var _text: Label = $Root/Panel/Text
@onready var _hint: Label = $Root/Panel/Hint


func _ready() -> void:
	add_to_group("dialogue_box")
	_root.visible = false
	_hud = get_parent().get_node_or_null("HUD")


func is_open() -> bool:
	return _open


## 开始一段对话。已经开着的话直接顶掉（不结算旧的）
func open(data: DialogueData) -> void:
	if data == null or not data.has_content():
		return
	_data = data
	_index = 0
	_progress = 0.0
	_open = true
	_root.visible = true
	if _hud != null:
		_hud.visible = false
	get_tree().paused = true
	_speaker.text = tr(data.speaker_key)
	_hint.text = tr("UI_DLG_HINT")
	_show_line()


func _process(delta: float) -> void:
	if not _open:
		return
	if _is_typing():
		_progress += CHARS_PER_FRAME * delta * 60.0
		_text.visible_characters = mini(int(_progress), _text.text.length())


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("attack") or event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()


func _advance() -> void:
	if _is_typing():
		_text.visible_characters = -1      # 先显完这一句
		return
	if _index + 1 < _data.lines.size():
		_index += 1
		_show_line()
		return
	_close()


func _close() -> void:
	var d := _data
	_open = false
	_root.visible = false
	if _hud != null:
		_hud.visible = true
	get_tree().paused = false
	_data = null
	_reward(d)
	finished.emit(d)


## 赠礼：记过 flag 就不再给。先记后给 —— 顺序反了的话，
## 万一加进背包之后崩了，下次还会再给一次
func _reward(d: DialogueData) -> void:
	if d == null or d.give_item.is_empty() or d.flag == &"":
		return
	if PlayerState.has_flag(d.flag):
		return
	if PlayerState.add_item(d.give_item):
		PlayerState.set_flag(d.flag)


func _show_line() -> void:
	_text.text = tr(_data.lines[_index])
	_text.visible_characters = 0
	_progress = 0.0


func _is_typing() -> bool:
	return _text.visible_characters >= 0 and _text.visible_characters < _text.text.length()
