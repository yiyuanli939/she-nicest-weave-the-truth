class_name ProofBoard
extends GraphEdit
## 织机工作台:ProofSession 的投影。全项目 GraphEdit API 只出现在本文件与 machine_node.gd。
##
## 约定(与 ProofSession 文档一致):
##   * 玩家操作 → 一律转发 session 裁决,自己绝不直接 connect_node 落地;
##   * board_rebuilt → 全量重建节点;board_updated → clear_connections + 全量重挂;
##   * 正常放置由发起方(place 函数)用返回的 id 自己建节点。

signal pin_requested(node_id: int, out_port: int)

var session: ProofSession
var atom_colors: Dictionary = {}

var _overlay: WireOverlay


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
		connect_node("n%d" % w.from_id, w.from_port, "n%d" % w.to_id, w.to_port)
	for mn in _machine_nodes():
		mn.refresh(session)
	_overlay.rebuild()


# ---- view → session ----

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	session.connect_wire(_id_of(from_node), from_port, _id_of(to_node), to_port)


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	session.disconnect_wire(_id_of(from_node), from_port, _id_of(to_node), to_port)


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


static func _id_of(node_name: StringName) -> int:
	return int(String(node_name).substr(1))
