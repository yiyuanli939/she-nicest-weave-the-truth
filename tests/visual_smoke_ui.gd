extends SceneTree
## UI 交互穷举(全部走 Window.push_input 真实输入管线,不直接调回调):
##   故事界面(底图/场景/立绘/遮罩 + 每个点击落点 + 任意键)/ 无对话关直接进棋盘 / 工具条按钮 /
##   仪器架 7 格与置灰 / 节点无公式文字 / 右键删除的每个落点 / 拖动中右键不误删 / Delete 键 / 撤销重做快捷键 /
##   钉按钮 → 编辑器 → 钉住 / 幽灵态 / 连线徽章 / 笔记抽屉划出收回翻页 / 标题页四选项 / 选关页锁与进关 / 示答。
##   无机器人模式(提示/入口消失、F9 切回)/ 低功耗模式(静止棋盘不重绘、标题流光照常、帧率上限 60)。
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


func _motion(at: Vector2, mask: int) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	ev.button_mask = mask
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


## 场景里可见的 Label/Button 文本中含 needle 的(无机器人模式:任何可见文字都不许提实体小机)
func _visible_texts_with(from: Node, needle: String) -> Array[String]:
	var out: Array[String] = []
	for c in from.find_children("*", "Control", true, false):
		var text := ""
		if c is Label:
			text = (c as Label).text
		elif c is Button:
			text = (c as Button).text
		if text.contains(needle) and (c as Control).is_visible_in_tree():
			out.append(text)
	return out


func _visible_button_texts(from: Node) -> Array[String]:
	var out: Array[String] = []
	for b in from.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree():
			out.append((b as Button).text)
	return out


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

	# ---- E. 节点无公式文字;幽灵态:未连未钉全幽灵;钉纹样(上口)后上口实显、蚂蚁线消失;接线后入口实显;弹窗改版 ----
	var leak := false
	for l in mn.find_children("*", "Label", true, false):
		for sym in ["?", "&", "|", ">", "A", "B"]:
			leak = leak or (l as Label).text.contains(sym)
	_check(not leak, "节点内没有任何公式/字母文字")
	_check(mn._in_views[0].ghost and mn._out_views[0].ghost and mn._out_views[1].ghost, "新放置的仪器所有口都是幽灵")
	_check(mn._pin_buttons.size() == 2 and (mn._pin_buttons[0] as Button).text == "钉纹样" and (mn._pin_buttons[1] as Button).text == "钉纹样"
			and mn.get_titlebar_hbox().get_child_count() == 1, "岔纹机两个可钉口各有一个「钉纹样」按钮,标题栏里没有按钮")
	_check(mn._pin_buttons[0].get_parent() == mn._out_views[0].get_parent().get_parent()
			and mn._pin_buttons[0].get_index() == mn._out_views[0].get_parent().get_index() - 1, "岔纹机钉按钮在输出纹样左侧同一行")
	_check(mn.is_ant_frame_shown(0) and mn.is_ant_frame_shown(1), "未钉的两口都画蚂蚁线")
	_check(mn.get_theme_constant("separation") == MachineNode.ROW_GAP and MachineNode.ROW_GAP >= 32, "纹样行距拉开到 ROW_GAP")
	_click(_center(mn._pin_buttons[0]), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(scene._editor.visible, "点上口的「钉纹样」打开纹样绘制弹窗")
	var swatch_ok := true
	var icon_btns := 0
	for b in scene._editor._brush_row.get_children():
		swatch_ok = swatch_ok and not (b as Button).text.contains("A") and not (b as Button).text.contains("B")
		if (b as Button).text == "" and b.get_child_count() > 0:
			icon_btns += 1
	_check(swatch_ok, "弹窗原子笔刷是色块,不写字母")
	_check(icon_btns == 3 and _button_named(scene._editor, "挖回孔") == null, "并织/迭层/岔纹是三个图标笔刷,没有挖回孔(得 %d)" % icon_btns)
	_check(_button_named(scene._editor, "清空") != null and _button_named(scene._editor, "取消") != null and _button_named(scene._editor, "确认") != null
			and _button_named(scene._editor, "钉住") == null and _button_named(scene._editor, "清除钉住") == null,
			"弹窗按钮是 清空/取消/确认")
	_check(_labels_with(scene._editor, "斜纹处") == 0 and _labels_with(scene._editor, "点选笔刷进行绘制") == 1 and _labels_with(scene._editor, "纹样绘制") == 1,
			"弹窗有标题「纹样绘制」与「点选笔刷进行绘制:」,旧提示删掉")
	scene._editor.tree = FormulaParser.parse("B")
	scene._editor._confirm.pressed.emit()
	await _settle()
	mn = board.get_node("n%d" % mid) as MachineNode
	_check(s.describe_node(mid).pinned.get(0, "") == "B", "钉住后模型记录 B")
	_check(not mn._out_views[0].ghost and mn._out_views[1].ghost, "钉住的上口实显,下口仍幽灵")
	_check(not mn.is_ant_frame_shown(0) and mn.is_ant_frame_shown(1), "钉住的口蚂蚁线消失,另一口还在")
	s.connect_wire(s.assumption_ids[0], 0, mid, 0)
	await _settle()
	mn = board.get_node("n%d" % mid) as MachineNode
	_check(not mn._in_views[0].ghost, "接上线的入口实显")
	_check(mn.is_input_wired(0) and not mn.is_output_wired(0), "端口状态:入口有线(整圆),出口无线(插头)")
	_check(s.get_output_pattern(mid, 0).equals(FormulaParser.parse("(A & B) | B")), "上口织出 (A∧B)∨B")

	# ---- F. 连线徽章(64 号白描边):欠定常驻 → 钉住后 OK 无浮层;接错(冲突)的线 0.5 s 自动断开,徽章冻结 1 s 后淡出 ----
	_click(_center(_button_named(scene._palette, "并织机")), MOUSE_BUTTON_LEFT)
	await _settle()
	var join: int = s.get_node_ids()[-1]
	s.set_node_position(join, Vector2(1300, 720))   # 挪开,别压在岔纹机上
	board.apply_positions()
	await _settle()
	s.connect_wire(mid, 1, join, 0)   # 下口 ?R∨(A∧B) → 并织机入口:没染完
	await _settle()
	_check(board._overlay._chips.size() == 1 and (board._overlay._chips[0].ctrl as Control).get_child(0).text == "欠定",
			"欠定线挂「欠定」徽章(纯文字)")
	var chip_label := (board._overlay._chips[0].ctrl as Control).get_child(0) as Label
	_check(chip_label.get_theme_font_size("font_size") == WireOverlay.BADGE_FONT_SIZE and WireOverlay.BADGE_FONT_SIZE >= 64
			and chip_label.get_theme_constant("outline_size") == WireOverlay.BADGE_OUTLINE and chip_label.get_theme_color("font_outline_color") == Color.WHITE,
			"徽章 64 号字 + 白描边")
	await _wait(WireOverlay.BADGE_HOLD_SEC + 0.6)
	_check(s.get_wires().size() == 2 and board._overlay._chips.size() == 1, "欠定不是接错:线与徽章都留着等玩家钉")
	_click(_center((board.get_node("n%d" % mid) as MachineNode)._pin_buttons[1]), MOUSE_BUTTON_LEFT)
	scene._editor.tree = FormulaParser.parse("A")
	scene._editor._confirm.pressed.emit()
	await _settle()
	_check(board._overlay._chips.is_empty(), "钉下口后这条线 OK,浮层消失")
	s.connect_wire(mid, 1, s.goal_id, 0)   # A∨(A∧B) → 目标 B∧A:∨ 对 ∧
	await _settle()
	_check(board._overlay._chips.size() == 1 and (board._overlay._chips[0].ctrl as Control).get_child(0).text == "冲突",
			"连接词对不上的线挂「冲突」徽章")
	_check(s.get_wire_state(mid, 1, s.goal_id, 0) == ProofSession.WireState.CONFLICT, "冲突线暂时还在")
	await _wait(ProofBoard.BAD_WIRE_SEC + 0.2)
	_check(s.get_wire_state(mid, 1, s.goal_id, 0) == ProofSession.WireState.OK and s.get_wires().size() == 2, "0.5 s 后接错的线自动断开")
	_check(board._overlay._chips.size() == 1 and board._overlay._chips[0].detached, "断线后徽章冻结在原位继续显示")
	await _wait(WireOverlay.BADGE_HOLD_SEC + WireOverlay.BADGE_FADE_SEC + 0.3)
	_check(board._overlay._chips.is_empty(), "徽章停 1 s 后淡出释放")
	s.remove_machine(join)
	await _settle()

	# ---- G. 右键删除的每个落点(删 → Ctrl+Z 撤回 → 下一个落点) ----
	var spots_fn: Array[Callable] = [
		func(m: MachineNode) -> Vector2: return _center(m.get_titlebar_hbox().get_child(0)),
		func(m: MachineNode) -> Vector2: return _center(m._in_views[0]),
		func(m: MachineNode) -> Vector2: return _center(m._in_views[0].get_parent().get_parent().get_child(1)),
		func(m: MachineNode) -> Vector2: return _center(m._out_views[1]),
		func(m: MachineNode) -> Vector2: return _center(m._out_views[0]),
		func(m: MachineNode) -> Vector2: return _center(m),
	]
	var spot_names := ["标题文字", "输入口纹样", "行中间 spacer", "下口纹样", "上口纹样(已钉)", "节点几何中心"]
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
	_check(not mn.is_ant_frame_shown(0), "撤回后仍是钉住态(无蚂蚁线)")

	# ---- H. 拖动中右键不误删;右键线轴/目标不删;重做快捷键(按在纹样上 —— 节点中央现在是钉按钮,左键会开弹窗) ----
	var c := _center(mn._in_views[0])
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

	# ---- I. 点击选中 → 按删除键删除(真实输入;Backspace 覆盖 Mac 的 delete 键;点在纹样上 —— 节点中央现在是钉按钮) ----
	mn = board.get_node("n%d" % mid) as MachineNode
	_click(_center(mn._in_views[0]), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(mn.selected and board.has_focus(), "左键点节点纹样选中它、板获得焦点")
	_key(KEY_BACKSPACE)   # Mac 笔记本的"delete"就是 Backspace
	await _settle()
	_check(s.describe_node(mid) == null, "选中后按 Backspace 删除仪器")
	_action("ui_undo")
	await _settle()
	mn = board.get_node("n%d" % mid) as MachineNode
	_check(mn != null, "撤回后节点回来")
	_click(_center(mn._in_views[0]), MOUSE_BUTTON_LEFT)
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

	# ---- U. v1.1 端口/连线/封程机/弹窗:插座·插头·整圆;拖线插头随鼠标;封程机臂内沿口位真实拖线;假设线搭载标记;清空+确认=取消钉住 ----
	var spool_n := board.get_node("n%d" % s.assumption_ids[0]) as MachineNode
	var goal_n := board.get_node("n%d" % s.goal_id) as MachineNode
	_check(not spool_n.is_output_wired(0) and not goal_n.is_input_wired(0), "未接线:线轴出口画插头、目标入口画插座")
	_check(spool_n._port_layer != null and spool_n._port_layer == spool_n.get_child(spool_n.get_child_count() - 1), "端口图层是节点最后一个子节点(画在纹样之上)")
	_check(spool_n._out_views[0].region_borders.is_empty() and goal_n._in_views[0].region_borders.is_empty(), "线轴/目标没有区域边框(深色外框)")
	var from_pt: Vector2 = spool_n.global_position + spool_n.port_pos(false, 0) * board.zoom
	var to_pt: Vector2 = goal_n.global_position + goal_n.port_pos(true, 0) * board.zoom
	_press(from_pt, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	var mid_pt := (from_pt + to_pt) * 0.5
	_motion(mid_pt, MOUSE_BUTTON_MASK_LEFT)
	await _settle()
	_check(board._overlay._plug_on and spool_n._drag_port == Vector2i(1, 0), "拖线中:叠加层画插头,源口藏起插头")
	_check((board._overlay.get_global_transform_with_canvas() * board._overlay._plug_pos).distance_to(mid_pt) < 2.0, "插头跟着鼠标")
	_motion(to_pt, MOUSE_BUTTON_MASK_LEFT)
	_press(to_pt, MOUSE_BUTTON_LEFT, false, 0)
	await _settle()
	_check(s.get_wires().size() == 1 and s.get_wire_state(s.assumption_ids[0], 0, s.goal_id, 0) == ProofSession.WireState.CONFLICT,
			"真实拖线接上(线轴 A∧B → 目标 B∧A:冲突,稍后自动断)")
	_check(not board._overlay._plug_on and spool_n._drag_port.x < 0, "松手后鼠标处的插头消失")
	_check(goal_n.is_input_wired(0) and spool_n.is_output_wired(0), "接上:目标入口整圆、线轴出口不再画插头")
	await _wait(ProofBoard.BAD_WIRE_SEC + 0.2)
	_check(s.get_wires().is_empty() and not goal_n.is_input_wired(0), "接错的线自动断开,入口回到插座")
	_click(_center(_button_named(scene._palette, "封程机")), MOUSE_BUTTON_LEFT)
	await _settle()
	var imp_id: int = s.get_node_ids()[-1]
	s.set_node_position(imp_id, Vector2(900, 900))
	board.apply_positions()
	await _settle()
	var imp := board.get_node("n%d" % imp_id) as MachineNode
	_check(imp.has_custom_ports() and imp.title == "" and imp._title_row != null and imp._title_row.text == "封程机"
			and imp._title_row.get_index() == imp.get_child_count() - 2, "封程机:顶部标题栏为空,标题在底部")
	_check(imp.graph_out_port(1) == 0 and imp.model_out_port(0) == 1 and imp.graph_out_port(0) == 1, "封程机假设口在第一排(图口 0 ↔ 模型口 1)")
	var hyp_local: Vector2 = imp.port_pos(false, 0)
	var q_local: Vector2 = imp.port_pos(true, 0)
	var arm_l: Rect2 = imp._local_rect_of(imp._arm_l)
	var arm_r: Rect2 = imp._local_rect_of(imp._arm_r)
	_check(is_equal_approx(hyp_local.x, arm_l.end.x) and is_equal_approx(q_local.x, arm_r.position.x) and q_local.x - hyp_local.x >= MachineNode.IMP_NOTCH_W,
			"假设口在左臂右沿、输入口在右臂左沿,中间是缺口(%.0f..%.0f)" % [hyp_local.x, q_local.x])
	_check(is_equal_approx(hyp_local.y, imp._local_rect_of(imp._out_views[1]).get_center().y)
			and is_equal_approx(q_local.y, imp._local_rect_of(imp._in_views[0]).get_center().y), "两个口的 y 都在各自纹样中心")
	_check(imp._pin_buttons.has(1) and imp._pin_buttons[1].get_parent() == imp._arm_l, "钉纹样按钮在左臂假设纹样下方")
	_check(imp._out_views[0].region_borders.size() == 2 and imp._out_views[0].region_borders[0].color == MachineNode.META_COLORS[&"P"]
			and imp._out_views[0].region_borders[1].color == MachineNode.META_COLORS[&"Q"], "封程机 P>Q 口:上半金 / 下半棕两段边框")
	_click(_center(imp._pin_buttons[1]), MOUSE_BUTTON_LEFT)
	await _settle()
	scene._editor.tree = FormulaParser.parse("A")
	scene._editor._confirm.pressed.emit()
	await _settle()
	imp = board.get_node("n%d" % imp_id) as MachineNode
	var hyp_pt: Vector2 = imp.global_position + imp.port_pos(false, 0) * board.zoom
	var q_pt: Vector2 = imp.global_position + imp.port_pos(true, 0) * board.zoom
	_press(hyp_pt, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	_motion(hyp_pt + Vector2(0, -200), MOUSE_BUTTON_MASK_LEFT)
	await _settle()
	_check(board._overlay._plug_on and board._overlay._plug_color == MachineNode.HYP_COLOR, "从假设口拖线:鼠标处的插头是假设色")
	_motion(q_pt, MOUSE_BUTTON_MASK_LEFT)
	_press(q_pt, MOUSE_BUTTON_LEFT, false, 0)
	await _settle()
	_check(s.get_wires().size() == 1 and s.get_wire_state(imp_id, 1, imp_id, 0) == ProofSession.WireState.OK, "从臂内沿的假设口真实拖线到臂内沿的 Q 口接上")
	_check(s.get_wire_carries_hyp(imp_id, 1, imp_id, 0), "这条线搭载未消去的假设(整条假设色)")
	imp = board.get_node("n%d" % imp_id) as MachineNode
	_check(imp.is_output_wired(1) and imp.is_input_wired(0), "假设口插头插进 Q 口:出口不画插头、入口整圆")
	s.disconnect_wire(imp_id, 1, imp_id, 0)
	await _settle()
	var stock_pt: Vector2 = imp.global_position + imp.stock_port_pos(false, 0) * board.zoom
	_press(stock_pt, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	_motion(q_pt, MOUSE_BUTTON_MASK_LEFT)
	_press(q_pt, MOUSE_BUTTON_LEFT, false, 0)
	await _settle()
	_check(s.get_wires().is_empty(), "节点右缘(引擎默认口位)不再是假设口的热区,拖不出线")
	_click(_center(imp._pin_buttons[1]), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(scene._editor.visible and not scene._editor.is_canvas_empty() and not scene._editor._confirm.disabled, "已钉的口打开弹窗:画布是钉住的纹样")
	scene._editor._clear_btn.pressed.emit()
	_check(scene._editor.is_canvas_empty() and scene._editor.visible and not scene._editor._confirm.disabled, "「清空」擦回空画布、窗不关、确认可按")
	scene._editor._confirm.pressed.emit()
	await _settle()
	_check(not s.describe_node(imp_id).pinned.has(1), "空画布「确认」= 取消钉住")
	_check((board.get_node("n%d" % imp_id) as MachineNode).is_ant_frame_shown(1), "取消钉住后蚂蚁线回来")
	s.remove_machine(imp_id)
	await _settle()

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
	_check(nbui._entries.size() == scene.allowed_rules.size() and nbui._page == 0 and nbui._page_pic.visible
			and nbui._page_pic.texture.resource_path.ends_with("notebook/and_intro.png"),
			"只显示本关 %d 台仪器的页,从并织机整页图开始(得 %d)" % [scene.allowed_rules.size(), nbui._entries.size()])
	_check(nbui._page_pic.position == NotebookUI.PAGE_OFFSET and nbui._page_pic.stretch_mode == TextureRect.STRETCH_KEEP
			and nbui._page_pic.texture.get_size() == Vector2(3840, 2160),
			"整页图全屏尺寸原样摆放(抽屉开位时与屏幕对齐,不缩放不改长宽比)")
	_click(_center(nbui._flip), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(nbui._page == 1 and nbui._page_pic.texture.resource_path.ends_with("notebook/and_elim.png"), "点「翻页」到第 2 页(拆股机整页图)")
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
			_check(bgm.slot == &"", "进第一章故事界面 BGM = 静音槽位(关内曲只在棋盘起)")
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
	await _wait_until(func() -> bool: return g1.session.is_solved())
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
	await _wait_until(func() -> bool: return g2.session.is_solved())
	_check(g2.session.is_solved() and robot.sent("gimbal", "", 5) and not robot.sent("gimbal", "", 175), "「请帮帮我」+ 方向设左 → 回头到左极限(5)后代解")
	robot.set_turn_dir("right")
	# 3-1(l11):小机还没坏 —— 进关不故障、提示照显、说「请指导我」仍回头代解;通关瞬间坏掉(panic 演出)
	game.start_level(game.catalog.find(&"l11"))
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
	await _wait_until(func() -> bool: return g3.session.is_solved())
	_check(g3.session.is_solved() and robot.sent("gimbal", "", 175), "3-1 说「请指导我」仍回头代解")
	_check(robot.broken and robot.sent("anim", "panic") and not robot.sent("say", "panic")
			and (robot.sent("say", "glitch1") or robot.sent("say", "glitch2") or robot.sent("say", "glitch3")),
			"3-1 通关瞬间小机坏掉:乱动 + 坏掉音效,没有台词")
	# 3-2(l12):坏掉后任何 cue(含「请指导我」)都是故障演出,不回头、不代解
	game.start_level(game.catalog.find(&"l12"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	var g3b := current_scene as LevelScene
	_check(robot.broken, "3-2 起小机坏掉")
	_check(not g3b._guide_hint.visible, "坏掉后不显示求助提示")
	await _wait(3.4)                # 等 l11 代解演出的 hold/回正走完(Robot autoload 跨场景继续)
	robot.sent_log.clear()
	robot._last_at.clear()          # 模拟故障演出 6 s 节流已过
	robot._last_guide_ms = -100000
	robot._on_event({"evt": "speech", "text": "请 指导 我"})
	await _wait(1.2)
	_check(not g3b.session.is_solved() and robot.sent("emote", "glitch") and not robot.sent("gimbal"), "坏掉后说「请指导我」只故障、不回头、不代解")
	# 第四章(l14):仍是坏的(修好在结局「感谢游玩」黑屏,不在进关)
	game.start_level(game.catalog.find(&"l14"))
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
	# 「小机不动」模式:表情/代解照常,云台/动画一条不发(维护面板「小机动作」开关的底层)
	robot.set_stationary(true)
	game.start_level(game.catalog.find(&"l01"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	var g5 := current_scene as LevelScene
	await _wait(1.0)
	robot.sent_log.clear()
	robot._last_guide_ms = -100000
	robot._on_event({"evt": "speech", "text": "请 指导 我"})
	await _wait_until(func() -> bool: return g5.session.is_solved())
	_check(g5.session.is_solved() and robot.sent("emote", "think") and not robot.sent("gimbal") and not robot.sent("anim"),
			"不动模式:代解与表情照常,云台/动画一条不发")
	robot.set_stationary(false)
	_check(game.save.settings.get("robot_stationary") == false, "开关状态写进 settings")
	game.save.wipe()

	# ---- S. 操作指引(v1.1 后剩 钉/放/拉 三步,存档 steps 记忆,刚 wipe 过)+ 笔记自动弹出:首次上架的仪器进关自动翻到它那页 ----
	game.start_level(game.catalog.find(&"l01"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	var s1 := current_scene as LevelScene
	_check(not s1._notebook_ui.is_open(), "l01 没有新仪器:笔记不自动弹出")
	_check(s1._step_hint.visible and s1._step_hint.text == StepGuide.TEXT[&"wire"], "l01 没有仪器架:提示拉线")
	_check(not s1._guide_hint.visible or s1._step_hint.position.y < s1._guide_hint.position.y, "操作指引在求助提示上一行")
	s1.session.connect_wire(s1.session.assumption_ids[0], 0, s1.session.goal_id, 0)
	await _settle()
	_check(not s1._step_hint.visible and game.save.is_step_done(&"wire"), "拉线通关 → 指引消失、拉线记为做过")
	game.start_level(game.catalog.find(&"l02"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	var s2 := current_scene as LevelScene
	var nb2: NotebookUI = s2._notebook_ui
	await _wait_until(func() -> bool: return nb2.is_open() and is_equal_approx(nb2._drawer.position.x, NotebookUI.OPEN_X), 3.0)
	_check(nb2.is_open() and is_equal_approx(nb2._drawer.position.x, NotebookUI.OPEN_X), "l02 首次上架并织机:进关笔记自动划出")
	_check(nb2._entries.size() == 1 and nb2._page == 0 and nb2._page_pic.texture.resource_path.ends_with("notebook/and_intro.png"),
			"自动翻到并织机那页")
	_click(_center(nb2._handle), MOUSE_BUTTON_LEFT)   # 继续工作
	await nb2.slide_finished
	await _settle()
	_check(not nb2.is_open(), "点「继续工作」收起")
	_check(s2._step_hint.visible and s2._step_hint.text == StepGuide.TEXT[&"place"], "l02 空盘:提示从仪器架放仪器")
	_click(_center(_button_named(s2._palette, "并织机")), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(game.save.is_step_done(&"place") and not s2._step_hint.visible, "放了仪器(拉线已学过)→ 不再提示(翻笔记/断线不再是指引)")
	s2.session.connect_wire(s2.session.assumption_ids[0], 0, s2.session.goal_id, 0)   # 线轴 A 直接接目标 A & B:冲突
	await _settle()
	_check(not s2._step_hint.visible, "接错的线不出指引(它会自己断开)")
	await _wait(ProofBoard.BAD_WIRE_SEC + 0.2)
	_check(s2.session.get_wires().is_empty(), "接错的线自动断开")
	game.start_level(game.catalog.find(&"l07"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	var s3 := current_scene as LevelScene
	var nb3: NotebookUI = s3._notebook_ui
	await _wait_until(func() -> bool: return nb3.is_open() and is_equal_approx(nb3._drawer.position.x, NotebookUI.OPEN_X), 3.0)
	_check(nb3.is_open() and nb3._entries[nb3._page].id == &"imp_intro", "l07 首次上架封程机:自动翻到封程机那页(不是第一页)")
	_click(_center(nb3._handle), MOUSE_BUTTON_LEFT)
	await nb3.slide_finished
	await _settle()
	_check(not s3._step_hint.visible, "l07 空盘:放仪器做过 → 不提示")
	_click(_center(_button_named(s3._palette, "封程机")), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(s3._step_hint.visible and s3._step_hint.text == StepGuide.TEXT[&"pin"], "封程机假设口没钉 → 提示钉纹样")
	var s3_board: ProofBoard = s3._board
	var s3_mn := s3_board.get_node("n%d" % s3.session.get_node_ids()[-1]) as MachineNode
	_click(_center(s3_mn._pin_buttons[1]), MOUSE_BUTTON_LEFT)
	await _settle()
	s3._editor.tree = FormulaParser.parse("A")
	s3._editor.pattern_committed.emit(s3._editor.tree)
	s3._editor.hide()
	await _settle()
	_check(game.save.is_step_done(&"pin") and not s3._step_hint.visible, "钉住后 pin 记为做过,不再提示")
	var saved_steps: Dictionary = SaveManager.open().steps
	_check(saved_steps.has("wire") and saved_steps.has("place") and saved_steps.has("pin") and not saved_steps.has("fix") and not saved_steps.has("notebook"),
			"三个操作落进存档 steps,没有 fix/notebook")
	game.save.wipe()
	_check(game.save.steps.is_empty(), "重置进度清掉指引记忆")

	# ---- S. 无机器人模式:一切指向实体小机的提示/入口消失;标题页 F9 是切回入口 ----
	robot.set_enabled(false, false)   # 不落盘:别污染开发机存档
	game.start_level(game.catalog.find(&"l01"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	var g6 := current_scene as LevelScene
	_check(g6 != null and not g6._guide_hint.visible and not g6.is_processing(), "无机器人模式:关内不显示求助提示、发呆计时不跑")
	_check(g6 != null and _visible_texts_with(g6, "小机").is_empty(), "无机器人模式:关卡场景没有任何可见文字提到小机")
	robot.sent_log.clear()
	robot._last_guide_ms = -100000
	robot._on_event({"evt": "speech", "text": "请 指导 我"})
	await _wait(1.0)
	_check(g6 != null and not g6.session.is_solved() and robot.sent_log.is_empty(), "无机器人模式:语音事件不代解、不发命令")
	game.goto_credits()
	await _settle()
	var credit_texts := _visible_button_texts(current_scene)
	_check(credit_texts == ["返回主界面"] and _visible_texts_with(current_scene, "小机").is_empty(),
			"无机器人模式:开发者信息页没有「小机维护」(得 %s)" % str(credit_texts))
	game.goto_menu()
	await _settle()
	var menu2 := current_scene as MainMenu
	_key(KEY_F9)
	await _settle()
	_check(menu2 != null and menu2._cal_ui.visible and menu2._cal_ui._mode_btn.text.contains("无机器人模式"), "标题页 F9 打开维护面板,开关显示无机器人模式")
	_check(menu2 != null and menu2._cal_ui._connect_btn.disabled and menu2._cal_ui._flash_btn.disabled, "无机器人模式:接入/刷入按钮置灰")
	_click(_center(menu2._cal_ui._mode_btn), MOUSE_BUTTON_LEFT)
	await _settle()
	_check(robot.enabled and menu2._cal_ui._mode_btn.text.contains("已启用") and game.save.settings.get("robot_enabled") == true
			and not menu2._cal_ui._connect_btn.disabled, "点开关 → 启用、写进 settings、按钮恢复")
	game.save.settings.erase("robot_enabled")   # 开发机不留痕:回到平台默认(macOS 开)
	game.save.save()
	_click(_center(_button_named(menu2._cal_ui, "关闭")), MOUSE_BUTTON_LEFT)
	await _settle()
	game.start_level(game.catalog.find(&"l01"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	var g7 := current_scene as LevelScene
	_check(g7 != null and g7._guide_hint.visible and g7.is_processing(), "切回有机器人:求助提示与发呆计时恢复")
	game.save.wipe()

	# ---- T. 低功耗/帧率:静止棋盘不重绘,标题页流光照常动,帧率硬上限 60 ----
	_check(Engine.max_fps == 60 and OS.low_processor_usage_mode, "帧率上限 60 + 低功耗模式生效")
	game.start_level(game.catalog.find(&"l01"))
	await _settle()
	if current_scene is StoryScene:
		(current_scene as StoryScene).finish()
		await _settle()
	await _wait(1.6)   # 让进关的 BGM 淡入等 Tween 走完
	var drawn0 := Engine.get_frames_drawn()
	await _wait(1.0)
	var idle_draws := Engine.get_frames_drawn() - drawn0
	_check(idle_draws <= 10, "关内静止 1 s 重绘 ≤10 帧(得 %d;低功耗模式下静止画面不重绘)" % idle_draws)
	game.goto_menu()
	await _settle()
	await _wait(0.5)
	drawn0 = Engine.get_frames_drawn()
	await _wait(1.0)
	var title_draws := Engine.get_frames_drawn() - drawn0
	_check(title_draws >= 10 and title_draws <= 70, "标题页流光 1 s 重绘 10–70 帧(得 %d;TIME 着色器自动请求重绘,上限 60)" % title_draws)
	game.save.wipe()

	# ---- B. 回标题:BGM 淡入标题曲 ----
	game.goto_menu()
	await _settle()
	_check(bgm.slot == &"title" and bgm.is_playing(), "回标题 BGM 淡入标题曲")

	_finish()


func _finish() -> void:
	print("UI_SMOKE_FAILS=", _fails)
	quit(_fails)


## 轮询等待条件成立(带超时):代解等流程走定时器,冷启动首个窗口运行会有导入/着色器卡顿,
## 固定秒数等待会在慢机器上偶发竞态 —— 一律等到条件真了再断言。
func _wait_until(pred: Callable, timeout := 6.0) -> void:
	var t := 0.0
	while t < timeout and not pred.call():
		await _wait(0.1)
		t += 0.1
