extends SceneTree
## 音效时间线追踪(调试工具,不是测试):按真实输入走一遍 标题 → 选关 → 故事 → 第一纹接线通关 → 「继续」→ 第二纹 放机 / 点节点 /
## 拖节点 / 钉纹样弹窗 / 接线与改接 / 缩放 / 撤销重做 / 右键删 / 重置 / 笔记抽屉翻页 / 选关,每一步打印这一步响了哪些槽位(计数差)。
## 用来核对「一个操作响几声、响的是不是该响的」;不断言,退出码 0。跑之前备份存档、跑完复原。
## 钉纹样弹窗是 PopupPanel(独立嵌入窗口),root.push_input 送不进它里面的按钮 —— 弹窗内的操作走 pressed.emit / apply_brush_at,
## Esc 与点弹窗外面仍是真实输入。
##   godot --path . --script res://tools/sfx_trace.gd

const SAVE := "user://save.json"
const BAK := "user://save.json.sfx_trace_bak"

var _game: Node
var _sfx: Node
var _snap: Dictionary = {}
var _lines: Array[String] = []


func _initialize() -> void:
	await process_frame
	_game = root.get_node("Game")
	_sfx = root.get_node("Sfx")
	AudioServer.set_bus_mute(0, true)   # 别真出声;计数照记
	_backup()
	_game.save.wipe()
	_game.goto_menu()
	await _settle(3)
	_snapshot("(启动到标题页)")
	await _run()
	_restore()
	print("\n".join(_lines))
	quit(0)


func _run() -> void:
	# 标题 → 选关
	var menu := current_scene
	_click(_center(_button_named(menu, "开始游戏")), MOUSE_BUTTON_LEFT)
	await _settle(4)
	_snapshot("标题页点「开始游戏」→ 选关页")
	# 选关 → 第一纹故事
	var first: Button = null
	for b in current_scene.find_children("*", "Button", true, false):
		if (b as Button).text == "第一纹" and not (b as Button).disabled:
			first = b
	_click(_center(first), MOUSE_BUTTON_LEFT)
	await _settle(4)
	_snapshot("选关页点「第一纹」→ 故事界面")
	await _click_through_story("第一纹")
	# 第一纹棋盘:线轴 → 目标 真实拖线通关
	var scene: LevelScene = current_scene as LevelScene
	var board: ProofBoard = scene._board
	var s: ProofSession = scene.session
	var spool := board.get_node("n%d" % s.assumption_ids[0]) as MachineNode
	var goal := board.get_node("n%d" % s.goal_id) as MachineNode
	await _drag(spool.global_position + spool.port_pos(false, 0) * board.zoom, goal.global_position + goal.port_pos(true, 0) * board.zoom, "第一纹 拖线 线轴→目标(通关)")
	await _wait(1.2)
	_snapshot("  (通关后 1.2 s 内)")
	_click(_center(scene._win_popup._continue_btn), MOUSE_BUTTON_LEFT)
	await _settle(4)
	_snapshot("通关弹窗点「继续」→ 第二纹故事")
	await _click_through_story("第二纹")
	# 第二纹棋盘(进关自动弹出的笔记先收回,不然整页图挡住棋盘)
	scene = current_scene as LevelScene
	board = scene._board
	s = scene.session
	_click(_center(scene._notebook_ui._handle), MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("进关自动弹出的笔记:点夹子收回")
	_click(_center(scene._palette.button_of(scene.allowed_rules[0])), MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("点仪器架放一台 %s" % scene.allowed_rules[0])
	var mid: int = s.get_node_ids()[-1]
	s.set_node_position(mid, Vector2(900, 700))
	board.apply_positions()
	await _settle()
	_snapshot("  (脚本挪位置 apply_positions)")
	var mn := board.get_node("n%d" % mid) as MachineNode
	var body: Vector2 = _center(mn._in_views[0])
	_click(body, MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("点一下节点纹样(不动鼠标)")
	_click(body, MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("再点一下同一节点(已选中)")
	_press(body, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	_motion(body + Vector2(120, 80), MOUSE_BUTTON_MASK_LEFT)
	await _settle()
	_press(body + Vector2(120, 80), MOUSE_BUTTON_LEFT, false, 0)
	await _settle()
	_snapshot("拖动节点 120 px 松手")
	# 接线到仪器入口,再从入口把线拔起来改接
	spool = board.get_node("n%d" % s.assumption_ids[0]) as MachineNode
	mn = board.get_node("n%d" % mid) as MachineNode
	var in_pt: Vector2 = mn.global_position + mn.port_pos(true, 0) * board.zoom
	await _drag(spool.global_position + spool.port_pos(false, 0) * board.zoom, in_pt, "拖线 线轴→仪器入口")
	await _wait(0.8)
	_snapshot("  (0.8 s 后)")
	await _drag(in_pt, in_pt + Vector2(0, 300), "从已接的入口拖起线放到空处(改接)")
	await _wait(0.8)
	_snapshot("  (0.8 s 后)")
	# 缩放
	_wheel(board.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP)
	await _settle()
	_snapshot("棋盘滚轮放大一档")
	_wheel(board.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_DOWN)
	await _settle()
	_snapshot("滚轮缩小一档")
	# 撤销 / 重做
	_combo(KEY_Z, true, false)
	await _settle()
	_snapshot("Ctrl+Z 撤销")
	_combo(KEY_Z, true, true)
	await _settle()
	_snapshot("Ctrl+Shift+Z 重做")
	# 右键删 → 撤销
	mn = board.get_node("n%d" % mid) as MachineNode
	_click(_center(mn._in_views[0]), MOUSE_BUTTON_RIGHT)
	await _settle()
	_snapshot("右键节点纹样删机")
	_combo(KEY_Z, true, false)
	await _settle()
	_snapshot("Ctrl+Z 撤回删机")
	_click(_center((board.get_node("n%d" % s.goal_id) as MachineNode)._in_views[0]), MOUSE_BUTTON_RIGHT)
	await _settle()
	_snapshot("右键目标织机(拒删)")
	# 重置
	_click(_center(_button_named(scene, "重置")), MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("工具条「重置」")
	# 笔记
	var nb: NotebookUI = scene._notebook_ui
	_click(_center(nb._handle), MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("点笔记夹子(划出)")
	if nb._flip.visible:
		_click(_center(nb._flip), MOUSE_BUTTON_LEFT)
		await _settle()
		_snapshot("点翻页")
	_click(_center(nb._handle), MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("点夹子(收回)")
	# 悬停
	_motion(_center(_button_named(scene, "选关")), 0)
	await _settle()
	_snapshot("鼠标移到「选关」上(悬停)")
	_motion(_center(_button_named(scene, "重置")), 0)
	await _settle()
	_snapshot("鼠标移到「重置」上(悬停)")
	_click(_center(_button_named(scene, "选关")), MOUSE_BUTTON_LEFT)
	await _settle(4)
	_snapshot("工具条「选关」→ 选关页")
	_click(_center(_button_named(current_scene, "返回主界面")), MOUSE_BUTTON_LEFT)
	await _settle(4)
	_snapshot("选关页「返回主界面」→ 标题")
	_click(_center(_button_named(current_scene, "开发者信息")), MOUSE_BUTTON_LEFT)
	await _settle(4)
	_snapshot("标题页「开发者信息」")
	_key(KEY_ESCAPE)
	await _settle(4)
	_snapshot("开发者信息页 Esc 回标题")
	await _pin_popup_checks()


## 钉纹样弹窗:并织机没有可钉口,注入一关(无对话)放岔纹机来试
func _pin_popup_checks() -> void:
	var lv := LevelDef.new()
	lv.id = &"sfx_trace_pin"
	lv.title = "第九纹"
	lv.assumptions = ["A & B"]
	lv.goal = "B & A"
	lv.allowed_rules = [&"and_intro", &"and_elim", &"or_intro", &"imp_intro"]
	lv.atoms = [&"A", &"B"]
	_game.start_level(lv)
	await _settle(4)
	_snapshot("注入无对话关直接进棋盘(进关瞬间)")
	await _wait(1.0)
	_snapshot("  (进关后 1 s 内)")
	var scene: LevelScene = current_scene as LevelScene
	if scene._notebook_ui.is_open():
		_click(_center(scene._notebook_ui._handle), MOUSE_BUTTON_LEFT)
		await _settle()
		_snapshot("  笔记收回")
	_click(_center(_button_named(scene._palette, "岔纹机")), MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("放岔纹机")
	var s: ProofSession = scene.session
	var mid: int = s.get_node_ids()[-1]
	s.set_node_position(mid, Vector2(900, 700))
	scene._board.apply_positions()
	await _settle()
	var mn := scene._board.get_node("n%d" % mid) as MachineNode
	var pin_btn: Button = mn._pin_buttons.values()[0]
	_motion(_center(pin_btn), 0)
	await _settle()
	_snapshot("鼠标移到「钉纹样」按钮上")
	_click(_center(pin_btn), MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("点节点里「钉纹样」按钮")
	_button_named(scene._editor, "取消").pressed.emit()
	await _settle()
	_snapshot("弹窗「取消」")
	_click(_center(pin_btn), MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("再开弹窗")
	_key(KEY_ESCAPE)
	await _settle()
	_snapshot("弹窗按 Esc(%s)" % ("关了" if not scene._editor.visible else "没关"))
	_click(_center(pin_btn), MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("再开弹窗(未钉的口:空画布,「确认」%s)" % ("不可按" if scene._editor._confirm.disabled else "可按"))
	var brush: Button = scene._editor._brush_row.get_child(0)
	brush.pressed.emit()
	await _settle()
	_snapshot("选第一个笔刷")
	scene._editor.apply_brush_at(Vector2(10, 10), Rect2(0, 0, 100, 100))
	await _settle()
	_snapshot("画布上落一笔")
	scene._editor._confirm.pressed.emit()
	await _settle()
	_snapshot("画了一笔点「确认」(钉住)")
	_click(_center(pin_btn), MOUSE_BUTTON_LEFT)
	await _settle()
	_snapshot("已钉的口再开弹窗")
	scene._editor._clear_btn.pressed.emit()
	await _settle()
	_snapshot("点「清空」")
	scene._editor._confirm.pressed.emit()
	await _settle()
	_snapshot("空画布点「确认」(取消钉住)")
	_click(_center(pin_btn), MOUSE_BUTTON_LEFT)
	await _settle()
	_click(scene._board.get_global_rect().get_center() + Vector2(700, 500), MOUSE_BUTTON_LEFT)   # 弹窗外的棋盘空处
	await _settle()
	_snapshot("点弹窗外面(%s)" % ("关了" if not scene._editor.visible else "没关"))


func _click_through_story(tag: String) -> void:
	var n := 0
	while current_scene is StoryScene and n < 40:
		var box: DialogueBox = (current_scene as StoryScene)._dialogue
		var typing: bool = box._text.visible_characters < box._text.get_total_character_count()
		_click(_center(box._text), MOUSE_BUTTON_LEFT)
		await _settle(3)
		_snapshot("%s 故事 第 %d 次点击(%s)" % [tag, n + 1, "打字中" if typing else "整句已显示"])
		n += 1
		if not (current_scene is StoryScene):
			break
		await _wait(0.6)
		_snapshot("  (等 0.6 s)")
	await _settle(4)
	_snapshot("%s 故事结束 → 棋盘(进关瞬间)" % tag)
	await _wait(1.0)
	_snapshot("  (进关后 1 s 内)")


func _drag(from_pt: Vector2, to_pt: Vector2, label: String) -> void:
	_press(from_pt, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	_motion((from_pt + to_pt) * 0.5, MOUSE_BUTTON_MASK_LEFT)
	await _settle()
	_snapshot(label + " — 按下拖到半路")
	_motion(to_pt, MOUSE_BUTTON_MASK_LEFT)
	_press(to_pt, MOUSE_BUTTON_LEFT, false, 0)
	await _settle()
	_snapshot(label + " — 松手")


# ---- 记录 ----

func _snapshot(label: String) -> void:
	var parts: Array[String] = []
	for k in _sfx.counts:
		var d: int = int(_sfx.counts[k]) - int(_snap.get(k, 0))
		if d > 0:
			parts.append("%s×%d" % [k, d] if d > 1 else String(k))
	_snap = _sfx.counts.duplicate()
	var muted := "  [静音中]" if _sfx.is_muted() else ""
	_lines.append("%-46s %s%s" % [label, "、".join(parts) if not parts.is_empty() else "—", muted])


# ---- 真实输入(与 tests/visual_smoke_ui.gd 同一套) ----

func _settle(frames: int = 2) -> void:
	for i in frames:
		await process_frame


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


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


func _wheel(at: Vector2, button: MouseButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.factor = 1.0
		ev.position = at
		ev.global_position = at
		root.push_input(ev, true)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.pressed = pressed
		root.push_input(ev, true)


func _combo(keycode: Key, ctrl: bool, shift: bool) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.ctrl_pressed = ctrl
		ev.meta_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = pressed
		root.push_input(ev, true)


func _button_named(from: Node, text: String) -> Button:
	for b in from.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


# ---- 存档备份 / 复原 ----

func _backup() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE), ProjectSettings.globalize_path(BAK))


func _restore() -> void:
	if FileAccess.file_exists(BAK):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(BAK), ProjectSettings.globalize_path(SAVE))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BAK))
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
