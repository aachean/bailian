extends Node
## 截图：主菜单 + 素材致谢面板（中文）。
## **不碰语言设置** —— 上一次在这里 set_language("en") 之后又写了 set_language("zh")，
## 而 SUPPORTED 的 key 是 "zh_CN"，"zh" 不认 → 切回失败 → 英文被写进设置文件。
## 要切语言就用 `原值` 切回，别硬编码；能不动就不动。

func _ready() -> void:
	print("启动 locale=%s" % TranslationServer.get_locale())
	var mm: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(mm)
	await _frames(8)
	await _shot("credits_1_menu.png")
	mm.call("_on_credits")
	await _frames(8)
	var p: Node = mm.get_node("CreditsPanel")
	print("面板标题='%s'" % (p.get_node("Root/Panel/Title") as Label).text)
	await _shot("credits_2_panel.png")
	print("结束 locale=%s（应与启动一致）" % TranslationServer.get_locale())
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/shots/" + name)
	print("saved ", name)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
