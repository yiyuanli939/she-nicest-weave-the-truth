class_name MachineNode
extends GraphNode
## 棋盘上的一个节点(仪器/线轴/目标织机)的视图。
## 只认 ProofSession 的 NodeInfo/查询函数;一行 slot = 一对(输入口, 输出口)。
## 端口只画纹样,不写任何公式文字(美术:节点内 P、Q 等公式命题全部删除);
## 假设口(线轴口)用强调色;每个可钉口(pinnable)在 titlebar 出一个钉按钮,
## 由纹样编辑器接管(钉的是该口的自由纹样,求解不会从下游反推),钉住后口下出「已钉」小字。
## 尺寸为 3840×2160 逻辑像素;配色随 theme(乳黄底、棕红描边)。

signal pin_requested(out_port: int)
signal delete_requested

const PORT_COLOR := Color(0.54, 0.35, 0.27)   # 棕
const HYP_COLOR := Color(0.77, 0.42, 0.42)    # 假设口强调:红棕
const GOAL_COLOR := Color(0.788, 0.635, 0.306)  # 目标:黄铜
const BIG_VIEW := Vector2(192, 108)           # 线轴/目标的单口大纹样
const PORT_VIEW := Vector2(128, 72)           # 仪器口纹样
const PIN_FONT_SIZE := 40
const PINNED_MARK_FONT_SIZE := 28

var node_id: int = -1
var node_type: int = ProofSession.NodeType.MACHINE
var atom_colors: Dictionary = {}

var _in_views: Array[PatternView] = []
var _out_views: Array[PatternView] = []
var _pin_ports: Array[int] = []      # 可钉的输出口下标
var _pin_marks: Dictionary = {}      # 输出口下标 -> 「已钉」Label


func build_from(info: ProofSession.NodeInfo) -> void:
	node_id = info.id
	node_type = info.type
	name = "n%d" % info.id
	title = info.title
	_in_views.clear()
	_out_views.clear()
	_pin_ports.clear()
	_pin_marks.clear()
	var big := info.type != ProofSession.NodeType.MACHINE   # 线轴/目标:单口大纹样
	var rows := maxi(info.inputs.size(), info.outputs.size())
	for row in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 24)
		if row < info.inputs.size():
			h.add_child(_make_port_cell(_in_views, big, false))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.custom_minimum_size.x = 24
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 节点中央这条带也要能右键删/左键拖
		h.add_child(spacer)
		if row < info.outputs.size():
			var pinnable: bool = info.outputs[row].pinnable
			var cell := _make_port_cell(_out_views, big, pinnable)
			if pinnable:
				_pin_ports.append(row)
				_pin_marks[row] = cell.get_child(1)
			h.add_child(cell)
		add_child(h)
		var out_is_hyp := row < info.outputs.size() and info.outputs[row].is_hypothesis
		set_slot(row,
				row < info.inputs.size(), 0, GOAL_COLOR if info.type == ProofSession.NodeType.GOAL else PORT_COLOR,
				row < info.outputs.size(), 0, HYP_COLOR if out_is_hyp else PORT_COLOR)
	# 每个可钉口一个 titlebar 按钮:单口(封程机/溃散机)叫"钉纹样",岔纹机两口按行区分
	for p in _pin_ports:
		var btn := Button.new()
		if _pin_ports.size() == 1:
			btn.text = "钉纹样"
		else:
			btn.text = "钉上口" if p == _pin_ports[0] else "钉下口"
		btn.add_theme_font_size_override("font_size", PIN_FONT_SIZE)
		btn.tooltip_text = "给本口的自由纹样赋值(求解只看输入和钉住的纹样,不从下游反推)"
		btn.pressed.connect(pin_requested.emit.bind(p))
		get_titlebar_hbox().add_child(btn)


## 右键点节点体 = 请求删除本机(线轴/目标由模型层拒绝)。
## 左键还按着(正在拖节点)时的右键不算:触控板误触不该把手里的节点删了。
## 拖线中的右键到不了这里(GraphEdit 的连线层持有鼠标焦点,自己取消拖线)。
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	if mb.button_mask & MOUSE_BUTTON_MASK_LEFT:
		return
	accept_event()
	delete_requested.emit()


## 端口单元 = 纹样(+ 可钉口的「已钉」小字,钉住才显示);不写公式文字
func _make_port_cell(views: Array[PatternView], big: bool, with_pin_mark: bool) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := PatternView.new()
	v.atom_colors = atom_colors
	v.min_size = BIG_VIEW if big else PORT_VIEW
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 纹样不吃鼠标:右键删除/拖动节点都要穿透到 GraphNode
	views.append(v)
	box.add_child(v)
	if with_pin_mark:
		var mark := Label.new()
		mark.text = "已钉"
		mark.add_theme_font_size_override("font_size", PINNED_MARK_FONT_SIZE)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.visible = false
		box.add_child(mark)
	return box


## 每次 board_updated 后拉取最新纹样。
## 仪器上没线(也没钉)的口画幽灵:值只是合一推导的期望,不是已流入的事实;
## 线轴/目标永远实显(给定事实/要织的样张)。
func refresh(session: ProofSession) -> void:
	var is_machine := node_type == ProofSession.NodeType.MACHINE
	for i in _in_views.size():
		_in_views[i].formula = session.get_input_pattern(node_id, i)
		_in_views[i].ghost = is_machine and not session.is_input_connected(node_id, i)
	for i in _out_views.size():
		_out_views[i].formula = session.get_output_pattern(node_id, i)
		_out_views[i].ghost = is_machine and not session.is_output_connected(node_id, i)
	if _pin_ports.is_empty():
		return
	var info := session.describe_node(node_id)
	if info == null:
		return
	for p in _pin_ports:
		(_pin_marks[p] as Label).visible = info.pinned.has(p)


func is_pinned_mark_shown(out_port: int) -> bool:
	return _pin_marks.has(out_port) and (_pin_marks[out_port] as Label).visible
