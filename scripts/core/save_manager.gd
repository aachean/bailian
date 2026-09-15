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
## 存档格式版本。
##
## 10（2026-09-15）：第二个角色上线（M4）。存档多了 character_id（选了谁）。
##   **10 不作废进度**：纯增量字段，旧档读不到 = 没选过，回退默认角色。
## 9（2026-09-15）：经济上线（M3 第 3 步）。存档多了 gold（元宝）一个字段，
##   买 / 卖 / 怪掉的元宝都进它。**9 不作废进度**：纯增量字段，
##   旧档读不到就是 0（元宝本来也是从 0 开始攒）。
## 8（2026-09-14）：装备从「型号（资源路径）」换成「实例 uid」，强化改成逐件 + 按品质封顶。
##   存档多了 forge（uid → 强化等级）与 next_uid 两张表，upgrade（全局强化等级）作废。
##   **8 不作废进度**：等级 / 装备 / 精铁 / 打到哪全都能读回来，
##   旧档里的 upgrade 会搬到当时装备的那把武器上（PlayerState._migrate_legacy_upgrade）。
## 7：副本粒度重定（副本 = 一条 3~4 屏的路），存档只剩「哪些副本通关了」这一张表。
const VERSION := 10

## 低于这个版本的档，「打到哪」那套记录作废（只带回成长）。
## 7 之前的档记的是**线性三关**的进度，套不进「地图 → 副本 → 屏」的结构 ——
## 见 main_menu 的旧档分支。**判定要用它，不是 VERSION**：
## 拿 VERSION 判的话，每次加一层同格式的新字段都会误伤一批能用的档
const STRUCTURE_VERSION := 7
## 存档槽数量（2026-09-15 黑盒反馈：3 不够，扩到 15，菜单每页 5 个翻 3 页）。
## 槽位文件名不变（save_N.cfg），老档天然在原位
const SLOT_COUNT := 15
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
	# 新游戏要从头走：先清掉「打到哪」。
	# 必须单独清一次 —— write_progress 为了保住附加字段会先读旧档
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "furthest", "")
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


# ── 副本进度（三层结构用）──────────────────────────────────────
#
# 只有一张表：**已经通关的副本 id**。
#
# 为什么只剩这一张：粒度重定之后（副本 = 一条 3~4 屏的路），
# 副本内部按屏推进、进去就从头开始打 —— 没有「解锁到第几屏」这种需要记的东西。
# 副本之间的解锁由**顺序**推：「前一个副本通关了没有」就决定这个副本开没开
# （规则在 scripts/core/game_progress.gd，本文件只存事实）。
#
# 为什么按 id 而不是场景路径：路径会随重命名而变（重切时改过一次），id 不会。

## 已通关的副本 id 列表（舆图上打勾用）
func cleared_dungeons() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(slot_path(current_slot)) != OK:
		return []
	var a = cfg.get_value(SECTION, "cleared", [])
	return (a as Array).duplicate() if a is Array else []


func is_cleared(dungeon_id: StringName) -> bool:
	return cleared_dungeons().has(String(dungeon_id))


## 记下「这个副本通关了」。重复调用无副作用
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


## 清空副本通关记录（新游戏时用）。**必须单独清一次** ——
## write_progress 为了保住附加字段会先读旧档，指望它顺手清是清不掉的
func clear_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.load(slot_path(current_slot))
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
