extends Node
## AiBridge —— 让外部程序（AI）实时操控本游戏并观察反馈的「进程内桥」。
##
## 只在启动时带用户参数 `--ai-bridge` 才生效，正常游玩零开销：
##   <Godot 控制台版 exe> --path <本仓库目录> -- --ai-bridge
##
## 为什么不用 OS 级键鼠模拟（pyautogui / SendInput）作为主通道：
##   1. 受窗口焦点、DPI 缩放、键盘布局影响，换台机器就崩；
##   2. 只能拿到像素，拿不到「土狼计时还剩多少」这类内部状态；
##   3. 时序不可复现，改一行代码前后没法逐帧对齐对比。
## 本桥走引擎自己的输入管线（Input.action_press），对游戏逻辑而言与真人按键等价，
## 同时把角色内部状态按物理帧推出去，并且能直接在正确的时机抓取渲染结果。
##
## 协议：换行分隔的 JSON（JSON Lines），utf-8。
##   客户端 → 服务端：指令，形如 {"cmd":"key","action":"jump","pressed":true}
##   服务端 → 客户端：每个物理帧一份状态快照，形如 {"frame":123,"player":{...}}

const DEFAULT_PORT := 4409
const DEFAULT_SHOT_DIR := "res://build/ai"

## 是否已被 --ai-bridge 激活
var _enabled := false
var _port := DEFAULT_PORT
var _shot_dir := DEFAULT_SHOT_DIR

var _server: TCPServer
var _peers: Array[StreamPeerTCP] = []
var _buf: Array[String] = []

## 物理帧计数，从桥启动开始。客户端用它对齐操作与观察。
var _frame := 0
var _autopush := true

## 当前按住的 action（我们自己记账，因为 Input 没有公开的"当前按了什么"）
var _held: Dictionary = {}
## 服务端计时的点按：[{action: String, remaining: int}]
var _taps: Array = []

## 上一帧的状态，用来识别跳/落/离地事件
var _prev_on_floor := true
var _prev_vy := 0.0
var _events: Array = []

var _player: Node = null

## 连续截图（record 指令）
var _rec_left := 0
var _rec_interval := 6
var _rec_counter := 0
var _rec_prefix := "rec"
var _shot_seq := 0
var _busy_shot := false


func _ready() -> void:
	# 游戏暂停时桥也要活着，否则暂停后就再也叫不动了
	process_mode = Node.PROCESS_MODE_ALWAYS

	var args := OS.get_cmdline_user_args()
	if not args.has("--ai-bridge"):
		_enabled = false
		set_physics_process(false)
		return
	for a in args:
		if a.begins_with("--ai-bridge-port="):
			_port = int(a.split("=", true, 1)[1])
		elif a.begins_with("--ai-bridge-shots="):
			_shot_dir = a.split("=", true, 1)[1]

	_server = TCPServer.new()
	var err := _server.listen(_port, "127.0.0.1")
	if err != OK:
		push_error("[AiBridge] 无法监听 127.0.0.1:%d (err=%d)" % [_port, err])
		set_physics_process(false)
		return
	_enabled = true
	_ensure_shot_dir()
	print("[AiBridge] ready  port=%d  shots=%s" % [_port, ProjectSettings.globalize_path(_shot_dir)])


func _physics_process(_delta: float) -> void:
	_frame += 1
	_tick_taps()
	_pump()
	_collect_events()
	if _autopush and _peers.size() > 0:
		_broadcast(_snapshot())
	_maybe_record()


# ---------------------------------------------------------------- 网络

func _pump() -> void:
	while _server.is_connection_available():
		var p := _server.take_connection()
		if p != null:
			_peers.append(p)
			_buf.append("")
			p.set_no_delay(true)
			print("[AiBridge] client connected (frame=%d)" % _frame)

	var i := 0
	while i < _peers.size():
		var peer := _peers[i]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			print("[AiBridge] client disconnected (frame=%d)" % _frame)
			_peers.remove_at(i)
			_buf.remove_at(i)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			_buf[i] += peer.get_utf8_string(n)
			var nl := _buf[i].find("\n")
			while nl != -1:
				var line := _buf[i].substr(0, nl).strip_edges()
				_buf[i] = _buf[i].substr(nl + 1)
				if line != "":
					_handle(line, peer)
				nl = _buf[i].find("\n")
		i += 1


func _send(peer: StreamPeerTCP, payload: Dictionary) -> void:
	if peer == null or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	peer.put_data((JSON.stringify(payload) + "\n").to_utf8_buffer())


func _broadcast(payload: Dictionary) -> void:
	var s := (JSON.stringify(payload) + "\n").to_utf8_buffer()
	for peer in _peers:
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.put_data(s)


# ---------------------------------------------------------------- 指令分发

func _handle(line: String, peer: StreamPeerTCP) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		_send(peer, {"ok": false, "error": "bad json"})
		return
	var d: Dictionary = parsed
	match str(d.get("cmd", "")):
		"hello":
			_send(peer, {
				"ok": true, "type": "ack", "cmd": "hello", "name": "aibridge", "version": 1,
				"port": _port, "frame": _frame,
				"scene": _scene_name(),
				"actions": _known_actions(),
			})
		"key":
			var act := str(d.get("action", ""))
			if not _valid_action(act):
				_send(peer, {"ok": false, "error": "unknown action: " + act})
			else:
				if bool(d.get("pressed", true)):
					_press(act)
				else:
					_release(act)
				if bool(d.get("ack", false)):
					_send(peer, {"ok": true, "type": "ack", "cmd": "key", "action": act, "frame": _frame})
		"tap":
			var act2 := str(d.get("action", ""))
			if not _valid_action(act2):
				_send(peer, {"ok": false, "error": "unknown action: " + act2})
			else:
				var nf := maxi(1, int(d.get("frames", 3)))
				_press(act2)
				_taps.append({"action": act2, "remaining": nf})
				if bool(d.get("ack", false)):
					_send(peer, {"ok": true, "type": "ack", "cmd": "tap", "action": act2, "frames": nf, "frame": _frame})
		"release_all":
			for act3 in _held.keys():
				if bool(_held[act3]):
					Input.action_release(act3)
			_held.clear()
			_taps.clear()
			_send(peer, {"ok": true, "type": "ack", "cmd": "release_all", "frame": _frame})
		"state":
			_send(peer, _snapshot(false))
		"shot":
			_cmd_shot(d, peer)
		"record":
			_rec_interval = maxi(1, int(d.get("interval", 6)))
			_rec_left = maxi(0, int(d.get("count", 60)))
			_rec_counter = 0
			_rec_prefix = str(d.get("prefix", "rec"))
			_ensure_shot_dir()
			_send(peer, {"ok": true, "type": "ack", "cmd": "record", "count": _rec_left, "interval": _rec_interval})
		"park":
			_cmd_park(d, peer)
		"autopush":
			_autopush = bool(d.get("value", true))
			_send(peer, {"ok": true, "type": "ack", "cmd": "autopush", "value": _autopush})
		"reset":
			_player = null
			_release_all_now()
			get_tree().reload_current_scene()
			_send(peer, {"ok": true, "type": "ack", "cmd": "reset", "frame": _frame})
		"quit":
			_send(peer, {"ok": true, "type": "ack", "cmd": "quit"})
			print("[AiBridge] quit requested by client")
			get_tree().quit()
		_:
			_send(peer, {"ok": false, "error": "unknown cmd: " + str(d.get("cmd", ""))})


func _cmd_park(d: Dictionary, peer: StreamPeerTCP) -> void:
	var p := _get_player()
	if p == null:
		_send(peer, {"ok": false, "error": "no player"})
		return
	if d.has("x") or d.has("y"):
		p.global_position = Vector2(float(d.get("x", p.global_position.x)), float(d.get("y", p.global_position.y)))
	if d.has("vx") or d.has("vy"):
		p.velocity = Vector2(float(d.get("vx", 0.0)), float(d.get("vy", 0.0)))
	if bool(d.get("settle", false)):
		p.set("velocity", Vector2.ZERO)
	_send(peer, {"ok": true, "type": "ack", "cmd": "park", "frame": _frame, "player": _player_dict(p)})


# ---------------------------------------------------------------- 输入注入

func _press(action: String) -> void:
	_held[action] = true
	Input.action_press(action)


func _release(action: String) -> void:
	_held[action] = false
	Input.action_release(action)


func _release_all_now() -> void:
	for act in _held.keys():
		if bool(_held[act]):
			Input.action_release(act)
	_held.clear()
	_taps.clear()


func _tick_taps() -> void:
	var i := 0
	while i < _taps.size():
		var t: Dictionary = _taps[i]
		t["remaining"] = int(t["remaining"]) - 1
		if int(t["remaining"]) <= 0:
			_release(str(t["action"]))
			_taps.remove_at(i)
			continue
		i += 1


func _valid_action(a: String) -> bool:
	return InputMap.has_action(a)


func _known_actions() -> Array:
	var out: Array = []
	for a in InputMap.get_actions():
		var s := String(a)
		if s.begins_with("ui_"):
			continue
		out.append(s)
	out.sort()
	return out


# ---------------------------------------------------------------- 状态观测

func _scene_name() -> String:
	var cs := get_tree().current_scene
	return cs.name if cs != null else "<none>"


func _get_player() -> Node:
	if is_instance_valid(_player):
		return _player
	_player = null
	var nodes := get_tree().get_nodes_in_group("player")
	if nodes.size() > 0:
		_player = nodes[0]
		return _player
	# 兜底：整棵树里找第一个 CharacterBody2D
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CharacterBody2D:
			_player = n
			return _player
		for c in n.get_children():
			stack.append(c)
	return null


func _player_dict(p: Node) -> Dictionary:
	if p == null or not is_instance_valid(p):
		return {}
	return {
		"x": snappedf(p.global_position.x, 0.001),
		"y": snappedf(p.global_position.y, 0.001),
		"vx": snappedf(p.velocity.x, 0.001),
		"vy": snappedf(p.velocity.y, 0.001),
		"on_floor": p.is_on_floor(),
		"on_wall": p.is_on_wall(),
		"on_ceiling": p.is_on_ceiling(),
		"facing": int(p.get("_facing")) if p.get("_facing") != null else 0,
		"coyote": snappedf(float(p.get("_coyote_timer")) if p.get("_coyote_timer") != null else 0.0, 0.0001),
		"buffer": snappedf(float(p.get("_jump_buffer_timer")) if p.get("_jump_buffer_timer") != null else 0.0, 0.0001),
		"collisions": p.get_slide_collision_count(),
	}


func _shell_dict(p: Node) -> Dictionary:
	## 和 player 同一套字段，但可以指向任意刚体（M2 打靶子时用）
	return _player_dict(p)


func _collect_events() -> void:
	var p := _get_player()
	if p == null:
		return
	var on_floor: bool = p.is_on_floor()
	var vy: float = p.velocity.y
	if not _prev_on_floor and on_floor:
		_events.append("landed")
	if _prev_on_floor and not on_floor:
		_events.append("airborne")
	if _prev_vy >= 0.0 and vy < 0.0:
		_events.append("jumped")
	_prev_on_floor = on_floor
	_prev_vy = vy


func _snapshot(clear_events: bool = true) -> Dictionary:
	var p := _get_player()
	var d := {
		"frame": _frame,
		"ms": Time.get_ticks_msec(),
		"fps": Engine.get_frames_per_second(),
		"scene": _scene_name(),
		"events": _events.duplicate(),
		"keys": _held.duplicate(),
	}
	var pd := _player_dict(p)
	if not pd.is_empty():
		d["player"] = pd
	if clear_events:
		_events.clear()
	return d


# ---------------------------------------------------------------- 截图

func _ensure_shot_dir() -> void:
	var abs_dir := ProjectSettings.globalize_path(_shot_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)


func _cmd_shot(d: Dictionary, peer: StreamPeerTCP) -> void:
	if _busy_shot:
		_send(peer, {"ok": false, "error": "a shot is already in flight"})
		return
	_busy_shot = true
	_shot_seq += 1
	var nm := str(d.get("name", ""))
	if nm == "":
		nm = "shot_%05d.png" % _shot_seq
	elif not nm.ends_with(".png"):
		nm += ".png"
	var scale := float(d.get("scale", 1.0))
	_ensure_shot_dir()
	var rel := _shot_dir.path_join(nm)
	var abs_path := ProjectSettings.globalize_path(rel)

	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		_busy_shot = false
		_send(peer, {"ok": false, "error": "no viewport texture"})
		return
	var img: Image = tex.get_image()
	if img == null:
		_busy_shot = false
		_send(peer, {"ok": false, "error": "no image (headless?)"})
		return
	if not is_equal_approx(scale, 1.0):
		var w := maxi(1, int(round(img.get_width() * scale)))
		var h := maxi(1, int(round(img.get_height() * scale)))
		img.resize(w, h, Image.INTERPOLATE_NEAREST)
	var err := img.save_png(abs_path)
	_busy_shot = false
	_send(peer, {
		"ok": err == OK, "type": "shot", "frame": _frame,
		"path": rel, "abs": abs_path,
		"w": img.get_width(), "h": img.get_height(),
		"state": _snapshot(false),
	})


func _maybe_record() -> void:
	if _rec_left <= 0:
		return
	_rec_counter += 1
	if _rec_counter % _rec_interval != 0:
		return
	_rec_left -= 1
	_shot_seq += 1
	_cmd_shot({"name": "%s_%05d.png" % [_rec_prefix, _shot_seq], "scale": 0.5}, null)
