extends SceneTree
## M1 开窗冒烟:模拟玩家路径(仪器架放置 + connection_request)完成 A∧B ⊢ B∧A,
## 截图后退出。运行:
##   godot --path . --script res://tests/visual_smoke.gd
## 截图落在 res://tests/screenshots/ 下;退出码 0 = 通关且无脚本错误。

const OUT_DIR := "res://tests/screenshots"


func _initialize() -> void:
	var scene: LevelScene = (load("res://ui/level_scene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_run(scene)


func _run(scene: LevelScene) -> void:
	await process_frame
	await process_frame
	var session := scene.session
	var board: ProofBoard = scene.find_children("*", "ProofBoard", true, false)[0]

	# 拆股机 + 并织机,走 palette 同款入口
	board.place_machine_at_center(&"and_elim")
	board.place_machine_at_center(&"and_intro")
	var ids := session.get_node_ids()
	var elim: int = ids[-2]
	var intro: int = ids[-1]
	session.set_node_position(elim, Vector2(320, 120))
	session.set_node_position(intro, Vector2(560, 120))
	board.apply_positions()
	var spool: int = session.assumption_ids[0]
	await process_frame

	# 接线走 view 的 connection_request 路径(与鼠标一致)
	board._on_connection_request("n%d" % spool, 0, "n%d" % elim, 0)
	board._on_connection_request("n%d" % elim, 0, "n%d" % intro, 1)   # 交叉:P→右口
	board._on_connection_request("n%d" % elim, 1, "n%d" % intro, 0)   # Q→左口
	board._on_connection_request("n%d" % intro, 0, "n%d" % session.goal_id, 0)
	await process_frame
	await process_frame

	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	img.save_png(OUT_DIR + "/m1_solved.png")

	# 错误路径:线轴直连目标 → 冲突徽章
	board._on_connection_request("n%d" % spool, 0, "n%d" % session.goal_id, 0)
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(OUT_DIR + "/m1_conflict.png")
	var conflict_state := session.get_wire_state(spool, 0, session.goal_id, 0)
	session.undo()
	await process_frame

	print("SOLVED=", session.is_solved(), " CONFLICT_SEEN=", conflict_state == ProofSession.WireState.CONFLICT)
	quit(0 if session.is_solved() and conflict_state == ProofSession.WireState.CONFLICT else 1)
