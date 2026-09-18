extends Node
## 商店的观感截图（批 6：制书上架）。
##     godot --path <项目根> res://tests/shot_shop.tscn     # 输出到 build/shots/
##
## 为什么这件事必须靠截图：货架尾部新加的制书行没有装备图标（「书」字占位）、
## 已解锁的行要置灰 —— 文字断言验得出内容，验不出「它和装备行挤在一起
## 还是不是一眼分得清」。铁律同 shot_forge。

const TOWN := preload("res://scenes/stages/town.tscn")


func _ready() -> void:
	PlayerState.reset_for_new_game()
	var town := TOWN.instantiate()
	add_child(town)
	await _frames(5)
	var player := town.get_node("Player")
	var panel := player.get_node("ShopPanel")

	# 三本制书 + 一点元宝：能买一本、买不起一本、已解锁一本 —— 三种状态同框
	# （注意枚举名：EPIC=传说、LEGENDARY=至尊 —— 别看名字想当然）
	PlayerState.gold = 500
	var ok := PlayerState.unlock_tier(ItemData.Tier.EPIC)   # 传说制书 → 已解锁（置灰）
	print("unlock legend ok=", ok)                                # 别让失败静默过去
	PlayerState.gold = 130

	panel.call("open")
	await _frames(4)
	# 光标移到货架尾部（制书区）：先翻到最后一页
	var total: int = panel.call("_entries").size()
	for _i in total:
		_tap_key(KEY_DOWN)
		await _frames(1)
	for _i in 3:
		_tap_key(KEY_UP)      # 停在制书区中间，三行都进画面
		await _frames(2)
	panel.call("refresh")
	await _frames(3)
	await _shot("shop_blueprints.png")

	get_tree().paused = false
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/shots"))
	print("%s err=%d" % [name, img.save_png("res://build/shots/" + name)])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _tap_key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
