class_name ResDir
extends RefCounted
## res:// 目录扫描工具：**屏蔽「开发环境 vs 导出包」的差异**。
##
## ── 为什么需要它（导出后才发现的大坑）──────────────────────
## 导出包里 `DirAccess.get_files()` 返回的是**引擎生成的元文件**，不是资源本身：
##
## | 目录 | 开发环境 | 导出包 |
## |---|---|---|
## | 角色帧 | `idle_0.png` | `idle_0.png.import` |
## | 角色数据 | `archer.tres` | `archer.tres.remap` |
##
## 直接按 `.png` / `.tres` 匹配 → **导出包里全部落空**：主角/敌人/NPC 的精灵
## 一个都不加载（全部退成色块），选人页一片空白。
## 而这个 bug **从项目目录跑永远复现不了** —— 开发环境返回的就是资源本身。
##
## 修法：一律用 `files()` 拿「逻辑文件名」（去掉 `.import` / `.remap`），
## 再拼 `res://` 路径 `load()` —— 加载走引擎的重定向，原路径依然有效。
##
## 验证手法：把测试场景临时打进包（放行 `tests/`），再
## `godot --headless --main-pack <导出包> res://tests/xxx.tscn` ——
## **只有在导出包里跑，才能看见这类差异**。


## 目录下的「逻辑文件名」，可直接拼 `res://` 路径 `load()`。
static func files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("资源目录打不开：%s" % dir)
		return out
	for f in d.get_files():
		out.append(logical_name(f))
	return out


## `idle_0.png.import` → `idle_0.png`；`archer.tres.remap` → `archer.tres`
static func logical_name(file: String) -> String:
	return file.trim_suffix(".import").trim_suffix(".remap")
