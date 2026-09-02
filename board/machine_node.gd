class_name MachineNode
extends GraphNode
## 棋盘上的一个节点(仪器/线轴/目标织机)的视图。
## 只认 ProofSession 的 NodeInfo/查询函数;一行 slot = 一对(输入口, 输出口)。
## 端口只画纹样,不写任何公式文字(美术:节点内 P、Q 等公式命题全部删除)。
##
## v1.1 交互调整(v1.1交互调整说明/,示意图 image*.png):
##   §1   端口图形自画(PortLayer,节点最后一个子节点、Node2D 不算 slot):输出口 = 圆 + 朝右尖角(插头),
##        输入口 = 缺口朝左的圆(插座);接上后输入口整圆、输出口不画(插头"插进"了插座);正在从它拖线的出口也不画
##        (插头跟着鼠标走,由 WireOverlay 画)。_draw_port 覆写为空只为压掉引擎默认圆点 —— 它在脚本 _draw 之前
##        被调,画在那里会被节点自画的外形盖住。
##   §4.1 行距 ROW_GAP;§4.2 纹样边框按仪器模板的元变量着色(META_COLORS,注入 PatternView.region_borders);
##   §4.3 汇路机三行之间画两色分割线;
##   §4.4 封程机凹形:第一排 假设 P(左臂)+ 输入 Q(右臂)、中间留缺口,第二排 输出 P>Q,标题在底部。
##        GraphNode 只会把口放在节点左右边缘(左右缩进对称、不能逐口设),所以两个口的位置由 port_pos() 给出、
##        ProofBoard 用三个虚函数(热区 / 连线端点 / 曲线)接管;引擎按 slot 顺序给右口编号,假设口在第一排 →
##        图口号 ≠ 模型口号,graph_out_port / model_out_port 换算。外形(U 形 + 底部标题带 + 描边)自画,
##        引擎的 panel/titlebar 样式覆盖成空。
##   §4.5 「钉纹样」按钮带底色、放在可钉纹样旁(默认在下方,岔纹机在左侧);未钉的可钉口纹样外围画一圈静态虚线
##        (蚂蚁线;低功耗模式不做无限动画),钉住后不画,不再有「已钉」小字。
## 尺寸为 3840×2160 逻辑像素;配色随 theme(乳黄底、棕红描边);美术调这里的常量。

signal pin_requested(out_port: int)
signal delete_requested

const PORT_COLOR := Color(0.54, 0.35, 0.27)     # 棕
const HYP_COLOR := Color(0.77, 0.42, 0.42)      # 假设口强调:红棕(搭载假设的线整条也是这色:theme GraphEdit/colors/activity)
const GOAL_COLOR := Color(0.788, 0.635, 0.306)  # 目标:黄铜
const BIG_VIEW := Vector2(192, 108)             # 线轴/目标的单口大纹样
const PORT_VIEW := Vector2(128, 72)             # 仪器口纹样
const PIN_FONT_SIZE := 40
const ROW_GAP := 32                             # 行距(§4.1:image 4 间距 ≈ 纹样高 × 0.45)
const CELL_GAP := 24                            # 行内水平间距 / 中央 spacer 最小宽
const PANEL_MARGIN := Vector4(16, 12, 16, 16)   # 左/上/右/下内边距(与 theme node_panel 同;凹形节点自画时也用)
# §1 端口图形
const PORT_R := 14.0                            # 圆半径
const PORT_TIP := 12.0                          # 插头尖角伸出圆外的长度
const PORT_NOTCH_DEG := 70.0                    # 插座缺口张角
# §4.2 纹样边框:按仪器模板的元变量着色(策划给 C9A24E / 775241,青色从 image 8 采样)
const META_COLORS: Dictionary = {&"P": Color("C9A24E"), &"Q": Color("775241"), &"R": Color("7B9B8B")}
const META_COLOR_OVERRIDES: Dictionary = {&"or_intro": {&"Q": Color("C2CAB9"), &"R": Color("A8B9BE")}}   # 岔纹机两口各自的钉色(image 11)
# §4.5 钉纹样按钮:底色默认乳黄(image 9/12),岔纹机两口用各自钉色(image 11);位置默认纹样下方,岔纹机在纹样左侧
const PIN_BG := Color("F0E4C8")
const PIN_BG_BY_PORT: Dictionary = {&"or_intro": {0: Color("C2CAB9"), 1: Color("A8B9BE")}}
const PIN_BUTTON_SIDE: Dictionary = {&"or_intro": &"left"}
# 蚂蚁线:未钉的可钉口纹样外扩一圈静态虚线(image 9/11/12 采样为乳黄)
const ANT_COLOR := Color("F0E4C8")
const ANT_INSET := 10.0
const ANT_W := 2.0
const ANT_DASH := 10.0
# §4.3 汇路机分割线(策划给的两色:金线在上、乳黄线紧贴其下)
const DIVIDER_GOLD := Color("C9A34F")
const DIVIDER_CREAM := Color("F2E7CE")
const DIVIDER_W := 2.0
# §4.4 封程机凹形
const IMP_NOTCH_W := 96.0                       # 两臂之间缺口的最小宽
const NODE_BG := Color(1, 0.98, 0.94)           # 与 theme node_panel 同
const NODE_TITLE_BG := Color(0.941, 0.894, 0.784)
const NODE_BORDER := Color(0.42, 0.23, 0.2)
const NODE_BORDER_SELECTED := Color(0.788, 0.635, 0.306)
const NODE_BORDER_W := 6.0
const NODE_RADIUS := 16.0

var node_id: int = -1
var node_type: int = ProofSession.NodeType.MACHINE
var rule_id: StringName = &""
var atom_colors: Dictionary = {}

var _in_views: Array[PatternView] = []
var _out_views: Array[PatternView] = []      # 按模型输出口下标
var _pin_ports: Array[int] = []              # 可钉的输出口(模型口号)
var _pin_buttons: Dictionary = {}            # 模型输出口 -> 「钉纹样」Button
var _pinned: Dictionary = {}                 # 模型输出口 -> true(已钉)
var _wired_in: Dictionary = {}               # 输入口 -> true(有线)
var _wired_out: Dictionary = {}              # 模型输出口 -> true(有线;钉住不算)
var _out_is_hyp: Dictionary = {}             # 模型输出口 -> 是假设口
var _graph_of_model: Array[int] = []         # 模型输出口 -> GraphEdit 右口号
var _model_of_graph: Array[int] = []         # GraphEdit 右口号 -> 模型输出口
var _rows: Array[Control] = []               # 各 slot 行(分割线 / 缺口几何)
var _drag_port := Vector2i(-1, -1)           # (0 左 / 1 右, 图口号):正在从它拖线
var _concave := false                        # 封程机 U 形
var _arm_l: Control                          # 凹形左臂(假设 P + 钉按钮)
var _arm_r: Control                          # 凹形右臂(输入 Q)
var _title_row: Label                        # 凹形底部标题
var _port_layer: PortLayer


## 端口图层:画在所有子控件之上(节点最后一个子节点;Node2D 不参与 GraphNode 的 slot 排版)
class PortLayer extends Node2D:
	var owner_node: MachineNode

	func _draw() -> void:
		if owner_node != null:
			owner_node.draw_ports(self)


func _init() -> void:
	node_selected.connect(queue_redraw)     # 凹形节点的描边随选中变色
	node_deselected.connect(queue_redraw)


func build_from(info: ProofSession.NodeInfo) -> void:
	node_id = info.id
	node_type = info.type
	rule_id = info.rule_id
	name = "n%d" % info.id
	_in_views.clear()
	_out_views.clear()
	_pin_ports.clear()
	_pin_buttons.clear()
	_rows.clear()
	_graph_of_model.clear()
	_model_of_graph.clear()
	_out_is_hyp.clear()
	add_theme_constant_override("separation", ROW_GAP)
	for p in info.outputs.size():
		_out_is_hyp[p] = info.outputs[p].is_hypothesis
		if info.outputs[p].pinnable:
			_pin_ports.append(p)
	_concave = info.rule_id == &"imp_intro"
	if _concave:
		_build_concave(info)
	else:
		title = info.title
		_build_rows(info)
	_port_layer = PortLayer.new()
	_port_layer.owner_node = self
	add_child(_port_layer)


## 普通节点:一行 = [输入纹样 | spacer | (钉按钮) | 输出纹样];可钉口按钮默认另起一行放在输出纹样下方(image 12)
func _build_rows(info: ProofSession.NodeInfo) -> void:
	var big := info.type != ProofSession.NodeType.MACHINE   # 线轴/目标:单口大纹样
	var is_goal := info.type == ProofSession.NodeType.GOAL
	var side: StringName = PIN_BUTTON_SIDE.get(info.rule_id, &"below")
	for p in info.outputs.size():
		_graph_of_model.append(p)
		_model_of_graph.append(p)
	var rows := maxi(info.inputs.size(), info.outputs.size())
	for row in rows:
		var h := _row()
		if row < info.inputs.size():
			_in_views.append(_add_cell(h, big, _borders_for(info, info.inputs[row].label)))
		h.add_child(_spacer())
		if row < info.outputs.size():
			if side == &"left" and _pin_ports.has(row):
				h.add_child(_make_pin_button(row))
			_out_views.append(_add_cell(h, big, _borders_for(info, info.outputs[row].label)))
		add_child(h)
		_rows.append(h)
		set_slot(row,
				row < info.inputs.size(), 0, GOAL_COLOR if is_goal else PORT_COLOR,
				row < info.outputs.size(), 0, HYP_COLOR if _out_is_hyp.get(row, false) else PORT_COLOR)
	if side == &"below" and not _pin_ports.is_empty():
		var h := _row()   # 无口的一行:按钮右对齐在输出纹样下方
		h.add_child(_spacer())
		for p in _pin_ports:
			h.add_child(_make_pin_button(p))
		add_child(h)


## 封程机凹形(image 9):第一排 左臂[假设 P 纹样 + 钉按钮] | 缺口 | 右臂[输入 Q];第二排 输出 P>Q 靠右;底部标题
func _build_concave(info: ProofSession.NodeInfo) -> void:
	title = ""
	var engine_title := get_titlebar_hbox().get_child(0) as Label
	if engine_title != null:
		engine_title.add_theme_font_size_override("font_size", 1)   # 顶部标题栏压到几乎零高:外形与标题都自画
	var panel := StyleBoxEmpty.new()
	panel.content_margin_left = PANEL_MARGIN.x
	panel.content_margin_top = PANEL_MARGIN.y
	panel.content_margin_right = PANEL_MARGIN.z
	panel.content_margin_bottom = PANEL_MARGIN.w
	add_theme_stylebox_override("panel", panel)
	add_theme_stylebox_override("panel_selected", panel)
	var bar := StyleBoxEmpty.new()
	add_theme_stylebox_override("titlebar", bar)
	add_theme_stylebox_override("titlebar_selected", bar)
	_graph_of_model = [1, 0]   # 模型 0 = P>Q 在第二排(图口 1);模型 1 = 假设 P 在第一排(图口 0)
	_model_of_graph = [1, 0]
	var out_view := _make_view(false, _borders_for(info, info.outputs[0].label))
	var hyp_view := _make_view(false, _borders_for(info, info.outputs[1].label))
	_out_views = [out_view, hyp_view]
	var in_view := _make_view(false, _borders_for(info, info.inputs[0].label))
	_in_views = [in_view]
	var row0 := _row()
	_arm_l = _cell(hyp_view)
	_arm_l.add_child(_make_pin_button(1))
	_arm_l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row0.add_child(_arm_l)
	var notch := _spacer()
	notch.custom_minimum_size.x = IMP_NOTCH_W
	row0.add_child(notch)
	_arm_r = _cell(in_view)
	_arm_r.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row0.add_child(_arm_r)
	add_child(row0)
	_rows.append(row0)
	set_slot(0, true, 0, PORT_COLOR, true, 0, HYP_COLOR)
	var row1 := _row()
	row1.add_child(_spacer())
	row1.add_child(_cell(out_view))
	add_child(row1)
	_rows.append(row1)
	set_slot(1, false, 0, PORT_COLOR, true, 0, PORT_COLOR)
	_title_row = Label.new()
	_title_row.text = info.title
	_title_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_row.add_theme_font_size_override("font_size", get_theme_font_size("font_size", "GraphNodeTitleLabel"))
	_title_row.add_theme_color_override("font_color", get_theme_color("font_color", "GraphNodeTitleLabel"))
	_title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_row)


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


# ---- 子控件 ----

func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", CELL_GAP)
	return h


func _spacer() -> Control:
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.custom_minimum_size.x = CELL_GAP
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 节点中央这条带也要能右键删/左键拖
	return sp


func _make_view(big: bool, borders: Array[Dictionary]) -> PatternView:
	var v := PatternView.new()
	v.atom_colors = atom_colors
	v.min_size = BIG_VIEW if big else PORT_VIEW
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 纹样不吃鼠标:右键删除/拖动节点都要穿透到 GraphNode
	v.region_borders = borders
	return v


## 纹样格:竖排容器(纹样 [+ 钉按钮]),行内垂直居中,纹样保持原尺寸不被拉伸(口在纹样中心)
func _cell(v: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(v)
	return box


func _add_cell(h: Control, big: bool, borders: Array[Dictionary]) -> PatternView:
	var v := _make_view(big, borders)
	h.add_child(_cell(v))
	return v


func _make_pin_button(model_port: int) -> Button:
	var btn := Button.new()
	btn.text = "钉纹样"
	btn.add_theme_font_size_override("font_size", PIN_FONT_SIZE)
	btn.tooltip_text = "给本口的自由纹样赋值(求解只看输入和钉住的纹样,不从下游反推)"
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.mouse_filter = Control.MOUSE_FILTER_PASS   # 左键归按钮;右键穿透到节点(右键删机在按钮上也生效)
	var by_port: Dictionary = PIN_BG_BY_PORT.get(rule_id, {})
	UiStyles.fill_button(btn, by_port.get(model_port, PIN_BG))
	btn.pressed.connect(pin_requested.emit.bind(model_port))
	_pin_buttons[model_port] = btn
	return btn


## 仪器口的区域边框:按模板结构走到每个叶子,元变量按颜色表、其它叶(溃散机的 ⊥)用深色;线轴/目标不加(空 = 深色外框)
func _borders_for(info: ProofSession.NodeInfo, template_text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if info.type != ProofSession.NodeType.MACHINE:
		return out
	_collect_borders(FormulaParser.parse(template_text), [] as Array[int], out)
	return out


func _collect_borders(f: Formula, path: Array[int], out: Array[Dictionary]) -> void:
	if f == null:
		return
	if f.is_binary():
		var l: Array[int] = []
		l.append_array(path)
		l.append(0)
		_collect_borders(f.left, l, out)
		var r: Array[int] = []
		r.append_array(path)
		r.append(1)
		_collect_borders(f.right, r, out)
		return
	var color := PatternView.SPLIT_COLOR
	if f.kind == Formula.Kind.META:
		color = meta_color(f.name)
	out.append({path = path, color = color})


func meta_color(n: StringName) -> Color:
	var over: Dictionary = META_COLOR_OVERRIDES.get(rule_id, {})
	return over.get(n, META_COLORS.get(n, PatternView.SPLIT_COLOR))


# ---- 端口 ----

## 图口号 ↔ 模型口号(只有封程机不同)
func graph_out_port(model_port: int) -> int:
	return _graph_of_model[model_port] if model_port < _graph_of_model.size() else model_port


func model_out_port(graph_port: int) -> int:
	return _model_of_graph[graph_port] if graph_port < _model_of_graph.size() else graph_port


func is_hyp_out(model_port: int) -> bool:
	return _out_is_hyp.get(model_port, false)


func has_custom_ports() -> bool:
	return _concave


## 端口在节点内的位置(GraphEdit 图口号;节点局部坐标、不含缩放)。默认 = 引擎算法(左/右边缘、slot 行中心);
## 封程机的输入 Q 在右臂左沿、假设 P 在左臂右沿(§4.4),y 都取各自纹样的中心。
func port_pos(left: bool, graph_idx: int) -> Vector2:
	if _concave and graph_idx == 0 and _arm_l != null and _arm_r != null:
		if left:
			return Vector2(_local_rect_of(_arm_r).position.x, _local_rect_of(_in_views[0]).get_center().y)
		return Vector2(_local_rect_of(_arm_l).end.x, _local_rect_of(_out_views[1]).get_center().y)
	return stock_port_pos(left, graph_idx)


## 引擎自己算的口位(热区/连线端点都从它出发,ProofBoard 据此把封程机的口重映射到 port_pos)
func stock_port_pos(left: bool, graph_idx: int) -> Vector2:
	return get_input_port_position(graph_idx) if left else get_output_port_position(graph_idx)


## 位置被挪动的口:[{left, idx, stock, custom}]
func custom_ports() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _concave:
		out.append({left = true, idx = 0, stock = stock_port_pos(true, 0), custom = port_pos(true, 0)})
		out.append({left = false, idx = 0, stock = stock_port_pos(false, 0), custom = port_pos(false, 0)})
	return out


func set_drag_port(left: bool, graph_idx: int) -> void:
	_drag_port = Vector2i(0 if left else 1, graph_idx)
	if _port_layer != null:
		_port_layer.queue_redraw()


func clear_drag_port() -> void:
	if _drag_port.x < 0:
		return
	_drag_port = Vector2i(-1, -1)
	if _port_layer != null:
		_port_layer.queue_redraw()


func is_input_wired(port: int) -> bool:
	return _wired_in.has(port)


func is_output_wired(model_port: int) -> bool:
	return _wired_out.has(model_port)


## 引擎默认端口图标不画(端口在 PortLayer 画,见文件头)
func _draw_port(_slot_index: int, _pos: Vector2i, _left: bool, _color: Color) -> void:
	pass


func draw_ports(ci: CanvasItem) -> void:
	var in_color := GOAL_COLOR if node_type == ProofSession.NodeType.GOAL else PORT_COLOR
	for i in _in_views.size():
		var pos := port_pos(true, i)
		if _wired_in.has(i):
			ci.draw_circle(pos, PORT_R, in_color)   # 接上:插头与插座合成整圆
		else:
			draw_socket(ci, pos, in_color)
	for g in _out_views.size():
		var m := model_out_port(g)
		if _wired_out.has(m) or _drag_port == Vector2i(1, g):
			continue   # 插头已插进下游 / 正跟着鼠标
		draw_plug(ci, port_pos(false, g), HYP_COLOR if _out_is_hyp.get(m, false) else PORT_COLOR)


## 插头:圆 + 朝右尖角(输出口;拖线时 WireOverlay 在鼠标处画同样的)
static func draw_plug(ci: CanvasItem, pos: Vector2, color: Color, s: float = 1.0) -> void:
	ci.draw_circle(pos, PORT_R * s, color)
	ci.draw_colored_polygon(PackedVector2Array([
		pos + Vector2(PORT_R * 0.45, -PORT_R * 0.85) * s,
		pos + Vector2(PORT_R + PORT_TIP, 0) * s,
		pos + Vector2(PORT_R * 0.45, PORT_R * 0.85) * s]), color)


## 插座:缺口朝左的圆(输入口)
static func draw_socket(ci: CanvasItem, pos: Vector2, color: Color, s: float = 1.0) -> void:
	var half := deg_to_rad(PORT_NOTCH_DEG * 0.5)
	var a0 := PI + half
	var a1 := 3.0 * PI - half
	var pts := PackedVector2Array([pos])
	var n := 24
	for k in n + 1:
		var a := a0 + (a1 - a0) * k / n
		pts.append(pos + Vector2(cos(a), sin(a)) * PORT_R * s)
	ci.draw_colored_polygon(pts, color)


# ---- 刷新 ----

## 每次 board_updated 后拉取最新纹样与接线/钉住状态。
## 仪器上没线(也没钉)的口画幽灵:值只是合一推导的期望,不是已流入的事实;线轴/目标永远实显。
func refresh(session: ProofSession) -> void:
	var is_machine := node_type == ProofSession.NodeType.MACHINE
	for i in _in_views.size():
		_in_views[i].formula = session.get_input_pattern(node_id, i)
		_in_views[i].ghost = is_machine and not session.is_input_connected(node_id, i)
	for i in _out_views.size():
		_out_views[i].formula = session.get_output_pattern(node_id, i)
		_out_views[i].ghost = is_machine and not session.is_output_connected(node_id, i)
	_wired_in.clear()
	_wired_out.clear()
	for w in session.get_wires():
		if w.from_id == node_id:
			_wired_out[w.from_port] = true
		if w.to_id == node_id:
			_wired_in[w.to_port] = true
	_pinned.clear()
	var info := session.describe_node(node_id)
	if info != null:
		for p in info.pinned:
			_pinned[p] = true
	queue_redraw()
	if _port_layer != null:
		_port_layer.queue_redraw()


## 未钉的可钉口画蚂蚁线(钉住后不画)
func is_ant_frame_shown(out_port: int) -> bool:
	return _pin_ports.has(out_port) and not _pinned.has(out_port)


# ---- 自画:凹形外形 / 汇路机分割线 / 蚂蚁线 ----

func _draw() -> void:
	if _concave:
		_draw_concave_shape()
	elif rule_id == &"or_elim":
		_draw_dividers()
	for p in _pin_ports:
		if not _pinned.has(p) and p < _out_views.size():
			_draw_ant_frame(_local_rect_of(_out_views[p]).grow(ANT_INSET))


func _draw_dividers() -> void:
	for i in _rows.size() - 1:
		var y := (_local_rect_of(_rows[i]).end.y + _local_rect_of(_rows[i + 1]).position.y) * 0.5
		var x0 := PANEL_MARGIN.x
		var x1 := size.x - PANEL_MARGIN.z
		draw_line(Vector2(x0, y - DIVIDER_W * 0.5), Vector2(x1, y - DIVIDER_W * 0.5), DIVIDER_GOLD, DIVIDER_W)
		draw_line(Vector2(x0, y + DIVIDER_W * 0.5), Vector2(x1, y + DIVIDER_W * 0.5), DIVIDER_CREAM, DIVIDER_W)


func _draw_ant_frame(r: Rect2) -> void:
	var tl := r.position
	var tr := Vector2(r.end.x, r.position.y)
	var bl := Vector2(r.position.x, r.end.y)
	var br := r.end
	draw_dashed_line(tl, tr, ANT_COLOR, ANT_W, ANT_DASH)
	draw_dashed_line(tr, br, ANT_COLOR, ANT_W, ANT_DASH)
	draw_dashed_line(br, bl, ANT_COLOR, ANT_W, ANT_DASH)
	draw_dashed_line(bl, tl, ANT_COLOR, ANT_W, ANT_DASH)


## U 形:四个外角圆角、缺口直角;缺口从顶到第一排下方半个行距;底部标题带;描边随选中变色
func _draw_concave_shape() -> void:
	if _rows.is_empty() or _title_row == null:
		return
	var w := size.x
	var h := size.y
	var nx0 := _local_rect_of(_arm_l).end.x
	var nx1 := _local_rect_of(_arm_r).position.x
	var ny := _local_rect_of(_rows[0]).end.y + ROW_GAP * 0.5
	var pts := PackedVector2Array()
	pts.append_array(_arc(Vector2(NODE_RADIUS, NODE_RADIUS), PI, 1.5 * PI))
	pts.append(Vector2(nx0, 0))
	pts.append(Vector2(nx0, ny))
	pts.append(Vector2(nx1, ny))
	pts.append(Vector2(nx1, 0))
	pts.append_array(_arc(Vector2(w - NODE_RADIUS, NODE_RADIUS), 1.5 * PI, 2.0 * PI))
	pts.append_array(_arc(Vector2(w - NODE_RADIUS, h - NODE_RADIUS), 0.0, 0.5 * PI))
	pts.append_array(_arc(Vector2(NODE_RADIUS, h - NODE_RADIUS), 0.5 * PI, PI))
	draw_colored_polygon(pts, NODE_BG)
	var ty := _local_rect_of(_title_row).position.y - ROW_GAP * 0.5
	var band := PackedVector2Array([Vector2(0, ty), Vector2(w, ty)])
	band.append_array(_arc(Vector2(w - NODE_RADIUS, h - NODE_RADIUS), 0.0, 0.5 * PI))
	band.append_array(_arc(Vector2(NODE_RADIUS, h - NODE_RADIUS), 0.5 * PI, PI))
	draw_colored_polygon(band, NODE_TITLE_BG)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, NODE_BORDER_SELECTED if selected else NODE_BORDER, NODE_BORDER_W)


static func _arc(center: Vector2, a0: float, a1: float, segments: int = 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in segments + 1:
		var a := a0 + (a1 - a0) * k / segments
		out.append(center + Vector2(cos(a), sin(a)) * NODE_RADIUS)
	return out


## 子控件在节点局部坐标里的矩形(容器坐标逐级相加;不含缩放)
func _local_rect_of(c: Control) -> Rect2:
	var pos := Vector2.ZERO
	var n: Node = c
	while n != null and n != self:
		pos += (n as Control).position
		n = n.get_parent()
	return Rect2(pos, c.size)
