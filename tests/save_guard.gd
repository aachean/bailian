extends RefCounted
## 测试期间把**玩家真正的存档槽**备份到内存，测完原样还回去。
##
## ── 为什么必须有这个 ──────────────────────────────────────────
## `user://` 就是玩家真正玩游戏用的那个目录 —— 无头测试和 `play-bailian.bat`
## 指向的是同一份 `save_1..3.cfg`。
## 而 `test_m2` 为了测「槽位互不污染」会 **wipe 三个槽**，
## 于是：**跑一次回归 = 抹一次玩家的进度**。
## 这不是「测试环境脏了无所谓」——被抹掉的是神真的在玩的那个档。
##
## 用法（测试脚本里）：
## ```gdscript
## const SaveGuard := preload("res://tests/save_guard.gd")
## func _ready() -> void:
##     var bak := SaveGuard.backup()
##     ...跑完所有用例...
##     SaveGuard.restore(bak)
## ```

const SLOTS := 3


## 把三个槽 + last_slot.cfg 读成字节存下来。文件不存在就记成「本来就没有」
static func backup() -> Dictionary:
	var out := {}
	for s in range(1, SLOTS + 1):
		var p := SaveManager.slot_path(s)
		if FileAccess.file_exists(p):
			out["slot_%d" % s] = FileAccess.get_file_as_bytes(p)
	var lp: String = SaveManager.LAST_SLOT_PATH
	if FileAccess.file_exists(lp):
		out["last"] = FileAccess.get_file_as_bytes(lp)
	return out


## 按备份原样还原：备份里没有的槽 = 测试前就不存在，删掉它
static func restore(bak: Dictionary) -> void:
	for s in range(1, SLOTS + 1):
		var key := "slot_%d" % s
		var p := SaveManager.slot_path(s)
		if bak.has(key):
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_buffer(bak[key])
				f.close()
		elif FileAccess.file_exists(p):
			SaveManager.erase_slot(s)
	var lp: String = SaveManager.LAST_SLOT_PATH
	if bak.has("last"):
		var f2 := FileAccess.open(lp, FileAccess.WRITE)
		if f2 != null:
			f2.store_buffer(bak["last"])
			f2.close()
	elif FileAccess.file_exists(lp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(lp))
