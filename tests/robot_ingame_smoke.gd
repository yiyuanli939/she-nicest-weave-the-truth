extends SceneTree
## 游戏内机器人联动冒烟(需桥接+实机在线,且已跑过 m3 全通存档):
##   godot --path . --script res://tests/robot_ingame_smoke.gd
## 验证:l15 开场对话行 robot_cue=glitch 触发 → 已通关棋盘载入 celebrate →
##       l03 接冲突线 encourage → cal_set 回 cal_done。退出码 = 失败数。

var _fails := 0
var _events: Array[Dictionary] = []


func _initialize() -> void:
	_run()


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


func _run() -> void:
	await process_frame
	await process_frame
	var game := root.get_node("Game")
	var robot := root.get_node("Robot")
	var deadline := Time.get_ticks_msec() + 5000
	while not robot.connected and Time.get_ticks_msec() < deadline:
		await process_frame
	if not robot.connected:
		print("✗ 连不上桥接")
		quit(1)
		return
	robot.robot_event.connect(func(d: Dictionary) -> void: _events.append(d))

	# 1) l15:进关 → 全屏开场对话首行(档案员,cue=glitch);播完进棋盘
	game.start_level(game.catalog.all_levels()[14])
	await _wait(2.5)
	var story := current_scene as StoryScene
	_check(story != null and story._dialogue.visible, "l15 全屏开场对话显示(首行含 glitch cue)")
	if story != null:
		story.finish()
	await _wait(1.0)
	var scene := current_scene as LevelScene
	_check(scene != null and scene.session.is_solved(), "l15 已通关棋盘载入(恢复不应重复庆祝)")
	await _wait(4.0)

	# 2) l03:接一条冲突线 → encourage
	game.start_level(game.catalog.all_levels()[2])
	await _wait(1.5)
	story = current_scene as StoryScene
	if story != null:
		story.finish()
		await _wait(0.5)
	scene = current_scene as LevelScene
	var board: ProofBoard = scene.find_children("*", "ProofBoard", true, false)[0]
	var s := scene.session
	board._on_connection_request("n%d" % s.assumption_ids[0], 0, "n%d" % s.goal_id, 0)
	await _wait(1.0)
	var conflict := false
	for w in s.get_wires():
		conflict = conflict or w.state == ProofSession.WireState.CONFLICT
	_check(conflict, "l03 冲突线已出现(应已发 encourage)")
	s.undo()
	await _wait(3.0)

	# 3) 校准:cal_set → cal_done 事件
	robot.save_look_here()
	await _wait(2.0)
	var cal_done := false
	for e in _events:
		cal_done = cal_done or e.get("evt", "") == "cal_done"
	_check(cal_done, "cal_set → 收到 cal_done(得 %d 条事件)" % _events.size())

	robot.cue("idle")
	robot.send({cmd = "gimbal", pan = 90, tilt = 90})
	await _wait(0.5)
	print("INGAME_SMOKE_FAILS=", _fails)
	robot._ws.close()
	await process_frame
	quit(_fails)
