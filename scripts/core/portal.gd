extends Area2D
## 传送门：玩家走进去切到目标场景（城镇 ↔ 关卡）。
##
## 防穿回设计：玩家**已经在门里**时不触发，必须离开一次再进来才算 ——
## 不然出生点挨着门的新场景会立刻把人弹回去（子弹在膛的状态）。
## 切换时把进度档里的场景路径更新、快照清空：跨场景传送后世界重置，
## 快照的节点路径跟场景绑死，跨场景复用只会张冠李戴。

@export_file("*.tscn") var target_scene: String = ""

var _player_inside := false
var _armed := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


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
	# 玩家静止站在门里时 body_entered 不会再发 —— 用轮询补一次触发窗口
	if _player_inside and _armed:
		_try()


func _try() -> void:
	if not _armed or not _player_inside or target_scene.is_empty():
		return
	_armed = false
	SaveManager.write_progress(target_scene, {})
	get_tree().change_scene_to_file(target_scene)
