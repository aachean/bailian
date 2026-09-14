extends Node
## 存档底座：3 个存档槽，互不干扰。
##
## 用户验收原话：「一旦点新游戏就会全重新开始，应该有存档的列表可以去加载。」
## 单档 → 槽位制：开始游戏时选槽（覆盖需自担），读取存档时列槽挑一个，
## 当前正在玩的槽记在 last_slot，「继续游戏」回到最近一次玩的那个。
##
## 每槽一个文件（user://save_1.cfg …），坏一个不牵连其他。
## 快照的收集 / 恢复由关卡根节点（stage.gd）负责，这里只管序列化与槽位。

const SECTION := "progress"
## 6：三层结构（地图 → 副本 → 关卡）带来的逐关解锁进度。
## 旧档（< 6）不作废：等级 / 装备 / 精铁照旧带回，只把「打到第几关」重来 ——
## 见 main_menu._enter_slot 的旧档分支
const VERSION := 6
const SLOT_COUNT := 3
const LAST_SLOT_PATH := "user://last_slot.cfg"

## 正在玩的槽（1 起）。菜单开始 / 读档时设置，游戏内写档都用它
var current_slot: int = 1


# ── 槽位与路径 ─────────────────────────────────────────────────

func slot_path(slot: int) -> String:
	return "user://save_%d.cfg" % slot


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## 最近一次玩的槽；从没玩过返回 0
func last_slot() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(LAST_SLOT_PATH) != OK:
		return 0
	return int(cfg.get_value("slot", "n", 0))


func _remember_slot(slot: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("slot", "n", slot)
	cfg.save(LAST_SLOT_PATH)


# ── 进入游戏的两个入口 ─────────────────────────────────────────

## 菜单「开始游戏」选了槽：新建该槽进度（空快照 = 全新世界），并设为当前槽
func start_new_game(slot: int, level_path: String) -> void:
	current_slot = slot
	_remember_slot(slot)
	# 新游戏要从头走：先清掉「解锁到哪」。
	# 必须单独清一次 —— write_progress 为了保住附加字段会先读旧档
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "furthest", "")
	cfg.set_value(SECTION, "unlocked", {})
	cfg.set_value(SECTION, "cleared", [])
	cfg.save(slot_path(slot))
	write_progress(level_path, {})


## 菜单「读取存档」选了槽：设为当前槽，并标记下一次进关卡要恢复快照
func load_game(slot: int) -> void:
	current_slot = slot
	_remember_slot(slot)
	_pending_restore = true


# ── 写 / 读 ────────────────────────────────────────────────────

## 关卡 _ready 时来取。true = 这次进入要恢复快照（读了档）
var _pending_restore := false


## 写进度。state 是关卡快照（结构由 stage.gd 决定，这里不解读）；
## 空字典 = 干净的新开局。写当前槽。
##
## **先 load 一次再写**：档里除了这几项还有附加字段（furthest / unlocked / cleared 等），
## 不读旧文件直接 save 会把它们整个抹掉。
func write_progress(level_path: String, state: Dictionary = {}) -> void:
	var cfg := ConfigFile.new()
	cfg.load(slot_path(current_slot))
	cfg.set_value(SECTION, "version", VERSION)
	cfg.set_value(SECTION, "level", level_path)
	cfg.set_value(SECTION, "state", state)
	cfg.set_value(SECTION, "saved_at", Time.get_unix_time_from_system())
	var err := cfg.save(slot_path(current_slot))
	if err != OK:
		push_warning("SaveManager: 存档失败 err=%d" % err)
	_pending_restore = false


# ── 解锁到哪（关卡推进）────────────────────────────────────────

## 记下「已经打到哪一关」。门的封印解开时调用（portal._on_seal_broken）。
## 不记这个的话，玩家回城一趟再出来，又得从第一关重走 —— 关卡一连上就立刻需要它
func unlock_level(path: String) -> void:
	if path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(slot_path(current_slot))
	if str(cfg.get_value(SECTION, "furthest", "")) == path:
		return                    # 没变化就不落盘，省得每帧都写
	cfg.set_value(SECTION, "furthest", path)
	cfg.save(slot_path(current_slot))


## 已解锁的最远关卡路径。没解锁过返回空串，调用方回落到自己的默认目标
##
## ⚠️ **这是线性结构的残留**：它记的是「一整关的场景路径」，供 `level_2/3` 上
## 那扇 `to_furthest` 的门用（也供还没重切的老断言用）。三层结构（地图 → 副本 → 关卡）
## 用的不是它，而是下面的 `unlocked` / `cleared` —— 那套按「副本 id + 段号」记，
## 一段一段解锁。两套并存到 `level_2/3` 也重切完为止。
func furthest_level() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(current_slot)) != OK:
		return ""
	return str(cfg.get_value(SECTION, "furthest", ""))


# ── 逐关解锁（三层结构用）──────────────────────────────────────
#
# 存的是一张表：**副本 id → 已经解锁到第几段**（1 = 第 1 段可进，缺失 = 这个副本没开）。
# 加上一个「已清空的副本 id」列表，供舆图打勾。
#
# 为什么按 id + 段号而不是场景路径：路径会随重命名而变（重切关卡时改过一次），
# id 不会。这里只存**事实**；「清完这一关之后解锁谁」是玩法规则 ——
# 那条在 scripts/core/game_progress.gd（它读三层结构数据，本文件不读内容和规则）。

## 解锁进度表：副本 id（字符串）→ 已解锁段数。无档返回空表
func unlocked_table() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(current_slot)) != OK:
		return {}
	var d = cfg.get_value(SECTION, "unlocked", {})
	return d if d is Dictionary else {}


## 这个副本已经开出来几段。0 = 没开
func unlocked_stages(dungeon_id: StringName) -> int:
	return int(unlocked_table().get(String(dungeon_id), 0))


## 解锁到第 index 段（0 起）。**只增不减**，重复调用无副作用、不落盘。
## index 为负时忽略 —— 调用方传错不该把存档写坏
func unlock_stage(dungeon_id: StringName, index: int) -> void:
	if dungeon_id == &"" or index < 0:
		return
	var key := String(dungeon_id)
	var table := unlocked_table()
	if int(table.get(key, 0)) >= index + 1:
		return
	table[key] = index + 1
	var cfg := ConfigFile.new()
	cfg.load(slot_path(current_slot))
	cfg.set_value(SECTION, "unlocked", table)
	cfg.save(slot_path(current_slot))


## 已清空的副本 id 列表（舆图上打勾用）
func cleared_dungeons() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(current_slot)) != OK:
		return []
	var a = cfg.get_value(SECTION, "cleared", [])
	return (a as Array).duplicate() if a is Array else []


func is_cleared(dungeon_id: StringName) -> bool:
	return cleared_dungeons().has(String(dungeon_id))


## 记下「这个副本清完了」。重复调用无副作用
func mark_cleared(dungeon_id: StringName) -> void:
	if dungeon_id == &"":
		return
	var list := cleared_dungeons()
	if list.has(String(dungeon_id)):
		return
	list.append(String(dungeon_id))
	var cfg := ConfigFile.new()
	cfg.load(slot_path(current_slot))
	cfg.set_value(SECTION, "cleared", list)
	cfg.save(slot_path(current_slot))


## 清空解锁进度（新游戏时用）。**必须单独清一次** ——
## write_progress 为了保住附加字段会先读旧档，指望它顺手清是清不掉的
func clear_unlock_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.load(slot_path(current_slot))
	cfg.set_value(SECTION, "unlocked", {})
	cfg.set_value(SECTION, "cleared", [])
	cfg.save(slot_path(current_slot))


## 这一槽的存档格式版本。没档 / 读不出来返回 0
func slot_version(slot: int) -> int:
	if not slot_exists(slot):
		return 0
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(slot)) != OK:
		return 0
	return int(cfg.get_value(SECTION, "version", 0))


## 读当前槽的关卡路径。空串 = 没档 / 坏档，调用方走「新游戏」分支。
func read_progress(slot: int = -1) -> String:
	var s := current_slot if slot < 0 else slot
	if not slot_exists(s):
		return ""
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(s)) != OK:
		return ""
	return str(cfg.get_value(SECTION, "level", ""))


## 读当前槽的快照本体。无档返回空字典。
func read_state(slot: int = -1) -> Dictionary:
	var s := current_slot if slot < 0 else slot
	if not slot_exists(s):
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(s)) != OK:
		return {}
	var d = cfg.get_value(SECTION, "state", {})
	return d if d is Dictionary else {}


## 槽位展示信息（存档列表用）：场景路径、快照、时间
func read_slot_info(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(slot)) != OK:
		return {}
	return {
		"level": str(cfg.get_value(SECTION, "level", "")),
		"state": cfg.get_value(SECTION, "state", {}),
		"saved_at": int(cfg.get_value(SECTION, "saved_at", 0)),
	}


func erase_slot(slot: int) -> void:
	if slot_exists(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))
	if current_slot == slot:
		_pending_restore = false


## 关卡 _ready 时取走待恢复的快照。
## **只认 load_game() 打的标记** —— 直接跑场景、跑测试、新开局，
## 一律返回空字典。不设门槛的话，跑一遍测试都会把用户存档恢复进测试世界。
func take_pending_state() -> Dictionary:
	if not _pending_restore:
		return {}
	_pending_restore = false
	return read_state()


## 取消「下一次进关卡要恢复快照」这个待办。
##
## 读**旧结构**的档时用：那份快照里记的是老关卡里的坐标（x 可能到 1800），
## 直接套到城镇（宽 1280）上会把玩家甩到界外。那种情况要的是
## 「带上等级装备、世界从头开始」，所以先把快照的恢复请求撤掉
func drop_pending_restore() -> void:
	_pending_restore = false
