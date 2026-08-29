extends SceneTree
## 实机:「请指导我」的回头动作 —— 底部云台转到右极限 → 回正 → 转到左极限 → 回正(需先 bash hardware/run_robot.sh)。
##   godot --headless --path . --script res://tests/robot_turn_smoke.gd
## 每段转动后等固件的 gimbal ack(证明命令执行到了 PWM 写入);退出码 = 失败数。摄像头物理判定另见 hardware/cam_check.sh。

var _fails := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var robot := root.get_node("/root/Robot")
	var deadline := Time.get_ticks_msec() + 5000
	while not robot.connected and Time.get_ticks_msec() < deadline:
		await process_frame
	if not robot.connected:
		print("TURN_SMOKE: 连不上桥接(先 bash hardware/run_robot.sh)")
		quit(1)
		return
	print("TURN_SMOKE: 已连桥接,串口在线=", robot.serial_open)
	robot.send({cmd = "gimbal", pan = 90, tilt = 90})
	await _wait(0.8)
	for dir in ["right", "left"]:
		robot.set_turn_dir(dir)
		robot.sent_log.clear()
		var target: int = robot.turn_target(dir)
		print("  转到", "右" if dir == "right" else "左", "极限(pan=", target, ")")
		robot.turn_to_limit()
		await _wait(1.5)
		var ack: Dictionary = robot.last_gimbal_ack
		var ok: bool = int(ack.get("pan", -1)) == target
		_fails += 0 if ok else 1
		print("    发出 gimbal ", robot.sent_log.size(), " 条;固件 ack pan=", ack.get("pan", "无"), " → ", "OK" if ok else "FAIL(固件没回到位)")
		print("  回正")
		robot.return_center()
		await _wait(1.5)
		ack = robot.last_gimbal_ack
		ok = int(ack.get("pan", -1)) == 90
		_fails += 0 if ok else 1
		print("    固件 ack pan=", ack.get("pan", "无"), " → ", "OK" if ok else "FAIL")
	robot.set_turn_dir("right")
	print("TURN_SMOKE: 完成,失败 ", _fails)
	robot._ws.close()
	await process_frame
	quit(_fails)


func _wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < end:
		await process_frame
