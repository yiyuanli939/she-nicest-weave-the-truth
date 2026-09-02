class_name ProofBoard
extends GraphEdit
## 织机工作台:ProofSession 的投影。全项目 GraphEdit API 只出现在本文件与 machine_node.gd。
##
## 约定(与 ProofSession 文档一致):
##   * 玩家操作 → 一律转发 session 裁决,自己绝不直接 connect_node 落地;
##   * board_rebuilt → 全量重建节点;board_updated → clear_connections + 全量重挂;
##   * 正常放置由发起方(place 函数)用返回的 id 自己建节点。
##
## v1.1 交互调整:
##   * 图口号 ↔ 模型口号经 MachineNode.graph_out_port / model_out_port 换算(只有封程机不同:假设口排第一排);
##     脚本/测试直接连线请走 session.connect_wire(模型口号),别再借用 _on_connection_request(图口号)。
##   * 三个虚函数(端口热区 / 连线端点重映射 / 曲线)被接管,只为封程机把两个口挪到臂内沿(MachineNode.port_pos);
##     其它口走与引擎相同的算法(热区矩形按主题 inner/outer extent,曲线按 connection_lines_curvature 的贝塞尔)。
##   * 搭载未消去假设的线(WireInfo.carries_hyp)用 set_connection_activity 整条染成主题 GraphEdit/colors/activity(假设色)。
##   * 接错的线(冲突/成环/逃逸,WireOverlay.AUTO_BREAK)BAD_WIRE_SEC 后自动断开:定时器回调再查一次状态,
##     示答/代解一帧内连完、终态 OK 的线不会被断;徽章由 WireOverlay 冻结原位淡出。
##   * 拖线时通知源节点藏起插头、叠加层在鼠标处画插头(connection_drag_started/ended)。

signal pin_requested(node_id: int, out_port: int)

const BAD_WIRE_SEC := 0.5      # 接错的线多久后自动断开
const PORT_HOT_H := 40.0       # 端口热区高度(引擎默认 = 端口图标高;自画端口后在这里定)

var session: ProofSession
var atom_colors: Dictionary = {}

var _overlay: WireOverlay
var _pending_breaks: Dictionary = {}   # 边 Vector4i -> true:已排队等待断开


func _init() -> void:
	_overlay = WireOverlay.new()
	_overlay.board = self


func _ready() -> void:
	right_disconnects = true
	# 引擎默认工具条控件与美术风格冲突(灰 SpinBox/淡图标):只留缩放按钮;
	# minimap 被撑画布的角标稀释得没有信息量,关掉(画布固定大小 + 中键平移,不迷路)
	minimap_enabled = false
	show_arrange_button = false
	show_grid_buttons = false
	show_zoom_label = false
	show_minimap_button = false
	connection_lines_thickness = 8.0
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	delete_nodes_request.connect(_on_delete_nodes_request)
	end_node_move.connect(_on_end_node_move)
	connection_drag_started.connect(_on_drag_started)
	connection_drag_ended.connect(_on_drag_ended)
	add_child(_overlay)
	# 视区移动只留中键拖动(4.7 ViewPanner 内置):滚动条隐形且不吃鼠标。
	# 引擎每次 _update_scroll 会自己 show()/hide(),改 visible 会被顶回,所以用 modulate;
	# 不能 free —— scroll_offset 的值就存在这两条 ScrollBar 里。
	for sb in scroll_bars():
		sb.modulate.a = 0.0
		sb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 两个隐形角标把可平移画布撑到固定大小(GraphEdit 滚动范围 = 内容 AABB ± 一屏,无 API 可调)。
	# 非 MachineNode:_machine_nodes()/_on_board_rebuilt 都不会碰它们,模型层不感知。
	for corner in [Vector2(-800, -600), Vector2(4200, 2800)]:
		var anchor := GraphElement.new()
		anchor.position_offset = corner
		anchor.modulate.a = 0.0
		anchor.selectable = false
		anchor.draggable = false
		anchor.focus_mode = Control.FOCUS_NONE
		anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(anchor)


## 关卡 HUD 没有单独一行(美术:不显示当前关),必需按钮挂在棋盘自带的工具条上(GraphEdit API 只在本文件)
func add_toolbar_item(c: Control) -> void:
	get_menu_hbox().add_child(c)


## GraphEdit 的两条内部滚动条(GDScript 没有 get_h/v_scroll_bar;它们在内部容器里,递归找)
func scroll_bars() -> Array[ScrollBar]:
	var out: Array[ScrollBar] = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(true):
			if c is ScrollBar:
				out.append(c)
			elif not (c is GraphElement):
				stack.append(c)
	return out


func bind(s: ProofSession) -> void:
	session = s
	_overlay.session = s
	s.board_rebuilt.connect(_on_board_rebuilt)
	s.board_updated.connect(_on_board_updated)


## palette 请求放一台仪器:落点取当前视野中心
func place_machine_at_center(rule_id: StringName) -> void:
	var canvas_pos := (scroll_offset + size * 0.5) / zoom - Vector2(180, 120)
	var id := session.place_machine(rule_id, canvas_pos)
	if id >= 0:
		_spawn_node(id)


func _spawn_node(id: int) -> void:
	var info := session.describe_node(id)
	var mn := MachineNode.new()
	mn.atom_colors = atom_colors
	mn.build_from(info)
	mn.position_offset = session.get_node_position(id)
	mn.pin_requested.connect(func(port: int) -> void: pin_requested.emit(id, port))
	mn.delete_requested.connect(_on_node_delete_requested.bind(id))
	add_child(mn)
	_overlay.move_to_front()   # 徽章画在节点之上
	mn.refresh(session)


## 关卡布好局后同步一次模型里的节点位置(线轴/目标的初始摆位)
func apply_positions() -> void:
	for mn in _machine_nodes():
		mn.position_offset = session.get_node_position(mn.node_id)


func _machine_nodes() -> Array[MachineNode]:
	var out: Array[MachineNode] = []
	for c in get_children():
		if c is MachineNode:
			out.append(c)
	return out


func _node_of(node_name: StringName) -> MachineNode:
	return get_node_or_null(NodePath(node_name)) as MachineNode


# ---- session → view ----

func _on_board_rebuilt() -> void:
	clear_connections()
	for mn in _machine_nodes():
		mn.name = str(mn.name) + "_dead"   # 腾出 n%d 名字给新节点(queue_free 帧末才释放)
		mn.queue_free()
	for id in session.get_node_ids():
		_spawn_node(id)


func _on_board_updated() -> void:
	clear_connections()
	for w in session.get_wires():
		var from_name := "n%d" % w.from_id
		var to_name := "n%d" % w.to_id
		var fn := _node_of(from_name)
		var gp := fn.graph_out_port(w.from_port) if fn != null else w.from_port
		connect_node(from_name, gp, to_name, w.to_port)
		set_connection_activity(from_name, gp, to_name, w.to_port, 1.0 if w.carries_hyp else 0.0)
	for mn in _machine_nodes():
		mn.refresh(session)
	_overlay.rebuild()
	_schedule_breaks()


## 接错的线排队等 BAD_WIRE_SEC 后断开(每条只排一次;回调时再核对状态)
func _schedule_breaks() -> void:
	if not is_inside_tree():
		return
	for w in session.get_wires():
		if not WireOverlay.AUTO_BREAK.has(w.state):
			continue
		var key := Vector4i(w.from_id, w.from_port, w.to_id, w.to_port)
		if _pending_breaks.has(key):
			continue
		_pending_breaks[key] = true
		get_tree().create_timer(BAD_WIRE_SEC).timeout.connect(_break_wire.bind(key))


func _break_wire(key: Vector4i) -> void:
	_pending_breaks.erase(key)
	if session == null or not is_inside_tree():
		return
	if not WireOverlay.AUTO_BREAK.has(session.get_wire_state(key.x, key.y, key.z, key.w)):
		return   # 已被玩家断开 / 后续操作让它成立了
	_overlay.detach_chip(key)
	session.disconnect_wire(key.x, key.y, key.z, key.w, false)   # 自动断开不记撤销步(见 ProofSession.disconnect_wire)


# ---- view → session ----

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var fn := _node_of(from_node)
	var tn := _node_of(to_node)
	if fn == null or tn == null:
		return
	session.connect_wire(fn.node_id, fn.model_out_port(from_port), tn.node_id, to_port)


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var fn := _node_of(from_node)
	var tn := _node_of(to_node)
	if fn == null or tn == null:
		return
	session.disconnect_wire(fn.node_id, fn.model_out_port(from_port), tn.node_id, to_port)


func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
	for nm in nodes:
		_remove_machine(_id_of(nm))


## 右键点节点体的删除入口(见 MachineNode._gui_input)
func _on_node_delete_requested(id: int) -> void:
	_remove_machine(id)


func _remove_machine(id: int) -> void:
	session.remove_machine(id)
	if session.describe_node(id) == null:   # 线轴/目标模型层拒删,视图保持不动
		var mn := get_node_or_null(NodePath("n%d" % id)) as MachineNode
		if mn != null:
			mn.name = str(mn.name) + "_dead"
			mn.queue_free()


func _on_end_node_move() -> void:
	for mn in _machine_nodes():
		session.set_node_position(mn.node_id, mn.position_offset)


## 拖线开始:源口藏起插头,叠加层在鼠标处画插头(颜色随口:假设口红棕)
func _on_drag_started(from_node: StringName, from_port: int, is_output: bool) -> void:
	var mn := _node_of(from_node)
	if mn == null:
		return
	mn.set_drag_port(not is_output, from_port)
	var color := MachineNode.PORT_COLOR
	if is_output and mn.is_hyp_out(mn.model_out_port(from_port)):
		color = MachineNode.HYP_COLOR
	_overlay.begin_plug(color)


func _on_drag_ended() -> void:
	for mn in _machine_nodes():
		mn.clear_drag_port()
	_overlay.end_plug()


# ---- 端口位置接管(封程机臂内沿的口;其它口与引擎算法一致) ----

func _is_in_input_hotzone(in_node: Object, in_port: int, mouse_position: Vector2) -> bool:
	return _in_hotzone(in_node as MachineNode, true, in_port, mouse_position)


func _is_in_output_hotzone(in_node: Object, in_port: int, mouse_position: Vector2) -> bool:
	return _in_hotzone(in_node as MachineNode, false, in_port, mouse_position)


## mouse 是 GraphEdit 局部坐标 / zoom;热区 = 口位左右各 outer/inner extent、上下各半个 PORT_HOT_H(引擎同款)
func _in_hotzone(mn: MachineNode, left: bool, idx: int, mouse: Vector2) -> bool:
	if mn == null:
		return false
	var p := mn.position / zoom + mn.port_pos(left, idx)
	var inner := float(get_theme_constant("port_hotzone_inner_extent"))
	var outer := float(get_theme_constant("port_hotzone_outer_extent"))
	var r := Rect2(p.x - (outer if left else inner), p.y - PORT_HOT_H * 0.5, inner + outer, PORT_HOT_H)
	return r.has_point(mouse)


## 引擎给的端点是 (position_offset + 引擎口位) * zoom(正式连线)或 position + 引擎口位 * zoom(拖线预览);
## 命中封程机被挪动的口就换成 port_pos,再按引擎同款贝塞尔出线
func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var a := _remap_port_point(from_position)
	var b := _remap_port_point(to_position)
	var curve := Curve2D.new()
	var cp := absf(b.x - a.x) * connection_lines_curvature
	curve.add_point(a, Vector2.ZERO, Vector2(cp, 0))
	curve.add_point(b, Vector2(-cp, 0), Vector2.ZERO)
	return curve.tessellate(5, 2.0) if connection_lines_curvature > 0.0 else curve.tessellate(1)


func _remap_port_point(pt: Vector2) -> Vector2:
	for mn in _machine_nodes():
		if not mn.has_custom_ports():
			continue
		for cp in mn.custom_ports():
			for base in [mn.position_offset * zoom, mn.position]:
				if pt.distance_squared_to(base + (cp.stock as Vector2) * zoom) < 1.0:
					return base + (cp.custom as Vector2) * zoom
	return pt


static func _id_of(node_name: StringName) -> int:
	return int(String(node_name).substr(1))
