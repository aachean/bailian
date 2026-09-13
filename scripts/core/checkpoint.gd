extends Area2D
## 中途复活点：玩家路过一次，就把「死后回到哪」推到这里。
##
## ── 为什么需要它 ──────────────────────────────────────────────
## 关卡从 3 屏变成 4~5 屏之后，死在关底要重走一整关。那不叫难度，那叫烦。
## 关卡越长，复活点越必要 —— 这是长度带来的必需品，不是可选的润色。
##
## 复活点会进存档快照（`stage.collect` 存 player 的 `spawn_x/spawn_y`），
## 不然读档之后死一次，人又回到关卡最开头，中途设的复活点全白费。
##
## ── 视觉约定 ──────────────────────────────────────────────────
## 没踩过是灰的，踩过变金色。玩家得看得见「这里记下了」——
## 静默生效的机制等于不存在（漏翻的 key 显示成 key 那轮吃过这个亏）。

const IDLE_COLOR := Color(0.42, 0.4, 0.34, 0.55)
const ACTIVE_COLOR := Color(0.95, 0.8, 0.4, 0.85)

var _used := false

@onready var _visual: ColorRect = $Visual


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual.color = ACTIVE_COLOR if _used else IDLE_COLOR


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.has_method("set_spawn_point"):
		body.call("set_spawn_point", global_position)
	_used = true
	_visual.color = ACTIVE_COLOR


func is_used() -> bool:
	return _used
