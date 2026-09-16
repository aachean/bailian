extends Area2D
## 可交谈的 NPC：走进范围按 J 说话（造梦西游式）。
##
## ── 为什么复用 J 而不新开一个交互键 ───────────────────────────
## J 已经是「攻击 / 确认」。站在 NPC 面前时它不可能是攻击目标 ——
## 同一个键在不同语境下是不同的事，动作游戏通行做法，也省得玩家记两套键。
## （铁砧的交互用的也是 J，这里是同一套语言。）
##
## ── 说什么可以随进度换 ────────────────────────────────────────
## dialogue = 初见；repeat_dialogue = 已经聊过之后说的话。
## 「聊过没有」不存在 NPC 自己身上，存在 PlayerState.flags 里 ——
## 切场景会重建 NPC，存在节点上的状态会丢（这个坑在碎片那轮踩过）。

@export var name_key: StringName = &""
## 帧序列目录（如 res://assets/npcs/old_man）。非空时用像素精灵顶掉色块 ——
## 色块是原型期的占位，精灵才是正稿；留空则维持色块（测试场景还会用）
@export var sprite_dir: String = ""
## 精灵缩放：村民帧 48x48、内容高 34px，1.5 倍 ≈ 51px（主角 55 / 小怪 52）
@export var sprite_scale := 1.5
## 静态单图（告示牌这类）：sprite_dir 为空时才用。1:1 显示，底边贴地
@export var sprite_file: String = ""
@export var sprite_file_scale := 1.0
@export var dialogue: DialogueData = null
@export var repeat_dialogue: DialogueData = null

var _player: Node2D = null
var _skin: NpcSkin = null
## 对话刚关掉之后的锁帧 —— 关对话的那一下 J 还在 just_pressed 状态里，
## 不锁的话 NPC 下一帧就把它当成「开始对话」，对话会自己又弹开
var _lock := 0
var _was_open := false

@onready var _name_label: Label = $Name
@onready var _hint_label: Label = $Hint


## 精灵模式：非空 sprite_dir 时像素精灵上阵，色块（原型占位）退位
func _setup_skin() -> void:
	if sprite_dir.is_empty() and sprite_file.is_empty():
		return
	_skin = NpcSkin.new()
	_skin.name = "Skin"
	add_child(_skin)   # 建在色块之后 → 自然盖在上面，不必再挪顺序
	var ok := false
	if not sprite_dir.is_empty():
		ok = _skin.setup(sprite_dir, 18.0, sprite_scale)
	else:
		ok = _skin.setup_static(sprite_file, 18.0, sprite_file_scale)
	if not ok:
		_skin.queue_free()
		_skin = null
		return
	for n in ["Body", "Head"]:
		var n2 := get_node_or_null(n)
		if n2 != null:
			n2.visible = false


func _ready() -> void:
	_setup_skin()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if not GameSettings.language_changed.is_connected(_refresh):
		GameSettings.language_changed.connect(_refresh)
	_refresh()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player = body
		_refresh()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player = null
		_refresh()


func _physics_process(delta: float) -> void:
	if _skin != null:
		_skin.tick(delta)
	if _lock > 0:
		_lock -= 1
	# 边沿检测：对话从「开着」变成「关着」的那一帧起锁一小会儿。
	# 不做这一步，关对话的那次 J 会在下一帧被当成「开始对话」—— 对话自己弹回来
	var open := _dialogue_open()
	if _was_open and not open:
		_lock = 8                     # 8 帧 ≈ 0.13 秒，玩家感觉不到，够吃掉残留的按键
		_refresh()                    # 聊完了，把「按 J 交谈」放回来
	_was_open = open

	if _lock > 0 or open or _player == null or dialogue == null:
		return
	if Input.is_action_just_pressed("attack"):
		_talk()


## 按 J 说话。已经聊过（flag 记上了）就换后一段台词
func _talk() -> void:
	var box := get_tree().get_first_node_in_group("dialogue_box")
	if box == null:
		return
	var d: DialogueData = dialogue
	if repeat_dialogue != null and PlayerState.has_flag(dialogue.flag):
		d = repeat_dialogue
	box.call("open", d)
	# 手动记上「它是开着的」：对话期间 NPC 被暂停，_physics_process 不跑，
	# 边沿检测拿不到「开着」这个状态，关闭那一帧就锁不住，对话会自己弹回来
	_was_open = true
	# 人已经在说话了，头上还顶着「按 J 交谈」很怪（这一刻起 NPC 就被暂停，
	# 没机会自己刷新，所以在这儿手动收起来）
	_hint_label.text = ""


## 对话开着时不吃 J —— 不然按 J 翻页会顺手又开一段
func _dialogue_open() -> bool:
	var box := get_tree().get_first_node_in_group("dialogue_box")
	return box != null and bool(box.call("is_open"))


## 参数必须留着：Godot 按参数个数严格匹配信号连接（少一个会在 emit 时报错、
## 界面静默不刷新，这个家族在语言切换那轮抓到过）
func _refresh(_locale: String = "") -> void:
	_name_label.text = tr(name_key) if name_key != &"" else ""
	_hint_label.text = tr("UI_NPC_TALK") if _player != null else ""
