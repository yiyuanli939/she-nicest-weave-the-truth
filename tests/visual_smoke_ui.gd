extends SceneTree
## UI 交互穷举(全部走 Window.push_input 真实输入管线,不直接调回调):
##   全屏对话每个点击落点 / 立绘与背景贴图槽位 / 无对话关直接进棋盘 /
##   右键删除的每个落点 / 拖动中右键不误删 / Delete 键 / 撤销重做快捷键 /
##   钉按钮 → 编辑器 → 钉住 / 幽灵态切换 / 连线徽章 / HUD 按钮 / 选关页真实点击进关。
##   godot --path . --script res://tests/visual_smoke_ui.gd
## 退出码 = 失败数。

var _fails := 0


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("✓ ", msg)
	else:
		print("✗ ", msg)
		_fails += 1


func _settle() -> void:
	await process_frame
	await process_frame


func _click(at: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		root.push_input(ev)


func _press(at: Vector2, button: MouseButton, pressed: bool, mask: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = mask
	ev.position = at
	ev.global_position = at
	root.push_input(ev)


func _action(name: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = name
		ev.pressed = pressed
		root.push_input(ev)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		root.push_input(ev)


func _button_named(from: Node, text: String) -> Button:
	for b in from.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _make_level(id: String, dlg: DialogueRes) -> LevelDef:
	var lv := LevelDef.new()
	lv.id = StringName(id)
	lv.title = "UI 测试关"
	lv.assumptions = ["A & B"]
	lv.goal = "B & A"
	lv.allowed_rules = [&"and_intro", &"and_elim", &"or_intro", &"imp_intro"]
	lv.atoms = [&"A", &"B"]
	lv.intro_dialogue = dlg
	return lv


func _run() -> void:
	await _settle()
	var game := root.get_node("/root/Game")

	# ---- A. 全屏对话:3 行两侧交替,带立绘/背景贴图与地点铭牌 ----
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	var tex := ImageTexture.create_from_image(img)
	var dlg := DialogueRes.new()
	dlg.location_title = "测试地点"
	dlg.background = tex
	for i in 3:
		var line := DialogueLine.new()
		line.speaker = ["阿梭", "小机", "阿梭"][i]
		line.text = "第 %d 句台词" % i
		line.side_right = i == 1
		if i == 1:
			line.portrait = tex
		dlg.lines.append(line)
	game.start_level(_make_level("ui_dlg", dlg))
	await _settle()
	var story := current_scene as StoryScene
	_check(story != null, "有对话的关先进 StoryScene")
	if story != null:
		var has_title := false
		for l in story.find_children("*", "Label", true, false):
			has_title = has_title or (l as Label).text == "测试地点"
		_check(has_title, "地点铭牌显示 location_title")
		_check(story._bg_slot.get_child_count() == 1 and story._bg_slot.get_child(0) is TextureRect, "背景贴图槽位生效")
		var box: DialogueBox = story._dialogue
		var spots := [
			["说话人名牌", _center(box._speaker)],
			["台词正文", _center(box._text)],
			["面板左上角", box._panel.get_global_rect().position + Vector2(6, 6)],
			["面板外(屏幕左上)", Vector2(30, 30)],
			["立绘区域", _center(story._portraits[0])],
			["插图区域", _center(story._bg_slot)],
		]
		var expected_idx := 0
		for n in 3:
			_check(box._idx == expected_idx, "第 %d 句正在显示(idx=%d)" % [n, box._idx])
			if n == 1:
				_check(story._portraits[1].visible and story._portraits[1].get_child(0) is TextureRect,
						"右侧立绘用贴图槽位")
				_check(story._portraits[0].modulate != Color.WHITE, "非说话侧立绘压暗")
			var s1: Array = spots[(2 * n) % spots.size()]
			var s2: Array = spots[(2 * n + 1) % spots.size()]
			_click(s1[1], MOUSE_BUTTON_LEFT)
			_check(box._text.visible_characters == box._text.get_total_character_count(),
					"点在「%s」:打字中点击整句显示" % s1[0])
			_click(s2[1], MOUSE_BUTTON_LEFT)
			expected_idx += 1
			if n < 2:
				_check(box._idx == expected_idx, "点在「%s」:推进到下一句" % s2[0])
		_check(not box.visible, "最后一句后再点即关闭")
		await _settle()
		_check(current_scene is LevelScene, "对话播完自动进棋盘")
		_check(story == null or not is_instance_valid(story), "StoryScene 已释放")

	# ---- B. 没有对话的关:直接进棋盘 ----
	game.start_level(_make_level("ui_board", null))
	await _settle()
	var scene := current_scene as LevelScene
	_check(scene != null, "无对话的关直接进 LevelScene")
	if scene == null:
		_finish()
		return

	# ---- C. HUD:没有撤销/重做按钮,有重置 ----
	_check(_button_named(scene, "撤销") == null and _button_named(scene, "重做") == null, "HUD 无撤销/重做按钮")
	_check(_button_named(scene, "重置") != null, "HUD 有重置按钮")
	_check(_button_named(scene, "示答") == null, "没有脚本化解法的关不显示示答按钮")

	# ---- D. 仪器架真实点击放置岔纹机 ----
	var board: ProofBoard = scene._board
	var s := scene.session
	_click(_center(_button_named(scene._palette, "岔纹机")), MOUSE_BUTTON_LEFT)
	await _settle()
	var ids := s.get_node_ids()
	_check(ids.size() == 3, "点仪器架按钮放置一台岔纹机(得 %d 节点)" % ids.size())
	var mid: int = ids[-1]
	s.set_node_position(mid, Vector2(360, 360))   # 挪开:palette 默认落在视野中心,会和后面放的机器重叠
	board.apply_positions()
	await _settle()
	var mn := board.get_node("n%d" % mid) as MachineNode

	# ---- E. 幽灵态:未连未钉全幽灵;钉上口后上口实显;接线后入口实显 ----
	_check(mn._in_views[0].ghost and mn._out_views[0].ghost and mn._out_views[1].ghost, "新放置的仪器所有口都是幽灵")
	_click(_center(_button_named(mn, "钉上口")), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(scene._editor.visible, "点「钉上口」打开纹样编辑器")
	scene._editor.tree = FormulaParser.parse("B")
	scene._editor._confirm.pressed.emit()
	await _settle()
	mn = board.get_node("n%d" % mid) as MachineNode
	_check(s.describe_node(mid).pinned.get(0, "") == "B", "钉住后模型记录 B")
	_check(not mn._out_views[0].ghost and mn._out_views[1].ghost, "钉住的上口实显,下口仍幽灵")
	_check(mn._out_views[0].get_parent().get_child(0).text.begins_with("📌"), "钉住的口标签带 📌")
	board._on_connection_request("n%d" % s.assumption_ids[0], 0, "n%d" % mid, 0)
	await _settle()
	mn = board.get_node("n%d" % mid) as MachineNode
	_check(not mn._in_views[0].ghost, "接上线的入口实显")
	_check(s.get_output_pattern(mid, 0).equals(FormulaParser.parse("(A & B) | B")), "上口织出 (A∧B)∨B")

	# ---- F. 连线徽章:欠定线「? 欠定」→ 钉住后 OK 无浮层;结构不合「☠ 冲突」;断线后无浮层 ----
	_click(_center(_button_named(scene._palette, "并织机")), MOUSE_BUTTON_LEFT)
	await _settle()
	var join: int = s.get_node_ids()[-1]
	s.set_node_position(join, Vector2(620, 360))   # 挪开,别压在岔纹机上
	board.apply_positions()
	await _settle()
	board._on_connection_request("n%d" % mid, 1, "n%d" % join, 0)   # 下口 ?R∨(A∧B) → 并织机入口:没染完
	await _settle()
	_check(board._overlay._chips.size() == 1 and (board._overlay._chips[0].ctrl as Control).get_child(0).text.begins_with("?"),
			"欠定线挂「? 欠定」徽章")
	_click(_center(_button_named(board.get_node("n%d" % mid), "钉下口")), MOUSE_BUTTON_LEFT)
	scene._editor.tree = FormulaParser.parse("A")
	scene._editor._confirm.pressed.emit()
	await _settle()
	_check(board._overlay._chips.is_empty(), "钉下口后这条线 OK,浮层消失")
	board._on_connection_request("n%d" % mid, 1, "n%d" % s.goal_id, 0)   # A∨(A∧B) → 目标 B∧A:∨ 对 ∧
	await _settle()
	_check(board._overlay._chips.size() == 1 and (board._overlay._chips[0].ctrl as Control).get_child(0).text.begins_with("☠"),
			"连接词对不上的线挂「☠ 冲突」徽章")
	board._on_disconnection_request("n%d" % mid, 1, "n%d" % s.goal_id, 0)
	await _settle()
	_check(board._overlay._chips.is_empty(), "断线后没有浮层")
	s.remove_machine(join)
	await _settle()

	# ---- G. 右键删除的每个落点(删 → Ctrl+Z 撤回 → 下一个落点) ----
	var spots_fn: Array[Callable] = [
		func(m: MachineNode) -> Vector2: return _center(m.get_titlebar_hbox().get_child(0)),
		func(m: MachineNode) -> Vector2: return _center(m._in_views[0]),
		func(m: MachineNode) -> Vector2: return _center(m._in_views[0].get_parent().get_child(0)),
		func(m: MachineNode) -> Vector2: return _center(m._in_views[0].get_parent().get_parent().get_child(1)),
		func(m: MachineNode) -> Vector2: return _center(m._out_views[1]),
		func(m: MachineNode) -> Vector2: return _center(m),
	]
	var spot_names := ["标题文字", "输入口纹样", "输入口标签", "行中间 spacer", "输出口纹样", "节点几何中心"]
	for k in spots_fn.size():
		mn = board.get_node("n%d" % mid) as MachineNode
		_click(spots_fn[k].call(mn), MOUSE_BUTTON_RIGHT)
		await _settle()
		_check(s.describe_node(mid) == null and board.get_node_or_null("n%d" % mid) == null,
				"右键「%s」删除仪器" % spot_names[k])
		_action("ui_undo")
		await _settle()
		_check(s.describe_node(mid) != null and board.get_node_or_null("n%d" % mid) != null,
				"Ctrl+Z 撤回删除(%s)" % spot_names[k])
	mn = board.get_node("n%d" % mid) as MachineNode
	_check(mn._out_views[0].get_parent().get_child(0).text.begins_with("📌"), "撤回后钉纹样标签仍在")

	# ---- H. 拖动中右键不误删;右键线轴/目标不删;重做快捷键 ----
	var c := _center(mn)
	_press(c, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	_press(c, MOUSE_BUTTON_RIGHT, true, MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)
	_press(c, MOUSE_BUTTON_RIGHT, false, MOUSE_BUTTON_MASK_LEFT)
	_press(c, MOUSE_BUTTON_LEFT, false, 0)
	await _settle()
	_check(s.describe_node(mid) != null, "左键按住拖动时按右键不删节点")
	_click(_center(board.get_node("n%d" % s.assumption_ids[0])), MOUSE_BUTTON_RIGHT)
	_click(_center(board.get_node("n%d" % s.goal_id)), MOUSE_BUTTON_RIGHT)
	await _settle()
	_check(s.get_node_ids().size() == 3, "右键线轴/目标不删")
	_action("ui_undo")   # 上一步有效操作是 F 段末尾删掉的并织机
	await _settle()
	_check(s.get_node_ids().size() == 4, "Ctrl+Z 撤回上一步(并织机回来)")
	_action("ui_redo")
	await _settle()
	_check(s.get_node_ids().size() == 3, "Ctrl+Shift+Z 重做(并织机再次删除)")

	# ---- H2. 点选仪器 → 弹出这台机的介绍卡;点空白处收起 ----
	mn = board.get_node("n%d" % mid) as MachineNode
	_click(_center(mn), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(scene._guide_panel.visible, "点选仪器弹出介绍卡")
	_check(scene._guide_panel._title.text.contains("岔纹"), "介绍卡显示这台机(岔纹机)的名字")
	_check(scene._guide_panel._body.text.length() > 0, "介绍卡有详解正文")
	# 点棋盘空白处取消选中 → 收起
	_click(board.get_global_rect().get_center() + Vector2(0, 240), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(not scene._guide_panel.visible, "点空白取消选中,介绍卡收起")
	# 右键点线轴不该弹介绍卡(线轴不是仪器)
	_click(_center(board.get_node("n%d" % s.assumption_ids[0])), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(not scene._guide_panel.visible, "点线轴不弹仪器介绍卡")

	# ---- I. 点击选中 → 按删除键删除(真实输入;Backspace 覆盖 Mac 的 delete 键) ----
	mn = board.get_node("n%d" % mid) as MachineNode
	_click(_center(mn), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(mn.selected and board.has_focus(), "左键点节点选中它、板获得焦点")
	_key(KEY_BACKSPACE)   # Mac 笔记本的"delete"就是 Backspace
	await _settle()
	_check(s.describe_node(mid) == null, "选中后按 Backspace 删除仪器")
	_action("ui_undo")
	await _settle()
	# 正向 Delete 键也要能删
	mn = board.get_node("n%d" % mid) as MachineNode
	_check(mn != null, "撤回后节点回来")
	_click(_center(mn), MOUSE_BUTTON_LEFT)
	await _settle()
	_key(KEY_DELETE)
	await _settle()
	_check(s.describe_node(mid) == null, "选中后按正向 Delete 也删除")
	_action("ui_undo")
	await _settle()
	_check(s.describe_node(mid) != null, "撤回删除")

	# ---- J. 重置按钮真实点击 ----
	_click(_center(_button_named(scene, "重置")), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(s.get_node_ids().size() == 2 and s.get_wires().is_empty(), "重置回到只有线轴和目标")

	# ---- L. 关卡右缘「笔记」标签 → 翻书式笔记:打开 / 翻页 / 继续工作关闭 ----
	var nb_tab: Button = null
	for b in scene.find_children("*", "Button", true, false):
		if (b as Button).text.contains("笔"):
			nb_tab = b
	_check(nb_tab != null, "关卡界面右缘有「笔记」标签")
	if nb_tab != null:
		_click(_center(nb_tab), MOUSE_BUTTON_LEFT)
		await _settle()
		var nbui := scene._notebook_ui
		_check(nbui.visible, "点「笔记」标签打开笔记")
		# 强制塞两条已解锁条目以验证翻页(存档此刻可能没解锁)
		nbui.open(game.notebook, ["notebook_and", "notebook_imp_intro"])
		await _settle()
		_check(nbui._page == 0 and nbui._entries.size() == 2, "笔记从第 1 页开始,两条")
		var flip: Button = null
		var backtab: Button = null
		for b in nbui.find_children("*", "Button", true, false):
			if (b as Button).text.contains("翻"):
				flip = b
			elif (b as Button).text.contains("继"):
				backtab = b
		_check(flip != null and backtab != null, "笔记有「翻页」和「继续工作」标签")
		_click(_center(flip), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(nbui._page == 1, "点「翻页」到第 2 页")
		_click(_center(flip), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(nbui._page == 0, "再翻回绕到第 1 页")
		_click(_center(backtab), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(not nbui.visible, "点「继续工作」关闭笔记")

	# ---- K. 选关页真实点击进关 ----
	game.goto_select()
	await _settle()
	var select := current_scene as LevelSelect
	_check(select != null, "选关页加载")
	if select != null:
		var first: Button = null
		for b in select.find_children("*", "Button", true, false):
			if (b as Button).text.contains("第一缕丝"):
				first = b
		_check(first != null, "选关页有第一关按钮")
		if first != null:
			_click(_center(first), MOUSE_BUTTON_LEFT)
			await _settle()
			_check(current_scene is StoryScene, "点第一关 → 开场对话场景")
			if current_scene is StoryScene:
				(current_scene as StoryScene).finish()
				await _settle()
				_check(current_scene is LevelScene and game.current.id == &"l01", "播完进 l01 棋盘")

	# ---- N. 测试用「示答」按钮:点了自动摆出本关答案并通关 ----
	var l01 := current_scene as LevelScene
	if l01 != null:
		var answer_btn := _button_named(l01, "示答")
		_check(answer_btn != null, "有脚本化解法的关(调试版)显示示答按钮")
		if answer_btn != null:
			_click(_center(answer_btn), MOUSE_BUTTON_LEFT)
			await _settle()
			_check(l01.session.is_solved(), "点「示答」自动摆出答案并通关")

	_finish()


func _finish() -> void:
	print("UI_SMOKE_FAILS=", _fails)
	quit(_fails)
