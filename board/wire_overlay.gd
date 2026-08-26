class_name WireOverlay
extends Control
## 连线视觉叠加层:每条线中点一枚纹样小片(PatternChip)+ 错误徽章。
## GraphEdit 的普通 Control 子节点,不吃鼠标;位置每帧重排(棋盘很小,便宜)。
## 徽章目前是文字占位;美术接口:换成 assets/svg/badges/*.svg(见 docs/ART_INTERFACE.md)。

const BADGE: Dictionary = {
	ProofSession.WireState.CONFLICT: "☠ 冲突",
	ProofSession.WireState.UNDERSPEC: "? 欠定",
	ProofSession.WireState.CYCLE: "◌ 成环",
	ProofSession.WireState.ESCAPED_HYP: "✂ 逃逸",
}
const BADGE_COLOR: Dictionary = {
	ProofSession.WireState.CONFLICT: Color(0.85, 0.2, 0.2),
	ProofSession.WireState.UNDERSPEC: Color(0.55, 0.5, 0.4),
	ProofSession.WireState.CYCLE: Color(0.8, 0.45, 0.1),
	ProofSession.WireState.ESCAPED_HYP: Color(0.85, 0.2, 0.2),
}

var board: GraphEdit
var session: ProofSession
var atom_colors: Dictionary = {}

var _chips: Array[Dictionary] = []   # {ctrl: Control, wire: ProofSession.WireInfo}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## board_updated 后全量重建小片
func rebuild() -> void:
	for c in _chips:
		(c.ctrl as Control).queue_free()
	_chips.clear()
	if session == null:
		return
	for w in session.get_wires():
		var chip := _make_chip(w)
		add_child(chip)
		_chips.append({ctrl = chip, wire = w})


func _make_chip(w: ProofSession.WireInfo) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := PatternView.new()
	v.atom_colors = atom_colors
	v.min_size = Vector2(40, 24)
	v.formula = session.get_input_pattern(w.to_id, w.to_port)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(v)
	if BADGE.has(w.state):
		var b := Label.new()
		b.text = BADGE[w.state]
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", BADGE_COLOR[w.state])
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(b)
	return box


func _process(_delta: float) -> void:
	if board == null:
		return
	for c in _chips:
		var w: ProofSession.WireInfo = c.wire
		var fn := board.get_node_or_null(NodePath("n%d" % w.from_id)) as GraphNode
		var tn := board.get_node_or_null(NodePath("n%d" % w.to_id)) as GraphNode
		var ctrl := c.ctrl as Control
		if fn == null or tn == null:
			ctrl.visible = false
			continue
		ctrl.visible = true
		var a: Vector2 = fn.position + fn.get_output_port_position(w.from_port) * board.zoom
		var b: Vector2 = tn.position + tn.get_input_port_position(w.to_port) * board.zoom
		ctrl.position = (a + b) * 0.5 - ctrl.size * 0.5
