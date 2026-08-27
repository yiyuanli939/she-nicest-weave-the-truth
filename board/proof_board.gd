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
	minimap_enabled = true
	show_arrange_button = false
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	delete_nodes_request.connect(_on_delete_nodes_request)
	end_node_move.connect(_on_end_node_move)
	add_child(_overlay)


func bind(s: ProofSession) -> void:
	session = s
	_overlay.session = s
	s.board_rebuilt.connect(_on_board_rebuilt)
	s.board_updated.connect(_on_board_updated)


## palette 请求放一台仪器:落点取当前视野中心
func place_machine_at_center(rule_id: StringName) -> void:
	var canvas_pos := (scroll_offset + size * 0.5) / zoom - Vector2(90, 60)
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
