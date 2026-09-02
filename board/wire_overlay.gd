class_name WireOverlay
extends Control
## 连线视觉叠加层:出错的线在中点挂一枚错误徽章(正常线无浮层)。
## GraphEdit 的普通 Control 子节点,不吃鼠标;有徽章时才开 _process 跟随节点(rebuild 时缓存两端 GraphNode 引用,
## 每帧零分配、零查树;没徽章不跑 —— 低功耗模式下静止棋盘不重绘)。
## 徽章是纯文字(只用美术指定字体,不带符号);颜色在 BADGE_COLOR。

const BADGE: Dictionary = {
	ProofSession.WireState.CONFLICT: "冲突",
	ProofSession.WireState.UNDERSPEC: "欠定",
	ProofSession.WireState.CYCLE: "成环",
	ProofSession.WireState.ESCAPED_HYP: "逃逸",
}
const BADGE_COLOR: Dictionary = {
	ProofSession.WireState.CONFLICT: Color(0.85, 0.2, 0.2),
	ProofSession.WireState.UNDERSPEC: Color(0.55, 0.5, 0.4),
	ProofSession.WireState.CYCLE: Color(0.8, 0.45, 0.1),
	ProofSession.WireState.ESCAPED_HYP: Color(0.85, 0.2, 0.2),
}

var board: GraphEdit
var session: ProofSession

var _chips: Array[Dictionary] = []   # {ctrl: Control, wire: ProofSession.WireInfo, from_node: GraphNode, to_node: GraphNode}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(false)


## board_updated 后全量重建徽章;OK 的线不建浮层;两端节点引用一并缓存,_process 只在有徽章时跑
func rebuild() -> void:
	for c in _chips:
		(c.ctrl as Control).queue_free()
	_chips.clear()
	if session != null and board != null:
		for w in session.get_wires():
			if not BADGE.has(w.state):
				continue
			var chip := _make_chip(w)
			add_child(chip)
			_chips.append({ctrl = chip, wire = w,
				from_node = board.get_node_or_null("n%d" % w.from_id), to_node = board.get_node_or_null("n%d" % w.to_id)})
	set_process(not _chips.is_empty())


func _make_chip(w: ProofSession.WireInfo) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Label.new()
	b.text = BADGE[w.state]
	b.add_theme_font_size_override("font_size", 32)
	b.add_theme_color_override("font_color", BADGE_COLOR[w.state])
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(b)
	return box


func _process(_delta: float) -> void:
	for c in _chips:
		var w: ProofSession.WireInfo = c.wire
		var fn := c.from_node as GraphNode
		var tn := c.to_node as GraphNode
		var ctrl := c.ctrl as Control
		if not (is_instance_valid(fn) and is_instance_valid(tn) and fn.is_inside_tree() and tn.is_inside_tree()):
			ctrl.visible = false   # 节点已重建/释放:等下一次 rebuild 重新缓存
			continue
		ctrl.visible = true
		var a: Vector2 = fn.position + fn.get_output_port_position(w.from_port) * board.zoom
		var b: Vector2 = tn.position + tn.get_input_port_position(w.to_port) * board.zoom
		ctrl.position = (a + b) * 0.5 - ctrl.size * 0.5
