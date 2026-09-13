extends Area2D
## 传送门：玩家走进去切到目标场景（城镇 ↔ 关卡）。
##
## ── 防穿回设计 ────────────────────────────────────────────────
## 玩家**已经在门里**时不触发，必须离开一次再进来才算 ——
## 不然出生点挨着门的新场景会立刻把人弹回去（子弹在膛的状态）。
## 切换时把进度档里的场景路径更新、快照清空：跨场景传送后世界重置，
## 快照的节点路径跟场景绑死，跨场景复用只会张冠李戴。
##
## ── 封印（M3-5）──────────────────────────────────────────────
## 通向下一关的门被 Boss 封着：`locked_by` 指到 Boss 节点，它不死门就不开。
## 没指封印者的门（回城门）照旧常开。
##
## 未解锁时**必须给一句话**。静悄悄地什么都不发生，玩家只会以为卡了 bug ——
## 这是黑盒验收里最容易踩的一类坑（同类：漏翻的 key 显示成 key 本身）。
## 所以走进去会弹一句「封锁中」，并配一个暗红的门色。

const OPEN_COLOR := Color(0.45, 0.65, 0.85, 0.55)
const LOCKED_COLOR := Color(0.44, 0.26, 0.28, 0.62)
## 提示显示多久后开始淡出（秒）
const HINT_HOLD := 1.2

@export_file("*.tscn") var target_scene: String = ""
## 封印者：通常指到本关 Boss。留空 = 常开。它没有 Health 或找不到时按常开处理
@export var locked_by: NodePath
## 未解锁时的那句话（翻译 key）
@export var hint_key: StringName = &"UI_GATE_LOCKED"
## true = 目标改成「已解锁的最远关卡」。城镇的门用这个 ——
## 不然玩家回城一趟再出来，又得从第一关重走一遍
@export var to_furthest: bool = false

var _player_inside := false
var _armed := false
var _locked := false
var _hint_t := 0.0
## 封印者的 Health。留着引用是为了每帧复查 —— 光靠 died 信号不够，见 _physics_process
var _seal_h: Health = null

@onready var _visual: ColorRect = $Visual
@onready var _hint: Label = $Hint


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_hint.modulate.a = 0.0
	if to_furthest:
		var f := SaveManager.furthest_level()
		if not f.is_empty():
			target_scene = f
	_bind_lock()
	_refresh_visual()


## 连上封印者的死亡信号。**读档回来的世界可能 Boss 已经死了** ——
## 这里先查一次当前状态，否则读档进门会被一扇「其实该开着的门」拦住
func _bind_lock() -> void:
	if locked_by.is_empty():
		return
	var b := get_node_or_null(locked_by)
	if b == null:
		push_warning("Portal: 找不到封印者 %s，这扇门按常开处理" % str(locked_by))
		return
	var h := b.get_node_or_null("Health") as Health
	if h == null:
		push_warning("Portal: 封印者 %s 没有 Health，这扇门按常开处理" % str(locked_by))
		return
	_seal_h = h
	_locked = not h.is_dead
	if not h.died.is_connected(_on_seal_broken):
		h.died.connect(_on_seal_broken)


func _on_seal_broken() -> void:
	_locked = false
	# 封印一解，这一关就算通了 —— 记下「解锁到哪」，
	# 城镇那扇 to_furthest 的门才知道该把玩家送到哪
	SaveManager.unlock_level(target_scene)
	_refresh_visual()


## 门的样子：封着的时候暗红，开了之后亮蓝 —— 不看提示也该看得出能不能进
func _refresh_visual() -> void:
	if _visual == null:
		return
	_visual.color = LOCKED_COLOR if _locked else OPEN_COLOR


func is_locked() -> bool:
	return _locked


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	_try()


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = false
	_armed = true          # 出去过一次，之后才允许触发


func _physics_process(_delta: float) -> void:
	# 封印者的死活每帧复查一次。光靠 died 信号不够：读档时 stage 是在自己的
	# _ready 里把 Boss 摆成尸体的，而门的 _ready 早就跑完了 —— 信号不会响第二次，
	# 门就会永远锁着，玩家读档回来发现「明明打过的关又过不去了」
	if _locked and _seal_h != null and _seal_h.is_dead:
		_on_seal_broken()
	# 玩家静止站在门里时 body_entered 不会再发 —— 用轮询补一次触发窗口
	if _player_inside and _armed:
		_try()


func _try() -> void:
	if not _armed or not _player_inside or target_scene.is_empty():
		return
	if _locked:
		_flash_hint()
		return
	_armed = false
	SaveManager.write_progress(target_scene, {})
	get_tree().change_scene_to_file(target_scene)


func _flash_hint() -> void:
	if _hint_t > 0.0:
		return                 # 正在显示，别每帧刷
	_hint_t = HINT_HOLD
	_hint.text = tr(hint_key)
	_hint.modulate.a = 1.0


func _process(delta: float) -> void:
	if _hint_t > 0.0:
		_hint_t -= delta
	elif _hint.modulate.a > 0.0:
		_hint.modulate.a = move_toward(_hint.modulate.a, 0.0, 2.6 * delta)
