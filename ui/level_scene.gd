class_name LevelScene
extends Control
## 关卡场景:ProofSession + ProofBoard + 仪器架 + HUD + 关内对话框。
## 开场对话已移到进关前的 StoryScene(见 game.start_level);_dialogue 留给关内剧情用。
## 有 Game autoload 且设了 current 关卡时从 LevelDef 读配置(含棋盘恢复);
## 否则用下面的默认字段(冒烟测试直接注入)。

var session := ProofSession.new()

var _game: Node = null
var _board: ProofBoard
var _palette: PalettePanel
var _status: Label
var _win_flash: ColorRect
var _editor: PatternEditor
var _dialogue: DialogueBox
var _next_btn: Button
var _pin_target := Vector2i(-1, -1)   # (node_id, out_port) 正在编辑的假设口
var _fresh_state: Dictionary = {}     # setup 刚完成的快照,重置用
var _idle_sec := 0.0                  # 发呆计时 → 小机出声引导
var _restoring := false               # 载入旧棋盘触发的 proof_completed 不算新胜利

const IDLE_HINT_SEC := 45.0

# 默认配置(无 Game 时生效;冒烟测试注入)
var level_title := ""
var assumptions: Array[String] = ["A & B"]
var goal_text := "B & A"
var allowed_rules: Array[StringName] = [&"and_intro", &"and_elim"]
var atom_colors: Dictionary = {&"A": Color(0.82, 0.35, 0.30), &"B": Color(0.27, 0.42, 0.70)}
var atoms: Array[StringName] = [&"A", &"B"]
var allow_bot := false


func _ready() -> void:
	_game = get_node_or_null("/root/Game")
	var lv: LevelDef = _game.current if _game != null else null
	if lv != null:
		level_title = lv.title
		assumptions = lv.assumptions
		goal_text = lv.goal
		allowed_rules = lv.allowed_rules
		atoms = lv.atoms
		atom_colors = lv.effective_colors()
		allow_bot = lv.allow_bot
	add_child(session)
	_build_ui()
	session.proof_completed.connect(_on_win)
	session.board_updated.connect(_on_conflict_check)
	session.board_updated.connect(func() -> void: _idle_sec = 0.0)
	var err := session.setup(assumptions, goal_text)
	assert(err == "", err)
	_layout_endpoints()
	_fresh_state = session.save_state()
	_palette.set_rules(allowed_rules)
	if lv != null:
		var saved: Dictionary = _game.save.board_state(lv.id)
		if not saved.is_empty():
			_restoring = true
			session.load_state(saved)
			_restoring = false
			_board.apply_positions()
		if lv.robot_cue_on_enter != "":
			_game.robot_cue(lv.robot_cue_on_enter)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var hud := HBoxContainer.new()
	var goal_lbl := Label.new()
	var prefix := ("  %s · " % level_title) if level_title != "" else "  "
	goal_lbl.text = "%s目标纹样:%s" % [prefix, goal_text]
	hud.add_child(goal_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(spacer)
	_status = Label.new()
	hud.add_child(_status)
	var reset_btn := Button.new()
	reset_btn.text = "重置"
	reset_btn.pressed.connect(_on_reset)
	hud.add_child(reset_btn)
	if _game != null:
		_next_btn = Button.new()
		_next_btn.text = "下一关 ▶"
		_next_btn.visible = false
		_next_btn.pressed.connect(_on_next)
		hud.add_child(_next_btn)
		var back := Button.new()
		back.text = "选关"
		back.pressed.connect(_on_back)
		hud.add_child(back)
	root.add_child(hud)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_palette = PalettePanel.new()
	body.add_child(_palette)
	_board = ProofBoard.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.atom_colors = atom_colors
	_board.bind(session)
	body.add_child(_board)
	_palette.machine_requested.connect(_board.place_machine_at_center)

	_win_flash = ColorRect.new()
	_win_flash.color = Color(0.2, 0.85, 0.35, 0.0)
	_win_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_win_flash)

	_editor = PatternEditor.new()
	_editor.pattern_committed.connect(_on_pattern_committed)
	_editor.pattern_cleared.connect(_on_pattern_cleared)
	add_child(_editor)
	_board.pin_requested.connect(_on_pin_requested)

	_dialogue = DialogueBox.new()
	if _game != null:
		_dialogue.cue.connect(_game.robot_cue)
	add_child(_dialogue)


## 线轴排左列、目标织机放右侧
func _layout_endpoints() -> void:
	var y := 80.0
	for id in session.assumption_ids:
		session.set_node_position(id, Vector2(60, y))
		y += 130
	session.set_node_position(session.goal_id, Vector2(760, 140))
	_board.apply_positions()


# ---- 假设口钉纹样 ----

func _on_pin_requested(node_id: int, out_port: int) -> void:
	_pin_target = Vector2i(node_id, out_port)
	var info := session.describe_node(node_id)
	var initial: Formula = null
	var pinned := info != null and info.pinned.has(out_port)
	if pinned:
		initial = FormulaParser.parse(info.pinned[out_port])
	_editor.open_for(atoms, atom_colors, initial, allow_bot, pinned)


func _on_pattern_committed(f: Formula) -> void:
	var err := session.pin_hypothesis(_pin_target.x, _pin_target.y, FormulaParser.to_text(f))
	if err != "":
		_status.text = err
	elif not session.is_solved():
		_status.text = ""


func _on_pattern_cleared() -> void:
	session.unpin_hypothesis(_pin_target.x, _pin_target.y)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_undo"):
		session.undo()
		_status.text = ""
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_redo"):
		session.redo()
		get_viewport().set_input_as_handled()


## 发呆太久 → 小机语音引导(Robot 侧对 hint 也有节流)
func _process(delta: float) -> void:
	if _game == null or session.is_solved():
		return
	_idle_sec += delta
	if _idle_sec >= IDLE_HINT_SEC:
		_idle_sec = 0.0
		_game.robot_cue("hint")


## 接出冲突线 → 小机困惑(Robot 侧自带节流,这里只管报)
func _on_conflict_check() -> void:
	if _game == null:
		return
	for w in session.get_wires():
		if w.state == ProofSession.WireState.CONFLICT:
			_game.robot_cue("confused")
			return


# ---- 胜负与流程 ----

func _on_win() -> void:
	_status.text = "织成了!  "
	if _next_btn != null and _game != null and _game.next_level() != null:
		_next_btn.visible = true
	if _restoring:
		return   # 只是恢复旧棋盘:不闪光、不叫小机、不重复记档
	var tw := create_tween()
	tw.tween_property(_win_flash, "color:a", 0.35, 0.25)
	tw.tween_property(_win_flash, "color:a", 0.0, 0.9)
	if _game != null:
		_game.notify_solved(session.save_state())


func _on_next() -> void:
	_game.store_board(session.save_state())
	_game.start_level(_game.next_level())


func _on_back() -> void:
	_game.store_board(session.save_state())
	_game.goto_select()


func _on_reset() -> void:
	session.load_state(_fresh_state)
	_layout_endpoints()
	_status.text = ""
