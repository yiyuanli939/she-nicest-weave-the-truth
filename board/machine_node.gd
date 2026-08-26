class_name MachineNode
extends GraphNode
## 棋盘上的一个节点(仪器/线轴/目标织机)的视图。
## 只认 ProofSession 的 NodeInfo/查询函数;一行 slot = 一对(输入口, 输出口)。
## 假设口(线轴口)用强调色;titlebar 的"钉纹样"按钮由 M2 的纹样编辑器接管。

signal pin_requested(out_port: int)

const PORT_COLOR := Color(0.72, 0.58, 0.34)   # 黄铜
const HYP_COLOR := Color(0.85, 0.42, 0.55)    # 假设口强调色
const GOAL_COLOR := Color(0.90, 0.76, 0.28)   # 目标金

var node_id: int = -1
var node_type: int = ProofSession.NodeType.MACHINE
var atom_colors: Dictionary = {}

var _in_views: Array[PatternView] = []
var _out_views: Array[PatternView] = []
var _hyp_ports: Array[int] = []


func build_from(info: ProofSession.NodeInfo) -> void:
	node_id = info.id
	node_type = info.type
	name = "n%d" % info.id
	title = info.title
	_in_views.clear()
	_out_views.clear()
	_hyp_ports.clear()
	var big := info.type != ProofSession.NodeType.MACHINE   # 线轴/目标:单口大纹样
	var rows := maxi(info.inputs.size(), info.outputs.size())
	for row in rows:
		var h := HBoxContainer.new()
		h.custom_minimum_size.y = 44 if big else 34
		if row < info.inputs.size():
			h.add_child(_make_port_cell(info.inputs[row], _in_views, big))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.custom_minimum_size.x = 12
		h.add_child(spacer)
		if row < info.outputs.size():
			var cell := _make_port_cell(info.outputs[row], _out_views, big)
			if info.outputs[row].is_hypothesis:
				_hyp_ports.append(row)
			h.add_child(cell)
		add_child(h)
		var out_is_hyp := row < info.outputs.size() and info.outputs[row].is_hypothesis
		set_slot(row,
				row < info.inputs.size(), 0, GOAL_COLOR if info.type == ProofSession.NodeType.GOAL else PORT_COLOR,
				row < info.outputs.size(), 0, HYP_COLOR if out_is_hyp else PORT_COLOR)
	if not _hyp_ports.is_empty():
		var btn := Button.new()
		btn.text = "钉纹样"
		btn.tooltip_text = "为假设口指定纹样(线轴口)"
		btn.pressed.connect(_on_pin_pressed)
		get_titlebar_hbox().add_child(btn)


func _make_port_cell(port: ProofSession.PortInfo, views: Array[PatternView], big: bool) -> Control:
	var box := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = port.label
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(1, 1, 1, 0.75)
	box.add_child(lbl)
	var v := PatternView.new()
	v.atom_colors = atom_colors
	v.min_size = Vector2(72, 40) if big else Vector2(48, 26)
	views.append(v)
	box.add_child(v)
	return box


## 每次 board_updated 后拉取最新纹样
func refresh(session: ProofSession) -> void:
	for i in _in_views.size():
		_in_views[i].formula = session.get_input_pattern(node_id, i)
	for i in _out_views.size():
		_out_views[i].formula = session.get_output_pattern(node_id, i)
	var info := session.describe_node(node_id)
	if info != null and not _hyp_ports.is_empty():
		for p in _hyp_ports:
			var lbl := _port_label_of(_out_views[p])
			var base := info.outputs[p].label
			lbl.text = ("📌 " + str(info.pinned[p])) if info.pinned.has(p) else base


func _port_label_of(v: PatternView) -> Label:
	return v.get_parent().get_child(0) as Label


func _on_pin_pressed() -> void:
	pin_requested.emit(_hyp_ports[0])
