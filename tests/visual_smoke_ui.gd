extends SceneTree
## UI 交互穷举(全部走 Window.push_input 真实输入管线,不直接调回调):
##   故事界面(底图/场景/立绘/遮罩 + 每个点击落点 + 任意键)/ 无对话关直接进棋盘 / 工具条按钮 /
##   仪器架 7 格与置灰 / 节点无公式文字 / 右键删除的每个落点 / 拖动中右键不误删 / Delete 键 / 撤销重做快捷键 /
##   钉按钮 → 编辑器 → 钉住 / 幽灵态 / 连线徽章 / 笔记抽屉划出收回翻页 / 标题页四选项 / 选关页锁与进关 / 示答。
##   godot --path . --script res://tests/visual_smoke_ui.gd
## 退出码 = 失败数。坐标一律是 3840×2160 逻辑视口坐标(push_input 的 in_local_coords = true)。

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
		root.push_input(ev, true)


func _press(at: Vector2, button: MouseButton, pressed: bool, mask: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.button_mask = mask
	ev.position = at
	ev.global_position = at
	root.push_input(ev, true)


func _action(name: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = name
		ev.pressed = pressed
		root.push_input(ev, true)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		root.push_input(ev, true)


func _button_named(from: Node, text: String) -> Button:
	for b in from.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _labels_with(from: Node, needle: String) -> int:
	var n := 0
	for l in from.find_children("*", "Label", true, false):
		if (l as Label).text.contains(needle):
			n += 1
	return n


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _make_level(id: String, dlg: DialogueRes) -> LevelDef:
	var lv := LevelDef.new()
	lv.id = StringName(id)
	lv.title = "第九纹"
	lv.assumptions = ["A & B"]
	lv.goal = "B & A"
	lv.allowed_rules = [&"and_intro", &"and_elim", &"or_intro", &"imp_intro"]
	lv.atoms = [&"A", &"B"]
	lv.intro_dialogue = dlg
	return lv


func _line(speaker: String, text: String, scene: String, left: String, nora_expr: String) -> DialogueLine:
	var l := DialogueLine.new()
	l.speaker = speaker
	l.text = text
	l.scene = scene
	l.left_char = left
	l.nora_expr = nora_expr
	return l


func _run() -> void:
	await _settle()
	var game := root.get_node("/root/Game")

	# ---- A. 故事界面:底图 + 场景插图 + 左右立绘 + 遮罩;点击落点与任意键推进;不显示场景名 ----
	var dlg := DialogueRes.new()
	dlg.lines.append(_line("莉娅", "第 0 句台词", "街景", "莉娅", "默认"))
	dlg.lines.append(_line("诺拉·拉弗蒂", "第 1 句台词", "", "莉娅", "惊讶"))
	dlg.lines.append(_line("莉娅", "第 2 句台词", "工坊", "莉娅", "默认"))
	game.start_level(_make_level("ui_dlg", dlg))
	await _settle()
	var story := current_scene as StoryScene
	_check(story != null, "有对话的关先进 StoryScene")
	if story != null:
		_check(_labels_with(story, "街景") == 0 and _labels_with(story, "第九纹") == 0, "故事界面不显示场景名/关名")
		_check(story._scene_pic.visible and story._scene_pic.texture != null
				and story._scene_pic.texture.resource_path.ends_with("scene_street.png"), "第 0 句换到街景插图")
		_check(story._slots[0].visible and story._portraits[0].texture.resource_path.contains("char_lia_default"), "左侧立绘 = 莉娅默认")
		_check(story._slots[1].visible and story._portraits[1].texture.resource_path.contains("char_nora_default"), "右侧恒为诺拉")
		_check(story._masks[1].visible and not story._masks[0].visible, "莉娅说话:诺拉叠遮罩,莉娅不叠")
		_check(is_equal_approx(story._masks[1].modulate.a, 0.5) and story._masks[1].size == story._portraits[1].size
				and story._masks[1].position == story._portraits[1].position, "遮罩 50% 透明且与立绘完全重合")
		var box: DialogueBox = story._dialogue
		var spots := [
			["说话人名字", _center(box._speaker)],
			["台词正文", _center(box._text)],
			["屏幕左上角", Vector2(30, 30)],
			["左侧立绘", _center(story._slots[0])],
			["场景插图", _center(story._scene_pic)],
			["右侧立绘", _center(story._slots[1])],
		]
		var expected_idx := 0
		for n in 3:
			_check(box._idx == expected_idx, "第 %d 句正在显示(idx=%d)" % [n, box._idx])
			if n == 1:
				_check(box._speaker.text == "诺拉·拉弗蒂", "名字显示全名")
				_check(story._portraits[1].texture.resource_path.contains("char_nora_surprised"), "诺拉表情切到惊讶")
				_check(story._masks[0].visible and not story._masks[1].visible, "诺拉说话:莉娅叠遮罩")
				_check(story._scene_pic.texture.resource_path.ends_with("scene_street.png"), "场景留空则沿用上一句")
			if n == 2:
				_check(story._scene_pic.texture.resource_path.ends_with("scene_workshop.png"), "第 2 句换到工坊")
				_key(KEY_SPACE)
				_check(box._text.visible_characters == box._text.get_total_character_count(), "打字中按任意键整句显示")
				_key(KEY_ENTER)
			else:
				var s1: Array = spots[(2 * n) % spots.size()]
				var s2: Array = spots[(2 * n + 1) % spots.size()]
				_click(s1[1], MOUSE_BUTTON_LEFT)
				_check(box._text.visible_characters == box._text.get_total_character_count(),
						"点在「%s」:打字中点击整句显示" % s1[0])
				_click(s2[1], MOUSE_BUTTON_LEFT)
				_check(box._idx == expected_idx + 1, "点在「%s」:推进到下一句" % s2[0])
			expected_idx += 1
		_check(not box.visible, "最后一句后再按即关闭")
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

	# ---- C. 工具条:没有撤销/重做按钮,有重置;不显示关名/目标文字 ----
	_check(_button_named(scene, "撤销") == null and _button_named(scene, "重做") == null, "无撤销/重做按钮")
	_check(_button_named(scene, "重置") != null, "有重置按钮")
	_check(_button_named(scene, "示答") == null, "没有脚本化解法的关不显示示答按钮")
	_check(_labels_with(scene, "第九纹") == 0 and _labels_with(scene, "目标纹样") == 0, "关内不显示当前关名/目标文字")

	# ---- D. 仪器架:固定 7 格按图顺序;本关未上架的置灰禁用;点可用的放置 ----
	var board: ProofBoard = scene._board
	var s := scene.session
	var last_y := -1.0
	var order_ok := true
	for rid in PalettePanel.SLOT_ORDER:
		var b := scene._palette.button_of(rid)
		order_ok = order_ok and b != null and b.position.y > last_y
		if b != null:
			last_y = b.position.y
	_check(order_ok, "仪器架 7 个按钮按图顺序从上到下")
	_check(scene._palette.button_of(&"imp_elim").disabled and scene._palette.button_of(&"or_elim").disabled
			and scene._palette.button_of(&"false_elim").disabled and not scene._palette.button_of(&"or_intro").disabled,
			"本关未上架的仪器置灰禁用")
	_click(_center(scene._palette.button_of(&"false_elim")), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(s.get_node_ids().size() == 2, "点置灰的仪器不放置")
	_click(_center(_button_named(scene._palette, "岔纹机")), MOUSE_BUTTON_LEFT)
	await _settle()
	var ids := s.get_node_ids()
	_check(ids.size() == 3, "点仪器架按钮放置一台岔纹机(得 %d 节点)" % ids.size())
	var mid: int = ids[-1]
	s.set_node_position(mid, Vector2(720, 720))   # 挪开:palette 默认落在视野中心,会和后面放的机器重叠
	board.apply_positions()
	await _settle()
	var mn := board.get_node("n%d" % mid) as MachineNode

	# ---- E. 节点无公式文字;幽灵态:未连未钉全幽灵;钉上口后上口实显 + 「已钉」;接线后入口实显 ----
	var leak := false
	for l in mn.find_children("*", "Label", true, false):
		for sym in ["?", "&", "|", ">", "A", "B"]:
			leak = leak or (l as Label).text.contains(sym)
	_check(not leak, "节点内没有任何公式/字母文字")
	_check(mn._in_views[0].ghost and mn._out_views[0].ghost and mn._out_views[1].ghost, "新放置的仪器所有口都是幽灵")
	_click(_center(_button_named(mn, "钉上口")), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(scene._editor.visible, "点「钉上口」打开纹样编辑器")
	var swatch_ok := true
	for b in scene._editor._brush_row.get_children():
		swatch_ok = swatch_ok and not (b as Button).text.contains("A") and not (b as Button).text.contains("B")
	_check(swatch_ok, "编辑器原子笔刷是色块,不写字母")
	scene._editor.tree = FormulaParser.parse("B")
	scene._editor._confirm.pressed.emit()
	await _settle()
	mn = board.get_node("n%d" % mid) as MachineNode
	_check(s.describe_node(mid).pinned.get(0, "") == "B", "钉住后模型记录 B")
	_check(not mn._out_views[0].ghost and mn._out_views[1].ghost, "钉住的上口实显,下口仍幽灵")
	_check(mn.is_pinned_mark_shown(0) and not mn.is_pinned_mark_shown(1), "钉住的口下出「已钉」")
	board._on_connection_request("n%d" % s.assumption_ids[0], 0, "n%d" % mid, 0)
	await _settle()
	mn = board.get_node("n%d" % mid) as MachineNode
	_check(not mn._in_views[0].ghost, "接上线的入口实显")
	_check(s.get_output_pattern(mid, 0).equals(FormulaParser.parse("(A & B) | B")), "上口织出 (A∧B)∨B")

	# ---- F. 连线徽章:欠定线「欠定」→ 钉住后 OK 无浮层;结构不合「冲突」;断线后无浮层 ----
	_click(_center(_button_named(scene._palette, "并织机")), MOUSE_BUTTON_LEFT)
	await _settle()
	var join: int = s.get_node_ids()[-1]
	s.set_node_position(join, Vector2(1300, 720))   # 挪开,别压在岔纹机上
	board.apply_positions()
	await _settle()
	board._on_connection_request("n%d" % mid, 1, "n%d" % join, 0)   # 下口 ?R∨(A∧B) → 并织机入口:没染完
	await _settle()
	_check(board._overlay._chips.size() == 1 and (board._overlay._chips[0].ctrl as Control).get_child(0).text == "欠定",
			"欠定线挂「欠定」徽章(纯文字)")
	_click(_center(_button_named(board.get_node("n%d" % mid), "钉下口")), MOUSE_BUTTON_LEFT)
	scene._editor.tree = FormulaParser.parse("A")
	scene._editor._confirm.pressed.emit()
	await _settle()
	_check(board._overlay._chips.is_empty(), "钉下口后这条线 OK,浮层消失")
	board._on_connection_request("n%d" % mid, 1, "n%d" % s.goal_id, 0)   # A∨(A∧B) → 目标 B∧A:∨ 对 ∧
	await _settle()
	_check(board._overlay._chips.size() == 1 and (board._overlay._chips[0].ctrl as Control).get_child(0).text == "冲突",
			"连接词对不上的线挂「冲突」徽章")
	board._on_disconnection_request("n%d" % mid, 1, "n%d" % s.goal_id, 0)
	await _settle()
	_check(board._overlay._chips.is_empty(), "断线后没有浮层")
	s.remove_machine(join)
	await _settle()

	# ---- G. 右键删除的每个落点(删 → Ctrl+Z 撤回 → 下一个落点) ----
	var spots_fn: Array[Callable] = [
		func(m: MachineNode) -> Vector2: return _center(m.get_titlebar_hbox().get_child(0)),
		func(m: MachineNode) -> Vector2: return _center(m._in_views[0]),
		func(m: MachineNode) -> Vector2: return _center(m._in_views[0].get_parent().get_parent().get_child(1)),
		func(m: MachineNode) -> Vector2: return _center(m._out_views[1]),
		func(m: MachineNode) -> Vector2: return _center(m._pin_marks[0]),
		func(m: MachineNode) -> Vector2: return _center(m),
	]
	var spot_names := ["标题文字", "输入口纹样", "行中间 spacer", "输出口纹样", "「已钉」小字", "节点几何中心"]
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
	_check(mn.is_pinned_mark_shown(0), "撤回后「已钉」仍在")

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

	# ---- L. 右缘笔记抽屉:点「笔记」向左划出 → 变「继续工作」;翻页循环;点「继续工作」收回 ----
	var nbui: NotebookUI = scene._notebook_ui
	var vw: float = root.get_visible_rect().size.x
	_check(nbui._handle.text.contains("笔") and not nbui.is_open()
			and is_equal_approx(nbui._drawer.position.x, vw - NotebookUI.CLOSED_PEEK), "抽屉收起在右缘,夹子写「笔记」")
	_click(_center(nbui._handle), MOUSE_BUTTON_LEFT)
	await nbui.slide_finished
	await _settle()
	_check(nbui.is_open() and is_equal_approx(nbui._drawer.position.x, NotebookUI.OPEN_X), "点「笔记」抽屉划出到位")
	_check(nbui._handle.text.contains("继"), "划出后夹子变「继续工作」")
	_check(nbui._entries.size() == 7 and nbui._page == 0 and nbui._title.text == "并织机", "七台仪器说明,从并织机开始")
	_click(_center(nbui._flip), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(nbui._page == 1 and nbui._title.text == "拆股机", "点「翻页」到第 2 条(拆股机)")
	for i in 6:
		_click(_center(nbui._flip), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(nbui._page == 0, "翻到最后一条再翻回到第一条")
	_click(_center(nbui._handle), MOUSE_BUTTON_LEFT)
	await nbui.slide_finished
	await _settle()
	_check(not nbui.is_open() and nbui._handle.text.contains("笔")
			and is_equal_approx(nbui._drawer.position.x, vw - NotebookUI.CLOSED_PEEK), "点「继续工作」抽屉收回")

	# ---- T. 标题页:恰好四个选项;开始游戏→选关;有进度则「继续游戏」;重置进度即清档;开发者信息 Esc 返回 ----
	game.save.wipe()
	game.goto_menu()
	await _settle()
	var menu := current_scene as MainMenu
	_check(menu != null, "标题页加载")
	if menu != null:
		var names: Array[String] = []
		for b in menu.find_children("*", "Button", true, false):
			if b.get_parent() == menu:
				names.append((b as Button).text)
		_check(names == ["开始游戏", "重置进度", "开发者信息", "退出游戏"], "标题页恰好四个选项(得 %s)" % str(names))
		_click(_center(_button_named(menu, "开始游戏")), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(current_scene is LevelSelect, "开始游戏 → 选关页(不直接进关)")
		game.save.mark_solved(&"l01")
		game.save.save()
		game.goto_menu()
		await _settle()
		menu = current_scene as MainMenu
		_check(_button_named(menu, "继续游戏") != null, "有进度时第一项是「继续游戏」")
		_click(_center(_button_named(menu, "重置进度")), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(game.save.solved.is_empty() and _button_named(menu, "开始游戏") != null, "点「重置进度」即清档,第一项变回「开始游戏」")
		_click(_center(_button_named(menu, "开发者信息")), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(current_scene is CreditsScene, "开发者信息页加载")
		_check(current_scene.find_children("*", "Button", true, false).is_empty(), "开发者信息页只有文字没有按钮")
		_action("ui_cancel")
		await _settle()
		_check(current_scene is MainMenu, "开发者信息页按 Esc 回标题")
		game.goto_credits()
		await _settle()
		_click(Vector2(1920, 1080), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(current_scene is MainMenu, "开发者信息页点击任意处回标题")

	# ---- K. 选关页:全部关卡可见,只有第一关可点;「第一纹」真实点击进关;Esc 回标题 ----
	game.goto_select()
	await _settle()
	var select := current_scene as LevelSelect
	_check(select != null, "选关页加载")
	if select != null:
		var buttons := select.find_children("*", "Button", true, false)
		var enabled := 0
		for b in buttons:
			if not (b as Button).disabled:
				enabled += 1
		_check(buttons.size() == game.catalog.all_levels().size(), "全部 %d 关都显示" % game.catalog.all_levels().size())
		_check(enabled == 1, "清档后只有第一关可点(得 %d)" % enabled)
		_check(_labels_with(select, "第一章 并纹") == 1 and _labels_with(select, "第二章 叠层纹") == 1, "章名按美术图")
		var first: Button = null
		for b in buttons:
			if (b as Button).text == "第一纹" and not (b as Button).disabled:
				first = b
		_check(first != null, "第一章「第一纹」可点")
		_action("ui_cancel")
		await _settle()
		_check(current_scene is MainMenu, "选关页按 Esc 回标题")
		game.goto_select()
		await _settle()
		select = current_scene as LevelSelect
		first = null
		for b in select.find_children("*", "Button", true, false):
			if (b as Button).text == "第一纹" and not (b as Button).disabled:
				first = b
		if first != null:
			_click(_center(first), MOUSE_BUTTON_LEFT)
			await _settle()
			_check(current_scene is StoryScene, "点第一纹 → 故事界面")
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
