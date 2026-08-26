extends SceneTree
## 手势遥操整合冒烟(需桥接在跑;teleop 用 --test 合成手,无需摄像头):
##   godot --path . --script res://tests/teleop_smoke.gd
## 断言:teleop_hand 包到达 → 光标显示且移动 → 合成捏合注入左键(全屏探针接到点击)
##       → teleop_stop 后进程退出、光标随手消失。退出码 = 失败数。

var _fails := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("✓ ", msg)
	else:
		print("✗ ", msg)
		_fails += 1


func _wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < end:
		await process_frame


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var robot := root.get_node("Robot")
	var deadline := Time.get_ticks_msec() + 5000
	while not robot.connected and Time.get_ticks_msec() < deadline:
		await process_frame
	if not robot.connected:
		print("✗ 连不上桥接(先 node hardware/bridge/bridge.js)")
		quit(1)
		return

	# 全屏探针:证明合成鼠标事件真的抵达 UI 层
	var probe := Button.new()
	probe.flat = true
	probe.modulate.a = 0.05
	probe.set_anchors_preset(Control.PRESET_FULL_RECT)
	var probe_clicks := [0]
	probe.pressed.connect(func() -> void: probe_clicks[0] += 1)
	root.add_child(probe)

	var packets := [0]
	robot.teleop_hand.connect(func(_d: Dictionary) -> void: packets[0] += 1)

	_check(robot.teleop_start(["--test", "--duration", "11"]), "teleop --test 进程启动")
	await _wait(2.0)
	var cursor_shown: bool = robot.gesture._cursor.visible
	var p1: Vector2 = robot.gesture._cursor.position
	await _wait(4.5)
	var p2: Vector2 = robot.gesture._cursor.position
	_check(packets[0] > 40, "手部包持续到达(收到 %d)" % packets[0])
	_check(cursor_shown and robot.gesture._cursor.visible, "虚拟光标显示")
	_check(p1.distance_to(p2) > 30.0, "光标随合成手移动(位移 %.0f px)" % p1.distance_to(p2))
	_check(robot.gesture.clicks >= 1, "捏合注入左键(%d 次)" % robot.gesture.clicks)
	_check(probe_clicks[0] >= 1, "点击真实抵达 UI 控件(探针 %d 次)" % probe_clicks[0])

	robot.teleop_stop()
	await _wait(1.5)
	_check(not robot.teleop_running(), "关闭后进程已退出")
	var n0: int = packets[0]
	await _wait(1.5)
	_check(packets[0] == n0, "关闭后不再有手部包")
	_check(not robot.gesture._cursor.visible, "光标已隐藏")

	robot.send({cmd = "gimbal", pan = 90, tilt = 90})
	print("TELEOP_SMOKE_FAILS=", _fails)
	robot._ws.close()
	await process_frame
	quit(_fails)
