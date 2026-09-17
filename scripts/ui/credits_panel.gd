extends CanvasLayer
## 素材致谢面板（**只读**）。
##
## ── 为什么必须有这一块 ────────────────────────────────────────
## 村民素材（CraftPix「Villagers Sprite Sheets Pixel Art Pack」）是 **OGA-BY 3.0**，
## 该许可要求署名出现在**玩家看得到的地方**；其余素材虽只要求「感谢即可」，一并列出。
## **这是授权义务，不是装饰** —— 完整凭据（许可原文）在仓库 `assets/CREDITS.md`。
##
## ── 人名 / 作品名 / 链接刻意不进 i18n ─────────────────────────
## 授权要求的是那几行字**原样**出现在玩家面前，把署名翻译过去反而失真。
## 只有标题、说明、按钮走 csv。
##
## ── 关掉时留帧号印记 ─────────────────────────────────────────
## 与设置面板同一套约定：叠在上面的面板先收到 Esc、关掉自己之后，
## 下面那层再读 `is_open()` 已经是 false —— **同一下 Esc 关两层**。
##
## ── 打开的那一帧不响应关闭 ────────────────────────────────────
## 主菜单的按钮支持用 `J` 触发。打开面板和关闭面板如果落在同一次按键里，
## 玩家看到的是「按了没反应」—— 项目里最不接受的一种失败。
## 所以记下打开的帧号，那一帧内的按键一律忽略。

## 署名正文。**加 / 换素材时这里与 `assets/CREDITS.md` 一起改**（两处都要动）
const BODY := """主角 · 剑客 — Mattz Art（自定义许可）
    xzany.itch.io/free-knight-2d-pixel-art
主角 · 弓手 — DezrasDragons（CC0）
    opengameart.org/content/ranger-animated
小怪 · Boss — MoikMellah（CC0）
    opengameart.org/content/goblin-corps-mv-platformer-set
NPC · 老铁匠与猎人 — CraftPix.net（OGA-BY 3.0）
    opengameart.org/content/villagers-sprite-sheets-pixel-art-pack
界面面板 — Kenney（CC0）
    kenney.nl/assets/ui-pack-pixel-adventure
中文字体 — Google Noto Sans SC（SIL OFL 1.1）
    github.com/google/fonts"""

## 上一次关掉的帧号（**给暂停菜单读的**，见文件头）
var _closed_frame := -1
## 打开的帧号：那一帧内不响应关闭（见文件头）
var _opened_frame := -1

@onready var _root: Control = $Root
@onready var _title: Label = $Root/Panel/Title
@onready var _body: Label = $Root/Panel/Body
@onready var _note: Label = $Root/Panel/Note
@onready var _back: Button = $Root/Panel/Back


func _ready() -> void:
	_root.visible = false
	_body.text = BODY
	_back.pressed.connect(close)
	if not GameSettings.language_changed.is_connected(_on_language_changed):
		GameSettings.language_changed.connect(_on_language_changed)
	refresh()


# ── 开关 ───────────────────────────────────────────────────────

func is_open() -> bool:
	return _root.visible


func closed_at_frame() -> int:
	return _closed_frame


func open() -> void:
	_opened_frame = Engine.get_process_frames()
	_root.visible = true
	refresh()


func close() -> void:
	_closed_frame = Engine.get_process_frames()
	_root.visible = false


# ── 输入 ───────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	# 刚打开的那一帧：把按键吃掉但**不关闭** —— 否则「按 J 打开」会当场变成「按 J 关闭」
	if Engine.get_process_frames() <= _opened_frame:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_J or k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			close()
			get_viewport().set_input_as_handled()


func _on_language_changed(_locale: String = "") -> void:
	refresh()


# ── 绘制 ───────────────────────────────────────────────────────

func refresh() -> void:
	_title.text = tr("UI_CREDITS")
	_note.text = tr("UI_CREDITS_NOTE")
	_back.text = tr("UI_BACK")


# ── 给断言看的 ─────────────────────────────────────────────────

## 署名正文（断言扫「有没有把作者漏掉」）
func body_text() -> String:
	return _body.text
