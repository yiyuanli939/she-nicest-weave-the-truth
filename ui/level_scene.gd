class_name LevelScene
extends Control
## 关卡场景:ProofSession + ProofBoard + 仪器架 + HUD 组装。
## M1:硬编码一关(A & B ⊢ B & A);M3 起由 Game.current_level 注入 LevelDef。

var session := ProofSession.new()

var _board: ProofBoard
var _palette: PalettePanel
var _status: Label
var _win_flash: ColorRect
var _editor: PatternEditor
var _pin_target := Vector2i(-1, -1)   # (node_id, out_port) 正在编辑的假设口

# 默认关卡(M3 起由 Game 注入 LevelDef 覆盖)
var assumptions: Array[String] = ["A & B"]
var goal_text := "B & A"
var allowed_rules: Array[StringName] = [&"and_intro", &"and_elim"]
var atom_colors: Dictionary = {&"A": Color(0.82, 0.35, 0.30), &"B": Color(0.27, 0.42, 0.70)}
var atoms: Array[StringName] = [&"A", &"B"]
var allow_bot := false


func _ready() -> void:
	add_child(session)
	_build_ui()
	session.proof_completed.connect(_on_win)
	var err := session.setup(assumptions, goal_text)
	assert(err == "", err)
	_layout_endpoints()
	_palette.set_rules(allowed_rules)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var hud := HBoxContainer.new()
	var goal_lbl := Label.new()
	goal_lbl.text = "  目标纹样:%s" % goal_text
	hud.add_child(goal_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(spacer)
	_status = Label.new()
	_status.text = ""
	hud.add_child(_status)
	for pair in [["撤销", _on_undo], ["重做", _on_redo], ["重置", _on_reset]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		hud.add_child(b)
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
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_redo"):
		session.redo()
		get_viewport().set_input_as_handled()


## 线轴排左列、目标织机放右侧
func _layout_endpoints() -> void:
	var y := 80.0
	for id in session.assumption_ids:
		session.set_node_position(id, Vector2(60, y))
		y += 130
	session.set_node_position(session.goal_id, Vector2(760, 140))
	_board.apply_positions()


func _on_win() -> void:
	_status.text = "织成了!  "
	var tw := create_tween()
	tw.tween_property(_win_flash, "color:a", 0.35, 0.25)
	tw.tween_property(_win_flash, "color:a", 0.0, 0.9)


func _on_undo() -> void:
	session.undo()
	_status.text = ""


func _on_redo() -> void:
	session.redo()


func _on_reset() -> void:
	session.reset()
	_layout_endpoints()
	_status.text = ""
