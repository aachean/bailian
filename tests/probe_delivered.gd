extends Node
## 交付状态探针：按「玩家拿到手」的方式实例化 test_room，
## 不改任何属性，直接观察 Walker 的 AI 行为。
## 存在的意义：自动验收会临时改场景（关/开 AI），那条路径测不出交付环境的错误 ——
## 「小怪不会巡逻也不会还手」就是这么漏掉的。
##
##     godot --headless --fixed-fps 60 --path <项目根> res://tests/probe_delivered.tscn

const ROOM := preload("res://scenes/stages/test_room.tscn")


func _ready() -> void:
	var room := ROOM.instantiate()
	add_child(room)
	# 先把玩家放到最右边 —— 模拟「玩家还在远处没惊动它」，
	# 这样才能真正观察到巡逻（玩家出生点 200 离它太近，开局就会被 aggro）
	var player := room.get_node("Player")
	player.global_position = Vector2(560.0, 288.0)
	player.velocity = Vector2.ZERO
	await _frames(30)

	var walker := room.get_node_or_null("Walker")
	if walker == null:
		printerr("[probe] 找不到 Walker")
		get_tree().quit(1)
		return

	print("[probe] ai_enabled=%s  state=%d（0=巡逻）" % [str(walker.ai_enabled), int(walker.state)])
	var x0: float = walker.global_position.x
	var turned := 0
	var last_dir := 1.0
	for i in 300:
		await get_tree().physics_frame
		var dir := signf(walker.velocity.x)
		if dir != 0.0 and dir != last_dir:
			turned += 1
			last_dir = dir
	var moved: float = absf(walker.global_position.x - x0)
	print("[probe] 5 秒巡逻：移动 %.1f px，折返 %d 次（>10 px 且折返 = 在巡逻）" % [moved, turned])

	# 玩家走近 → 应进入追击并攻击
	player.global_position = Vector2(85.0, 288.0)
	player.velocity = Vector2.ZERO
	var saw_chase := false
	var hit := false
	var x1: float = walker.global_position.x
	var moved2 := 0.0
	var hb := walker.get_node("Hitbox") as Hitbox
	var logged := 0
	for i in 300:
		await get_tree().physics_frame
		if int(walker.state) == 1:      # CHASE
			saw_chase = true
		if hb != null and hb.is_active() and logged < 6:
			logged += 1
			var r := hb.rect()
			print("[probe] 判定帧 %d：判定框 %s，玩家在 x=%.1f y=%.1f" % [
				i, str(r), player.global_position.x, player.global_position.y])
		moved2 = walker.global_position.x - x1
		var hp: int = (player.get_node("Health") as Health).hp
		if hp < 100:
			hit = true
			break
	print("[probe] 走近后：进入追击=%s，逼近 %.1f px，玩家掉血=%s" % [
		str(saw_chase), moved2, str(hit)])
	print("[probe] 调试：walker 出招 %d 次，挨打 %d 次，最终位置 x=%.0f（玩家 x=%.0f）" % [
		int(walker.attacks_started), int(player.get("hurts_taken")),
		walker.global_position.x, player.global_position.x])

	var ok: bool = walker.ai_enabled and moved > 10.0 and turned > 0 and saw_chase and hit
	print("[probe] 结论：%s" % ("交付环境 AI 正常" if ok else "交付环境 AI 异常"))
	get_tree().quit(0 if ok else 1)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
