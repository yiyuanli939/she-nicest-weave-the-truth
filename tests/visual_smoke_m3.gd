extends SceneTree
## M3 全流程验收:清档 → 主菜单 → 逐关(16)开场对话→解题→通关弹窗「织成了」真实点击「继续」推进 →
## 选关页 → 重进旧关棋盘恢复(v1.2:已通关的关重开 = 目标线拆掉的「差一步」态,接回即弹窗)→ 关内笔记抽屉。
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


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


## 走真实输入管线点一下(按下 + 抬起),坐标为视口全局坐标
func _click(at: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev, true)   # 坐标是 3840×2160 逻辑视口坐标(窗口比它小)


func _button_named(from: Node, text: String) -> Button:
	for b in from.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


## 目标织机的输入口是否有线
func _goal_wired(scene: LevelScene) -> bool:
	for w in scene.session.get_wires():
		if w.to_id == scene.session.goal_id:
			return true
	return false


## 把脚本化解法的最后一根线(每关都是 → 目标织机)接回去:恢复盘上机器 id 升序 = 摆放顺序 m0..mN
func _reconnect_goal(scene: LevelScene, level_id: StringName) -> void:
	var s := scene.session
	var machines: Array[int] = []
	for id in s.get_node_ids():
		if s.describe_node(id).type == ProofSession.NodeType.MACHINE:
			machines.append(id)
	machines.sort()
	var last: Array = LevelSolutions.DATA[level_id].w[-1]
	s.connect_wire(LevelSolutions._resolve(last[0], s, machines), last[1], s.goal_id, last[3])


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
	AudioServer.set_bus_mute(0, true)   # 跑测试别真出声
	var bgm := root.get_node("/root/Bgm")

	# 主菜单
	change_scene_to_file("res://ui/main_menu.tscn")
	await _settle()
	_shot("m3_menu")
	_check(current_scene is MainMenu, "主菜单加载")
	_check(bgm.slot == &"title" and bgm.is_playing(), "主菜单 BGM = 标题曲")

	# 逐关通关:第一关从菜单逻辑入口进,之后走通关弹窗「继续」(真实点击)
	game.start_level(game.first_unsolved())
	await _settle()
	for i in 16:
		await _skip_story()   # 开场对话在进关前的 StoryScene 播,先跳过
		var scene := current_scene as LevelScene
		if scene == null:
			_check(false, "第 %d 关场景未加载" % (i + 1))
			break
		var lv: LevelDef = game.current
		_check(bgm.slot == bgm.slot_for_chapter(game.current_chapter()), "%s BGM 槽位随章节" % lv.id)
		var robot := root.get_node("/root/Robot")
		if lv.id == &"l11":
			_check(not robot.broken, "l11(3-1)进关小机还没坏")
		elif lv.id == &"l12":
			_check(robot.broken, "l12(3-2)起小机坏掉(3-1 通关瞬间)")
		elif lv.id == &"l14":
			_check(robot.broken and not robot.sent("say", "calm"), "第四章小机仍坏(修好在结局)")
		var board: ProofBoard = scene.find_children("*", "ProofBoard", true, false)[0]
		LevelSolutions.apply(scene, board, lv.id)
		await _settle()
		_check(scene.session.is_solved(), "%s %s 通关" % [lv.id, lv.title])
		if i == 0:
			# 关内曲真的在响:wav 循环点缺 loop_end 时混 1 帧即停、playing 翻 false、播放头停在 0
			# (自动通关跑得快,从故事界面起播到这里可能不到半秒,只要求 > 0)
			var lp: AudioStreamPlayer = bgm.active_player()
			_check(lp.playing and lp.get_playback_position() > 0.0,
					"关内曲播放头在推进(playing=%s pos=%.2f)" % [lp.playing, lp.get_playback_position()])
		if lv.id == &"l11":
			_check(robot.broken and robot.sent("anim", "panic") and not robot.sent("say", "panic"),
					"3-1 通关瞬间小机坏掉(乱动 + 音效,没有台词)")
		if lv.id == &"l09":
			_shot("m3_l09_board")
		_check(scene._win_popup.visible and _button_named(scene, "下一关") == null, "%s 通关弹出「织成了」弹窗,工具条没有「下一关」" % lv.id)
		if i == 0:
			_shot("m3_win_popup")
		if game.next_level() != null:
			_click(scene._win_popup._continue_btn.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)   # 真实点击弹窗「继续」
			await _settle()

	_check(game.save.solved.size() == 16, "存档记录 16 关 (得 %d)" % game.save.solved.size())

	# 选关页金印
	game.goto_select()
	await _settle()
	_shot("m3_select_all_solved")
	_check(current_scene is LevelSelect, "选关页加载")

	# 全屏开场对话展示 + 点击推进回归(无跳过键:每行点两次 = 全显→下一句,播完即关)
	game.start_level(game.catalog.all_levels()[0])   # l01:正式台词 1-1
	await _settle()
	var story := current_scene as StoryScene
	_check(story != null, "l01 进关前应是全屏开场对话场景")
	_shot("m3_l01_dialogue")
	if story != null:
		_check(story._dialogue.visible, "l01 开场对话显示")
		# 走真实输入管线,且点在台词正文正中(曾是死区:面板吃掉点击、捕捉层收不到)
		var at: Vector2 = story._dialogue._text.get_global_rect().get_center()
		for j in game.current.intro_dialogue.lines.size():
			_click(at, MOUSE_BUTTON_LEFT)   # 打字中:点击全显
			_click(at, MOUSE_BUTTON_LEFT)   # 已全显:点击下一句/关闭
		_check(not story._dialogue.visible, "点在面板上也能推进,播完最后一句再点即关闭")
		await _settle()
		_check(current_scene is LevelScene, "对话播完自动进棋盘")

	# 结局(剧情表注意事项②):l16 无进关对话;通关后「继续」→ 4-3 → 感谢游玩黑屏 → 开发者信息
	game.start_level(game.catalog.all_levels()[15])
	await _settle()
	_check(current_scene is LevelScene, "l16(4-3 移到通关后)进关直接是棋盘")
	var l16 := current_scene as LevelScene
	_check(not l16._win_popup.visible and not l16.session.is_solved() and not _goal_wired(l16),
			"已通关的 l16 重开:棋盘恢复但目标线拆掉(差一步),不弹通关弹窗")
	var robot_end := root.get_node("/root/Robot")
	_check(robot_end.broken, "结局前小机仍是坏的")
	_reconnect_goal(l16, &"l16")   # 玩家把最后一根线接回去 = 通关
	await _settle()
	_check(l16.session.is_solved() and l16._win_popup.visible, "l16 接回目标线 → 通关 → 弹窗")
	_click(l16._win_popup._continue_btn.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)   # 末关「继续」= 结局
	await _settle()
	var outro := current_scene as StoryScene
	_check(outro != null and game.current.outro_dialogue != null and game.current.outro_dialogue.lines.size() > 0,
			"「继续」→ 全屏结局剧情(l16.outro_dialogue)")
	if outro != null:
		_shot("m3_l16_outro")
		outro.finish()
		await _wait(StoryScene.THANKS_FADE_SEC + 0.3)
		_shot("m3_thanks")
		await _wait(StoryScene.THANKS_HOLD_SEC + 0.6)
		await _settle()
		_check(current_scene is CreditsScene, "感谢游玩黑屏后淡出到开发者信息页")
		_check(not robot_end.broken and robot_end.sent("say", "calm"), "结局黑屏时小机修好(calm)")
		_shot("m3_credits")

	# 棋盘恢复:重进已通关的 l04 = 记录的棋盘 + 目标线拆掉(差一步)
	game.start_level(game.catalog.all_levels()[3])
	await _settle()
	await _skip_story()
	var l04 := current_scene as LevelScene
	_check(l04.session.get_node_ids().size() == 4, "l04(原第三纹 B & A)棋盘恢复(线轴+目标+两台仪器)")
	_check(not l04.session.is_solved() and not _goal_wired(l04) and not l04._win_popup.visible,
			"l04 已通关重开:目标线拆掉、未通关、不弹窗")
	_shot("m3_l04_restored")

	# 右键删节点回归(真实输入,点在节点正中):右键仪器 → 删;右键线轴 → 不删;Ctrl+Z 撤回
	var l04_board: ProofBoard = l04.find_children("*", "ProofBoard", true, false)[0]
	var spool_node := l04_board.get_node("n%d" % l04.session.assumption_ids[0]) as MachineNode
	_click(spool_node.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await _settle()
	_check(l04.session.get_node_ids().size() == 4, "右键线轴不应删除")
	var machine_id := -1
	for id in l04.session.get_node_ids():
		if l04.session.describe_node(id).type == ProofSession.NodeType.MACHINE:
			machine_id = id
			break
	var machine_node := l04_board.get_node("n%d" % machine_id) as MachineNode
	_click(machine_node.get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	await _settle()
	_check(l04.session.get_node_ids().size() == 3, "右键仪器正中(曾是 spacer 死区)应删除该节点")
	_check(l04_board.get_node_or_null("n%d" % machine_id) == null, "视图节点应同步移除")
	l04.session.undo()
	await _settle()
	_check(l04.session.get_node_ids().size() == 4 and not l04.session.is_solved() and not _goal_wired(l04), "撤销后节点恢复(仍是差一步态)")

	# 关内诺拉的笔记抽屉:只显示本关上架仪器的说明(l04 第一章 = 2 台),划出后截图
	l04._on_open_notebook()
	await l04._notebook_ui.slide_finished
	await _settle()
	_check(l04._notebook_ui.is_open() and l04._notebook_ui._entries.size() == 2, "笔记抽屉划出,第一章两台仪器说明")
	_shot("m3_notebook")

	print("M3_SMOKE_FAILS=", _fails)
	quit(_fails)
