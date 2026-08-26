extends SceneTree
## 游戏 → 桥接 → 实机联动冒烟(需先跑 hardware/bridge 且机器人在线):
##   godot --headless --path . --script res://tests/robot_smoke.gd
## 依次触发 greet/confused/panic/celebrate/归位;退出码 0 = WebSocket 成功连上桥接。


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame          # 等 autoload 进树
	var robot := root.get_node("Robot")
	var deadline := Time.get_ticks_msec() + 5000
	while not robot.connected and Time.get_ticks_msec() < deadline:
		await process_frame
	if not robot.connected:
		print("ROBOT_SMOKE: 连不上桥接(先 npm run bridge)")
		quit(1)
		return
	print("ROBOT_SMOKE: 已连桥接,开始动作序列")
	robot.send({cmd = "text", s = "SHE NICEST"})
	await _wait(1.2)
	for c in ["greet", "confused", "hint", "panic", "celebrate", "calm"]:
		print("  cue: ", c)
		robot.cue(c)
		await _wait(6.0)
	robot.cue("idle")
	robot.send({cmd = "gimbal", pan = 90, tilt = 90})
	await _wait(0.5)
	print("ROBOT_SMOKE: 完成")
	robot._ws.close()
	await process_frame
	quit(0)


func _wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < end:
		await process_frame
