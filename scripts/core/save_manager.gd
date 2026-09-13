extends Node
## 存档底座。
##
## M2 增量 3 起存的不只是「进度到哪了」，还有**离开时的世界快照**
## （玩家血量位置、每只怪的血量位置死活）——「继续游戏」= 回到离开那一刻，
## 而不是关卡重开。快照的收集 / 恢复由关卡根节点（stage.gd）负责，
## 这里只管序列化和「下一次进关卡要不要恢复」的传递。
##
## 格式用 ConfigFile：手改得动、坏了能看出来，原型阶段够用。
## 存档位置 user://save.cfg（与 settings.cfg 同目录，互不干扰）。

const SAVE_PATH := "user://save.cfg"
const SECTION := "progress"
const VERSION := 3

## 关卡 _ready 时来取。true = 这次进入要恢复快照（点了「继续」）
var _pending_restore := false


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 写进度。state 是关卡快照（结构由 stage.gd 决定，这里不解读）；
## 空字典 = 干净的新开局。
func write_progress(level_path: String, state: Dictionary = {}) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "version", VERSION)
	cfg.set_value(SECTION, "level", level_path)
	cfg.set_value(SECTION, "state", state)
	cfg.set_value(SECTION, "saved_at", Time.get_unix_time_from_system())
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("SaveManager: 存档失败 err=%d" % err)
	_pending_restore = false


## 读进度。返回关卡路径；没有存档 / 读不出来 / 没有这一项，一律返回空串。
## 调用方拿空串就走「新游戏」分支，不要猜原因。
func read_progress() -> String:
	if not has_save():
		return ""
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return ""
	return str(cfg.get_value(SECTION, "level", ""))


## 读快照本体。无档返回空字典。
func read_state() -> Dictionary:
	if not has_save():
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return {}
	var d = cfg.get_value(SECTION, "state", {})
	return d if d is Dictionary else {}


## 菜单「开始游戏」：新开局。关卡 _ready 拿到的快照会是空的。
func request_new_game(level_path: String) -> void:
	write_progress(level_path, {})


## 菜单「继续游戏」：标记下一次进关卡要恢复快照。
func request_continue() -> void:
	_pending_restore = true


## 关卡 _ready 时取走待恢复的快照。
## **只认 request_continue() 打的标记** —— 直接跑场景、跑测试、新开局，
## 一律返回空字典。这条很重要：不设门槛的话，跑一遍测试都会把用户存档
## 恢复进测试世界，反过来测试写档也会污染真实进度。
func take_pending_state() -> Dictionary:
	if not _pending_restore:
		return {}
	_pending_restore = false
	return read_state()


## 清档（主菜单「重新开始」之类将来会用到；测试也靠它）
func erase_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_pending_restore = false
