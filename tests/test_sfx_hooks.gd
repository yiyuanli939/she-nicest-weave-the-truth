extends TestBase
## 操作音效的挂点(UI 冒烟没真实输入到的那些):拒删 / 拔线 / 接线被拒不响 / 拖动松手 / 缩放去重 / 重置 / 通关(代解不响)/
## 指引换条不重复 / 钉被拒·取消钉住 / 静音区间 / 撤销重建不响;钉纹样弹窗 开·笔刷·落笔·清空;对话 显示完·下一句;
## 设置弹窗 开·关·音效滑条;笔记抽屉 开·翻页·关;各按钮的 meta 槽位。无头下 LevelScene 用默认配置(无 Game)。
## 用 /root/Sfx(autoload)断言;--script 模式没有 autoload 时临时挂一个同名节点让 SoundFx.hit 找得到。


func _sfx() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var s := tree.root.get_node_or_null("Sfx")
	if s == null:
		s = load("res://game/sfx.gd").new()
		s.name = "Sfx"
		tree.root.add_child(s)
	s._frame_played.clear()   # 所有用例在同一帧里跑:清掉同帧去重记录,否则上个用例播过的槽位这里不响
	return s


func _count(sfx: Node, slot: StringName) -> int:
	return int(sfx.counts.get(slot, 0))


func test_board_and_level_hooks() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var sfx := _sfx()
	var scene := LevelScene.new()
	tree.root.add_child(scene)
	var board: ProofBoard = scene._board
	var s: ProofSession = scene.session
	var ok := check(_count(sfx, &"hint") == 1, "进关时操作指引出现响一次 hint(得 %d)" % _count(sfx, &"hint"))
	scene._refresh_step_hint()
	ok = check(_count(sfx, &"hint") == 1, "指引没换条不再响") and ok
	# 拒删 / 放置 / 拖动
	board._remove_machine(s.assumption_ids[0])
	ok = check(sfx.last_slot == &"refuse" and s.describe_node(s.assumption_ids[0]) != null, "删线轴被拒响 refuse") and ok
	board.place_machine_at_center(&"and_elim")
	var mid: int = s.get_node_ids()[-1]
	ok = check(sfx.last_slot == &"place", "放仪器响 place") and ok
	var n_place := _count(sfx, &"place")
	board.place_machine_at_center(&"no_such_rule")
	ok = check(_count(sfx, &"place") == n_place, "放置被模型拒绝(未知仪器)不响") and ok
	board._on_end_node_move()
	ok = check(sfx.last_slot == &"move", "拖动松手响 move") and ok
	# 缩放:只在 zoom 变了才响
	board.zoom = 1.25
	board._on_zoom_check()
	ok = check(sfx.last_slot == &"zoom", "缩放响 zoom") and ok
	var n_zoom := _count(sfx, &"zoom")
	board._on_zoom_check()
	ok = check(_count(sfx, &"zoom") == n_zoom, "zoom 没变的重绘不响") and ok
	# 接线:被拒(自环)不响;接上响 plug;拔线响 unplug
	var mn := board.get_node("n%d" % mid) as MachineNode
	var n_plug := _count(sfx, &"plug")
	board._on_connection_request(mn.name, mn.graph_out_port(0), mn.name, 0)
	ok = check(_count(sfx, &"plug") == n_plug and s.get_wires().is_empty(), "自环接线被拒不响") and ok
	var spool := board.get_node("n%d" % s.assumption_ids[0]) as MachineNode
	board._on_connection_request(spool.name, spool.graph_out_port(0), mn.name, 0)
	ok = check(sfx.last_slot == &"plug" and s.get_wires().size() == 1, "接上响 plug") and ok
	board._on_disconnection_request(spool.name, spool.graph_out_port(0), mn.name, 0)
	ok = check(sfx.last_slot == &"unplug" and s.get_wires().is_empty(), "右键拔线响 unplug") and ok
	# 钉:非可钉口被拒 → pin_error;取消钉住 → unpin
	scene._pin_target = Vector2i(mid, 0)
	scene._on_pattern_committed(f("A"))
	ok = check(sfx.last_slot == &"pin_error", "拆股机出口不可钉 → pin_error(得 %s)" % sfx.last_slot) and ok
	scene._on_pattern_cleared()
	ok = check(sfx.last_slot == &"unpin", "空画布确认响 unpin") and ok
	# 撤销重建期间不响(重建徽章 / 节点都不算操作);栈空的撤销不响
	var before: int = sfx.play_count
	s.undo()
	var undo_plays: int = sfx.play_count - before
	ok = check(undo_plays == 0, "撤销触发的整盘重建不响(多响了 %d 声)" % undo_plays) and ok
	# 静音区间:代解 / 载入期间放机不响,退出后恢复
	scene._sfx_mute(true)
	n_place = _count(sfx, &"place")
	board.place_machine_at_center(&"and_intro")
	ok = check(_count(sfx, &"place") == n_place and sfx.is_muted(), "静音区间内放仪器不响") and ok
	scene._sfx_mute(false)
	ok = check(not sfx.is_muted(), "静音计数归零") and ok
	# 重置 / 通关
	scene._on_reset()
	ok = check(sfx.last_slot == &"reset_board", "重置响 reset_board") and ok
	var n_win := _count(sfx, &"win")
	scene._suppress_win_cue = true
	scene._on_win()
	ok = check(_count(sfx, &"win") == n_win, "小机代解通关不响 win") and ok
	scene._suppress_win_cue = false
	scene._on_win()
	ok = check(_count(sfx, &"win") == n_win + 1, "玩家通关响 win") and ok
	scene._restoring = true
	scene._on_win()
	ok = check(_count(sfx, &"win") == n_win + 1, "载入通关盘不响 win") and ok
	scene._restoring = false
	# 按钮 meta:仪器架 / 钉纹样 / 笔记夹子 / 重置 不响 click;选关 back
	var and_btn := scene._palette.button_of(&"and_intro")
	ok = check(SoundFx.button_slot(and_btn) == &"" and SoundFx.button_slot(scene._notebook_ui._handle) == &""
			and SoundFx.button_slot(scene._notebook_ui._flip) == &"", "仪器架 / 笔记夹子 / 翻页按钮本身不响") and ok
	var reset_btn: Button = null
	var back_btn: Button = null
	for b in scene.find_children("*", "Button", true, false):
		if (b as Button).text == "重置":
			reset_btn = b
		elif (b as Button).text == "选关":
			back_btn = b
	ok = check(reset_btn != null and SoundFx.button_slot(reset_btn) == &"" and back_btn != null and SoundFx.button_slot(back_btn) == &"back",
			"工具条:重置不响(动作音在 _on_reset)、选关响 back") and ok
	board.place_machine_at_center(&"or_intro")   # 岔纹机有可钉口 → 有「钉纹样」按钮
	var or_n := board.get_node("n%d" % s.get_node_ids()[-1]) as MachineNode
	var pin_ok := not or_n._pin_buttons.is_empty()
	for port in or_n._pin_buttons:
		pin_ok = pin_ok and SoundFx.button_slot(or_n._pin_buttons[port]) == &""
	ok = check(pin_ok, "节点内「钉纹样」按钮不响(弹窗开时响 open)") and ok
	tree.root.remove_child(scene)
	scene.free()
	return ok


func test_pattern_editor_hooks() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var sfx := _sfx()
	var ed := PatternEditor.new()
	tree.root.add_child(ed)
	ed.open_for([&"A", &"B"], {}, null, true)
	var ok := check(sfx.last_slot == &"open", "钉纹样弹窗打开响 open(得 %s)" % sfx.last_slot)
	var brush_ok := ed._brush_row.get_child_count() >= 5
	for b in ed._brush_row.get_children():
		brush_ok = brush_ok and b is Button and SoundFx.button_slot(b) == &"brush"
	ok = check(brush_ok, "原子 / 结构 / 焦纹笔刷按钮都响 brush") and ok
	var n_paint := _count(sfx, &"paint")
	ed.brush = ""
	ed.apply_brush_at(Vector2(10, 10), Rect2(0, 0, 100, 100))
	ok = check(_count(sfx, &"paint") == n_paint, "没选笔刷落笔不响") and ok
	ed.brush = "atom:A"
	ed.apply_brush_at(Vector2(10, 10), Rect2(0, 0, 100, 100))
	ok = check(sfx.last_slot == &"paint" and not ed.is_canvas_empty(), "落笔响 paint") and ok
	ok = check(SoundFx.button_slot(ed._clear_btn) == &"clear" and SoundFx.button_slot(ed._confirm) == &"", "「清空」响 clear,「确认」不响(结果音由 LevelScene 出)") and ok
	var cancel: Button = null
	for b in ed.find_children("*", "Button", true, false):
		if (b as Button).text == "取消":
			cancel = b
	ok = check(cancel != null and SoundFx.button_slot(cancel) == &"", "「取消」按钮本身不响(关闭音统一在 popup_hide 里出)") and ok
	var n_close := _count(sfx, &"close")
	ed.hide()   # 取消 / Esc / 点弹窗外面都走这条:响一声 close
	ok = check(_count(sfx, &"close") == n_close + 1, "弹窗以任何方式关掉响一声 close(得 +%d)" % (_count(sfx, &"close") - n_close)) and ok
	ed.open_for([&"A", &"B"], {}, null, true)
	n_close = _count(sfx, &"close")
	ed._on_confirm()   # 「确认」关闭:结果音归 LevelScene,不响 close
	ok = check(_count(sfx, &"close") == n_close and not ed.visible, "「确认」关弹窗不响 close") and ok
	ed.open_for([&"A", &"B"], {}, null, true)
	n_close = _count(sfx, &"close")
	sfx._frame_played.erase(&"close")   # 同一帧里已经响过一次 close,去重会挡掉这次;测试里手动放行
	ed.hide()
	ok = check(_count(sfx, &"close") == n_close + 1, "确认过一次之后再取消仍响 close(标记复位)") and ok
	tree.root.remove_child(ed)
	ed.free()
	return ok


func test_dialogue_hooks() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var sfx := _sfx()
	var db := DialogueBox.new()
	tree.root.add_child(db)
	var dlg := DialogueRes.new()
	for i in 2:
		var l := DialogueLine.new()
		l.speaker = "诺拉"
		l.text = "一段足够长的台词让打字机还没打完就被点了一下一二三四五六七八九十"
		dlg.lines.append(l)
	db.play(dlg)
	db._step()
	var ok := check(sfx.last_slot == &"skip" and db._idx == 0, "打字中点一下:先显示完,响 skip(得 %s)" % sfx.last_slot)
	db._step()
	ok = check(sfx.last_slot == &"next" and db._idx == 1, "显示完再点:下一句,响 next") and ok
	tree.root.remove_child(db)
	db.free()
	return ok


func test_settings_notebook_and_menu_buttons() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var sfx := _sfx()
	var p := SettingsPanel.new()
	tree.root.add_child(p)
	p.setup(null, null, null, null, sfx)
	p.open()
	var ok := check(sfx.last_slot == &"open", "设置弹窗打开响 open")
	p._sfx_volume.value = 0.5
	ok = check(sfx.last_slot == &"slider" and is_equal_approx(sfx.user_volume, 0.5), "音效滑条动一档:当场改音量并响 slider 试听") and ok
	sfx.set_user_volume(1.0)
	p.close()
	ok = check(sfx.last_slot == &"close", "关闭响 close") and ok
	ok = check(SoundFx.button_slot(p._fullscreen_btn) == &"toggle" and SoundFx.button_slot(p._robot_btn) == &"toggle"
			and SoundFx.button_slot(p._close_btn) == &"" and SoundFx.button_slot(p._maint_btn) == &"", "全屏 / 小机联动响 toggle;关闭 / 小机维护按钮本身不响") and ok
	tree.root.remove_child(p)
	p.free()
	var nb := NotebookUI.new()
	tree.root.add_child(nb)
	nb.open(NotebookCatalog.load_default(), [&"and_intro", &"and_elim"])
	ok = check(sfx.last_slot == &"drawer_open", "抽屉划出响 drawer_open") and ok
	nb._next_page()
	ok = check(sfx.last_slot == &"page", "翻页响 page") and ok
	nb.close()
	ok = check(sfx.last_slot == &"drawer_close", "抽屉收回响 drawer_close") and ok
	tree.root.remove_child(nb)
	nb.free()
	var back := BackButton.make(func() -> void: pass)
	ok = check(SoundFx.button_slot(back) == &"back", "「返回主界面」响 back") and ok
	back.free()
	var wp := WinPopup.new()
	ok = check(SoundFx.button_slot(wp._continue_btn) == &"confirm", "通关弹窗「继续」响 confirm") and ok
	wp.free()
	return ok
