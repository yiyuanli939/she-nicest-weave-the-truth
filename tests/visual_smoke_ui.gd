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


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


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
	AudioServer.set_bus_mute(0, true)   # 跑测试别真出声;playing 状态不受影响
	var bgm := root.get_node("/root/Bgm")

	# ---- A. 故事界面:底图 + 场景插图 + 左右立绘 + 遮罩;点击落点与任意键推进;不显示场景名 ----
	var dlg := DialogueRes.new()
	# 台词要够长:打字机 40 字/秒,太短的话两帧一过就已显示完,"打字中点击"就测不到
	var filler := "这是一句足够长的测试台词,用来保证打字机还在逐字显示的时候我们就点了下去。"
	dlg.lines.append(_line("莉娅", "第 0 句台词。" + filler, "街景", "莉娅", "默认"))
	dlg.lines.append(_line("诺拉·拉弗蒂", "第 1 句台词。" + filler, "", "莉娅", "惊讶"))
	dlg.lines.append(_line("莉娅", "第 2 句台词。" + filler, "工坊", "莉娅", "默认"))
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
		# Esc 不当推进键(留给将来的退出/暂停;修饰键/功能键同理)
		_key(KEY_ESCAPE)
		_check(box._idx == 0 and box._text.visible_characters < box._text.get_total_character_count(),
				"Esc 不推进也不全显(想退出的玩家不该被推进关)")
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
	# 状态文字在按钮之后:文字变长不再把按钮推着跑(通关瞬间「下一关」曾从鼠标下溜走)
	var back_tool := _button_named(scene, "选关")
	var back_x0: float = back_tool.get_global_rect().position.x
	scene._status.text = "一段相当长的状态文字用来验证工具条按钮不再被文字推着跑一二三四五六七八"
	await _settle()
	_check(back_tool.get_global_rect().position.x == back_x0, "状态文字变化不推挤工具条按钮")
	scene._status.text = ""
	await _settle()

	# ---- D. 仪器架:只显示本关上架的仪器,按图顺序紧凑排列;未上架的不显示 ----
	var board: ProofBoard = scene._board
	var s := scene.session
	var last_y := -1.0
	var order_ok := true
	var shown := 0
	for rid in PalettePanel.SLOT_ORDER:
		var b := scene._palette.button_of(rid)
		if b == null or not b.visible:
			continue
		shown += 1
		order_ok = order_ok and b.position.y > last_y
		last_y = b.position.y
	_check(shown == scene.allowed_rules.size() and order_ok,
			"仪器架只显示本关 %d 台且从上到下紧凑排列(得 %d)" % [scene.allowed_rules.size(), shown])
	_check(not scene._palette.button_of(&"imp_elim").visible and not scene._palette.button_of(&"or_elim").visible
			and not scene._palette.button_of(&"false_elim").visible and scene._palette.button_of(&"or_intro").visible,
			"本关未上架的仪器不显示")
	var bars := board.scroll_bars()
	var bars_hidden := bars.size() == 2
	for bar in bars:
		bars_hidden = bars_hidden and bar.modulate.a == 0.0 and bar.mouse_filter == Control.MOUSE_FILTER_IGNORE
	_check(bars_hidden, "棋盘两条滚动条隐形且不吃鼠标(视区只靠中键拖动)")
	_click(_center(scene._palette.button_of(&"false_elim")), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(s.get_node_ids().size() == 2, "点未上架仪器的空位不放置")
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
	_check(nbui._entries.size() == scene.allowed_rules.size() and nbui._page == 0 and nbui._title.text == "并织机",
			"只显示本关 %d 台仪器的说明,从并织机开始(得 %d)" % [scene.allowed_rules.size(), nbui._entries.size()])
	_click(_center(nbui._flip), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(nbui._page == 1 and nbui._title.text == "拆股机", "点「翻页」到第 2 条(拆股机)")
	for i in nbui._entries.size() - 1:
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
	_check(bgm.slot == &"title" and bgm.is_playing(), "标题页 BGM = 标题曲在播")
	var bgm_p0: AudioStreamPlayer = bgm.active_player()
	if menu != null:
		var names: Array[String] = []
		for b in menu.find_children("*", "Button", true, false):
			if b.get_parent() == menu:
				names.append((b as Button).text)
		_check(names == ["开始游戏", "重置进度", "开发者信息", "退出游戏"], "标题页恰好四个选项(得 %s)" % str(names))
		_click(_center(_button_named(menu, "开始游戏")), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(current_scene is LevelSelect, "开始游戏 → 选关页(不直接进关)")
		_check(bgm.active_player() == bgm_p0 and bgm_p0.playing and bgm_p0.get_playback_position() > 0.0, "标题到选关 BGM 不重启(同一播放器接着播)")
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
		_check(bgm.active_player() == bgm_p0 and bgm_p0.playing, "开发者信息页 BGM 不重启")
		var credit_btns := current_scene.find_children("*", "Button", true, false)
		var visible_btns: Array[String] = []
		for b in credit_btns:
			if (b as Button).is_visible_in_tree():
				visible_btns.append((b as Button).text)
		_check(visible_btns == ["小机维护", "返回主界面"],
				"开发者信息页只有文字 + 「小机维护」「返回主界面」按钮(得 %s)" % str(visible_btns))
		_click(_center(_button_named(current_scene, "小机维护")), MOUSE_BUTTON_LEFT)
		await _settle()
		var maint: RobotMaintUI = (current_scene as CreditsScene)._maint
		_check(current_scene is CreditsScene and maint.visible, "点「小机维护」打开面板(不退回标题)")
		_check(maint._line_edits.size() == 5 and (maint._line_edits["greet"] as LineEdit).text.contains("诺拉"), "面板读到五句台词(greet 称呼诺拉;故障没有台词)")
		_check(_button_named(maint, "保存并生成语音") != null and _button_named(maint, "刷入固件与语音") != null
				and _button_named(maint, "接入小机(拉起桥接与语音助手)") != null, "面板有 接入 / 刷入 / 生成语音 按钮")
		_check(maint._dir_btn.text.contains("右") and maint._voice_opt.item_count == RobotMaintUI.VOICES.size(), "回头方向与音色控件就绪")
		_click(_center(_button_named(maint, "关闭")), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(not maint.visible and current_scene is CreditsScene, "关闭面板仍在开发者信息页")
		_action("ui_cancel")
		await _settle()
		_check(current_scene is MainMenu, "开发者信息页按 Esc 回标题")
		game.goto_credits()
		await _settle()
		_click(Vector2(1920, 1080), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(current_scene is MainMenu, "开发者信息页点击任意处回标题")
		game.goto_credits()
		await _settle()
		_click(_center(_button_named(current_scene, "返回主界面")), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(current_scene is MainMenu, "开发者信息页点「返回主界面」回标题")

	# ---- K. 选关页:全部关卡可见,只有第一关可点;「第一纹」真实点击进关;Esc 回标题 ----
	game.goto_select()
	await _settle()
	var select := current_scene as LevelSelect
	_check(select != null, "选关页加载")
	if select != null:
		var level_btns: Array[Button] = []
		var enabled := 0
		for b in select.find_children("*", "Button", true, false):
			if (b as Button).text == "返回主界面":
				continue
			level_btns.append(b)
			if not (b as Button).disabled:
				enabled += 1
		_check(level_btns.size() == game.catalog.all_levels().size(), "全部 %d 关都显示" % game.catalog.all_levels().size())
		_check(enabled == 1, "清档后只有第一关可点(得 %d)" % enabled)
		_check(_button_named(select, "返回主界面") != null, "选关页左上角有「返回主界面」")
		_check(_labels_with(select, "第一章 并纹") == 1 and _labels_with(select, "第二章 叠层纹") == 1, "章名按美术图")
		var first: Button = null
		for b in level_btns:
			if (b as Button).text == "第一纹" and not (b as Button).disabled:
				first = b
		_check(first != null, "第一章「第一纹」可点")
		_action("ui_cancel")
		await _settle()
		_check(current_scene is MainMenu, "选关页按 Esc 回标题")
		game.goto_select()
		await _settle()
		_click(_center(_button_named(current_scene, "返回主界面")), MOUSE_BUTTON_LEFT)
		await _settle()
		_check(current_scene is MainMenu, "选关页点「返回主界面」回标题")
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
			_check(bgm.slot == &"level_1", "进第一章故事界面 BGM 槽位 = level_1(故事与关内共用)")
			if current_scene is StoryScene:
				(current_scene as StoryScene).finish()
				await _settle()
				_check(current_scene is LevelScene and game.current.id == &"l01", "播完进 l01 棋盘")
				_check(bgm.slot == &"level_1", "故事到关内同槽位不变")
				if bgm.TRACKS[&"level_1"] == "":
					await _wait(bgm.FADE_SEC + 0.2)
					_check(not bgm.is_playing(), "第一章暂无曲:标题曲淡出到静音")

	# ---- N. 测试用「示答」按钮:点了自动摆出本关答案并通关 ----
	var l01 := current_scene as LevelScene
	if l01 != null:
		var answer_btn := _button_named(l01, "示答")
		_check(answer_btn != null, "有脚本化解法的关(调试版)显示示答按钮")
		if answer_btn != null:
			_click(_center(answer_btn), MOUSE_BUTTON_LEFT)
			await _settle()
			_check(l01.session.is_solved(), "点「示答」自动摆出答案并通关")

	# ---- R. 小机「请指导我」:坏掉前回头到极限后代解(无庆祝)/ 方向设置 / 3-1 通关瞬间坏掉 / 坏掉后只故障 ----
	var robot := root.get_node("/root/Robot")
	game.save.wipe()
	game.start_level(game.catalog.find(&"l01"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	var g1 := current_scene as LevelScene
	_check(g1 != null and g1._guide_hint.visible and g1._guide_hint.text.contains("请指导我") and g1._guide_hint.text.contains("请帮帮我"),
			"坏掉前关内提示可以说「请指导我」或「请帮帮我」")
	robot.set_turn_dir("right")
	robot.sent_log.clear()
	robot._on_event({"evt": "speech", "text": "请 指导 我"})
	await _wait(1.4)
	_check(g1.session.is_solved() and game.save.is_solved(&"l01"), "说「请指导我」→ 小机代解通关并记档")
	_check(robot.sent("gimbal", "", 175), "代解前底部云台回头到右极限(175)")
	_check(not robot.sent("say", "win") and not robot.sent("anim", "celebrate") and not robot.sent("say", "encourage"), "代解不庆祝不鼓励")
	await _wait(3.4)
	_check(robot.sent("gimbal", "", 90), "代解后转回正中")
	robot._on_event({"evt": "speech", "text": "请 帮帮 我"})
	await _wait(0.3)
	_check(g1._guiding == false, "已通关再说不再触发")
	robot.set_turn_dir("left")
	_check(game.save.settings.get("robot_turn") == "left", "回头方向设置写进存档 settings")
	robot._last_guide_ms = -100000   # 模拟 3 s 语音节流已过
	game.start_level(game.catalog.find(&"l02"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	var g2 := current_scene as LevelScene
	_check(bgm.slot == &"level_1", "同章 l02 BGM 槽位不变")
	robot.sent_log.clear()
	robot._on_event({"evt": "speech", "text": "请 帮帮 我"})
	await _wait(1.4)
	_check(g2.session.is_solved() and robot.sent("gimbal", "", 5) and not robot.sent("gimbal", "", 175), "「请帮帮我」+ 方向设左 → 回头到左极限(5)后代解")
	robot.set_turn_dir("right")
	# 3-1(l10):小机还没坏 —— 进关不故障、提示照显、说「请指导我」仍回头代解;通关瞬间坏掉(panic 演出)
	game.start_level(game.catalog.find(&"l10"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	_check(bgm.slot == &"level_3", "进第三章 BGM 槽位 = level_3")
	var g3 := current_scene as LevelScene
	_check(not robot.broken, "3-1 进关小机还没坏")
	_check(g3._guide_hint.visible, "3-1 仍显示求助提示")
	# 离开 l02 时演出还在 hold,LevelScene._exit_tree 兜底启动了缓步回正(gimbal 逐帧回 90,
	# 由 Robot autoload 跨场景继续走)——等它走完再清日志,别污染下面的断言
	await _wait(1.6)
	robot.sent_log.clear()
	robot._last_guide_ms = -100000
	robot._on_event({"evt": "speech", "text": "请 指导 我"})
	await _wait(1.4)
	_check(g3.session.is_solved() and robot.sent("gimbal", "", 175), "3-1 说「请指导我」仍回头代解")
	_check(robot.broken and robot.sent("anim", "panic") and not robot.sent("say", "panic")
			and (robot.sent("say", "glitch1") or robot.sent("say", "glitch2") or robot.sent("say", "glitch3")),
			"3-1 通关瞬间小机坏掉:乱动 + 坏掉音效,没有台词")
	# 3-2(l11):坏掉后任何 cue(含「请指导我」)都是故障演出,不回头、不代解
	game.start_level(game.catalog.find(&"l11"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	var g3b := current_scene as LevelScene
	_check(robot.broken, "3-2 起小机坏掉")
	_check(not g3b._guide_hint.visible, "坏掉后不显示求助提示")
	await _wait(3.4)                # 等 l10 代解演出的 hold/回正走完(Robot autoload 跨场景继续)
	robot.sent_log.clear()
	robot._last_at.clear()          # 模拟故障演出 6 s 节流已过
	robot._last_guide_ms = -100000
	robot._on_event({"evt": "speech", "text": "请 指导 我"})
	await _wait(1.2)
	_check(not g3b.session.is_solved() and robot.sent("emote", "glitch") and not robot.sent("gimbal"), "坏掉后说「请指导我」只故障、不回头、不代解")
	# 第四章(l13):仍是坏的(修好在结局「感谢游玩」黑屏,不在进关)
	game.start_level(game.catalog.find(&"l13"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	var g4 := current_scene as LevelScene
	_check(robot.broken and not robot.sent("say", "calm"), "第四章小机仍坏(修好在结局)")
	_check(not g4._guide_hint.visible, "第四章不显示求助提示")
	robot.sent_log.clear()
	robot._last_at.clear()
	robot._last_guide_ms = -100000
	robot._on_event({"evt": "speech", "text": "请 指导 我"})
	await _wait(1.0)
	_check(not g4.session.is_solved() and robot.sent("emote", "glitch") and not robot.sent("gimbal"), "第四章说「请指导我」也只故障")
	game.save.wipe()

	# ---- B. 回标题:BGM 淡入标题曲 ----
	game.goto_menu()
	await _settle()
	_check(bgm.slot == &"title" and bgm.is_playing(), "回标题 BGM 淡入标题曲")

	_finish()


func _finish() -> void:
	print("UI_SMOKE_FAILS=", _fails)
	quit(_fails)
