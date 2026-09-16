extends Node
## 导出包内验证：ResDir 规范化后，目录扫描与资源装载是否正常。

func _ready() -> void:
	for dir in ["res://data/characters", "res://assets/characters/swordsman",
			"res://assets/enemies/goblin/peasant", "res://assets/npcs/old_man"]:
		var f := ResDir.files(dir)
		print("%-42s %d 项: %s" % [dir, f.size(), str(f.slice(0, 3))])
	var all: Array = CharacterData.all()
	print("CharacterData.all() → %d 个: %s" % [all.size(), str(all.map(func(c): return str(c.id)))])
	# 真装载一次（ResDir 给出的名字能否 load）
	var ok := 0
	for f in ResDir.files("res://assets/characters/swordsman"):
		if f.ends_with(".png") and ResourceLoader.exists("res://assets/characters/swordsman/" + f):
			ok += 1
	print("swordsman 帧可加载数: %d" % ok)
	var mm: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(mm)
	await _frames(8)
	mm.call("_open_character_page")
	await _frames(4)
	var page: Control = mm.get("_char_page")
	for c in page.get_children():
		if c is VBoxContainer:
			print("选人页 VBox 子节点数 = %d" % c.get_child_count())
	print("done")
	get_tree().quit()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
