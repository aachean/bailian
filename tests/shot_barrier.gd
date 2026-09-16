extends Node
## 三项修复验证：怪脚贴地 / 玩家与怪不重叠 / 新头像。

func _ready() -> void:
	SaveManager.current_slot = 3
	SaveManager.start_new_game(3, "res://scenes/stages/town.tscn")
	var lv: Node = load("res://scenes/stages/lichang.tscn").instantiate()
	add_child(lv)
	await _frames(12)
	var player: Node2D = lv.get_node("Player")
	var mob: Node2D = null
	for m in get_tree().get_nodes_in_group("enemy"):
		if m.global_position.x > 400.0 and m.global_position.y < 400.0:
			mob = m
			break
	if mob != null:
		# 站到怪左边 44px：如果还重叠说明碰撞没生效
		player.global_position = Vector2(mob.global_position.x - 44.0, 240.0)
		player.set("velocity", Vector2.ZERO)
		print("怪原点 %s 碰撞底 %.1f" % [mob.global_position, mob.global_position.y + 20.0])
		var sk: Sprite2D = mob.get_node_or_null("Visuals/Skin")
		if sk != null:
			print("Skin 中心 %.1f → 显示底边 %.1f" % [sk.position.y, sk.position.y + 48.0])
	await _frames(25)
	# 让玩家朝右走两步，看是否被怪挡住
	Input.action_press("move_right")
	await _frames(30)
	Input.action_release("move_right")
	await _frames(6)
	if mob != null:
		print("玩家 x=%.1f 怪 x=%.1f 间距=%.1f" % [
			player.global_position.x, mob.global_position.x,
			mob.global_position.x - player.global_position.x])
	if mob != null:
		var bar: Node2D = mob.get_node_or_null("HealthBar")
		var bg: ColorRect = mob.get_node_or_null("HealthBar/BG")
		if bar != null:
			print("HealthBar 局部 y=%.1f 全局 y=%.1f" % [bar.position.y, bar.global_position.y])
		if bg != null:
			print("BG pos=%s size=%s" % [bg.position, bg.size])
		print("怪原点 y=%.1f  Skin 顶=%.1f" % [mob.global_position.y, mob.global_position.y - 76.0])
	await _shot("verify_fix.png")
	print("done")
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://build/shots/" + name)
	print("saved", name)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
