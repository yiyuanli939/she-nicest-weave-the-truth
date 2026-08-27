extends SceneTree
## M3 全流程验收:清档 → 主菜单 → 逐关(17)入场对话→解题→「下一关」推进 →
## 选关页金印 → 笔记本 5 条 → 重进旧关棋盘恢复。
##   godot --path . --script res://tests/visual_smoke_m3.gd
## 退出码 0 = 全部通过。截图在 tests/screenshots/。

const OUT_DIR := "res://tests/screenshots"

var _fails := 0


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("✓ ", msg)
	else:
		print("✗ ", msg)
		_fails += 1


func _game() -> Node:
	return root.get_node("/root/Game")


func _shot(tag: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, tag])


func _settle() -> void:
	await process_frame
	await process_frame


## 进关前的全屏开场对话:一键播完并等切入棋盘
func _skip_story() -> void:
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()


func _run() -> void:
	await _settle()
	var game := _game()
	_check(game != null, "Game autoload 存在")
	game.save.wipe()

	# 主菜单
	change_scene_to_file("res://ui/main_menu.tscn")
	await _settle()
	_shot("m3_menu")
	_check(current_scene is MainMenu, "主菜单加载")

	# 逐关通关:第一关从菜单逻辑入口进,之后走「下一关」按钮
	game.start_level(game.first_unsolved())
	await _settle()
	for i in 17:
		await _skip_story()   # 开场对话在进关前的 StoryScene 播,先跳过
		var scene := current_scene as LevelScene
		if scene == null:
			_check(false, "第 %d 关场景未加载" % (i + 1))
			break
		var lv: LevelDef = game.current
		var board: ProofBoard = scene.find_children("*", "ProofBoard", true, false)[0]
		LevelSolutions.apply(scene, board, lv.id)
		await _settle()
		_check(scene.session.is_solved(), "%s %s 通关" % [lv.id, lv.title])
		if lv.id == &"l08":
			_shot("m3_l08_board")
		if game.next_level() != null:
			scene._on_next()
			await _settle()

	_check(game.save.solved.size() == 17, "存档记录 17 关 (得 %d)" % game.save.solved.size())
	_check(game.save.notebook.size() == 5, "笔记本解锁 5 条 (得 %d)" % game.save.notebook.size())

	# 选关页金印
	game.goto_select()
	await _settle()
	_shot("m3_select_all_solved")
	_check(current_scene is LevelSelect, "选关页加载")

	# 全屏开场对话展示 + 点击推进回归(无跳过键:每行点两次 = 全显→下一句,播完即关)
	game.start_level(game.catalog.all_levels()[15])   # l16:小机 panic 台词
	await _settle()
	var story := current_scene as StoryScene
	_check(story != null, "l16 进关前应是全屏开场对话场景")
	_shot("m3_l16_dialogue")
	if story != null:
		_check(story._dialogue.visible, "l16 开场对话显示")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = true
		for j in game.current.intro_dialogue.lines.size():
			story._dialogue._on_click(mb)   # 打字中:点击全显
			story._dialogue._on_click(mb)   # 已全显:点击下一句/关闭
		_check(not story._dialogue.visible, "点击播完最后一句后再点即关闭")
		await _settle()
		_check(current_scene is LevelScene, "对话播完自动进棋盘")

	# 棋盘恢复:重进 l03 应已是通关棋盘
	game.start_level(game.catalog.all_levels()[2])
	await _settle()
	await _skip_story()
	var l03 := current_scene as LevelScene
	_check(l03.session.get_node_ids().size() == 4, "l03 棋盘恢复(线轴+目标+两台仪器)")
	_check(l03.session.is_solved(), "l03 恢复后仍通关")
	_shot("m3_l03_restored")

	# 主菜单笔记本
	game.goto_menu()
	await _settle()
	var menu := current_scene as MainMenu
	menu._notebook_ui.open(game.notebook, game.save.notebook)
	await _settle()
	_shot("m3_notebook")

	print("M3_SMOKE_FAILS=", _fails)
	quit(_fails)
