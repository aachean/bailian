extends Node
## 存档底座。M2 只存「进度到哪了」（当前关卡路径），
## 装备 / 强化 / 玩家数值在增量 4 接进来 —— 那时只往字典里加字段，不改结构。
##
## 格式用 ConfigFile：手改得动、坏了能看出来，原型阶段够用。
## 存档位置 user://save.cfg（与 settings.cfg 同目录，互不干扰）。

const SAVE_PATH := "user://save.cfg"
const SECTION := "progress"
const VERSION := 1


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 写进度。现在只有关卡路径；以后加装备、强化等级就往这个字典里放
func write_progress(level_path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "version", VERSION)
	cfg.set_value(SECTION, "level", level_path)
	cfg.set_value(SECTION, "saved_at", Time.get_unix_time_from_system())
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("SaveManager: 存档失败 err=%d" % err)


## 读进度。返回关卡路径；没有存档 / 读不出来 / 没有这一项，一律返回空串。
## 调用方拿空串就走「新游戏」分支，不要猜原因。
func read_progress() -> String:
	if not has_save():
		return ""
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return ""
	return str(cfg.get_value(SECTION, "level", ""))


## 清档（主菜单「重新开始」之类将来会用到；测试也靠它）
func erase_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
