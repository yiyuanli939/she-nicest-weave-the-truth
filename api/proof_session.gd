class_name ProofSession
extends Node
## 证明棋盘的门面 —— 做游戏 UI 只需要认识它(和 PatternView)。
##
## 用法:把 ProofSession 节点放进关卡场景(设 % 唯一名),`setup()` 建关,
## 之后每个编辑函数都会自动重新求解并发信号;UI 收到信号后用查询函数拉取
## 最新状态刷新画面。合一、元变量、辖域这些内部概念完全不用懂,
## ProofGraph / SolveResult 等内部类型也不会漏出来。
## 唯一放行的引擎类型是 Formula:把它当"纹样值"原样传给 PatternView 即可。
##
## 三条使用约定(教程第 1、4、6 章会各讲一遍):
##   * 模型先行:任何操作先调这里,画面只是投影,自己不存逻辑状态;
##   * 收到 board_rebuilt 就全量重建节点,收到 board_updated 就全量重挂连线;
##   * 正常放置由发起方用返回的 id 自己建节点(不用等信号)。

const WireState = SolveResult.EdgeStatus   ## OK/CONFLICT/UNDERSPEC/CYCLE/ESCAPED_HYP

enum NodeType { ASSUMPTION, GOAL, MACHINE }   # 与内部 NodeKind 数值一致

## 任一编辑落地并重新求解后(每次编辑必发,含 setup/undo/load)
signal board_updated
## 节点集合整体变化(setup/reset/undo/redo/load_state):UI 应清空全部节点,
## 按 get_node_ids() + describe_node() 重建;之后必跟一次 board_updated
signal board_rebuilt
## solved 从 false 变 true 的那一刻(只在边沿发一次,胜利动画挂这里)
signal proof_completed


# ---- UI 建节点用的结构化元数据(有类型 → 编辑器能自动补全) ----

class PortInfo:
	var label: String            ## 展示文本:仪器口=模板(如 "P & Q"),线轴/目标=实际命题
	var is_hypothesis: bool = false
	var scope_input: int = -1    ## 假设口对应的封存输入口下标;非假设口为 -1
	var pinnable: bool = false   ## 玩家可给本口的自由元变量钉纹样(UI 据此出钉按钮)

class MachineInfo:
	var rule_id: StringName
	var cn_name: String
	var inputs: Array[PortInfo] = []
	var outputs: Array[PortInfo] = []

class NodeInfo:
	var id: int
	var type: int                ## NodeType
	var title: String            ## 仪器=中文机名;线轴="线轴";目标="目标织机"
	var rule_id: StringName      ## 仅 MACHINE 有
	var inputs: Array[PortInfo] = []
	var outputs: Array[PortInfo] = []
	var pinned: Dictionary = {}  ## {可钉口下标: 公式文本} 当前钉住的纹样

class WireInfo:
	var from_id: int
	var from_port: int
	var to_id: int
	var to_port: int
	var state: int               ## WireState


var _graph := ProofGraph.new()
var _positions: Dictionary = {}          # 节点 id -> Vector2(纯视图元数据)
var _last_result := SolveResult.new()
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _initial_state: Dictionary = {}      # setup 刚完成的快照,reset 用
var _was_solved := false


# ---- 建关 ----

## 初始化关卡:清空棋盘,为每条假设建线轴、为目标建织机。
## 返回 "" 表示成功;否则返回第一条公式的解析错误(直接可显示给玩家/策划)。
func setup(assumptions: Array[String], goal_text: String) -> String:
	var parsed: Array[Formula] = []
	for text in assumptions:
		var a := FormulaParser.parse(text)
		if a == null:
			return "假设「%s」解析失败: %s" % [text, FormulaParser.last_error]
		parsed.append(a)
	var goal := FormulaParser.parse(goal_text)
	if goal == null:
		return "目标「%s」解析失败: %s" % [goal_text, FormulaParser.last_error]
	_graph = ProofGraph.new()
	_positions = {}
	_undo_stack.clear()
	_redo_stack.clear()
	_was_solved = false
	for a in parsed:
		_graph.add_assumption_node(a)
	_graph.add_goal_node(goal)
	_initial_state = save_state()
	_notify(true)
	return ""


## setup 建出的线轴节点 id(顺序同传入的假设列表)
var assumption_ids: Array[int]:
	get:
		var out: Array[int] = []
		for id: int in _graph.nodes:
			if _kind(id) == ProofGraph.NodeKind.ASSUMPTION:
				out.append(id)
		return out

## 目标织机的节点 id;没有则 -1
var goal_id: int:
	get:
		for id: int in _graph.nodes:
			if _kind(id) == ProofGraph.NodeKind.GOAL:
				return id
		return -1


## 回到 setup 刚完成的状态(可 undo 回来)
func reset() -> void:
	if _initial_state.is_empty():
		return
	_push_undo()
	_apply_state(_initial_state)
	_notify(true)


# ---- 编辑(每个函数:改模型 → 自动求解 → 发信号) ----

## 放一台仪器,返回节点 id;未知 rule_id 返回 -1。
## at 是画布位置(纯视图元数据,存档会带上)。
func place_machine(rule_id: StringName, at: Vector2 = Vector2.ZERO) -> int:
	if Rules.get_rule(rule_id) == null:
		return -1
	_push_undo()
	var id := _graph.add_rule_node(rule_id)
	_positions[id] = at
	_notify(false)
	return id


## 只删仪器;传线轴/目标织机的 id 会被忽略(UI 不用自己分辨)
func remove_machine(node_id: int) -> void:
	if _kind(node_id) != ProofGraph.NodeKind.RULE:
		return
	_push_undo()
	_graph.remove_node(node_id)
	_positions.erase(node_id)
	_notify(false)


## 接线(from 的输出口 → to 的输入口)。目标输入口已有线时自动先断旧线
## (替换语义,正好匹配 GraphEdit"拖到已占用口"的手感)。
## false = 模型拒绝(节点/口不存在、自环),此时棋盘不变、不发信号。
func connect_wire(from_id: int, from_port: int, to_id: int, to_port: int) -> bool:
	var from: ProofGraph.ProofNode = _graph.nodes.get(from_id)
	var to: ProofGraph.ProofNode = _graph.nodes.get(to_id)
	if from == null or to == null:
		return false
	if from_port < 0 or from_port >= from.ports_out.size() \
			or to_port < 0 or to_port >= to.ports_in.size():
		return false
	if from_id == to_id and not _is_hyp_out(from, from_port):
		return false
	_push_undo()
	for e in _graph.edges.duplicate():
		if e.z == to_id and e.w == to_port:
			_graph.remove_edge(e)
	_graph.add_edge(Vector4i(from_id, from_port, to_id, to_port))
	_notify(false)
	return true


func disconnect_wire(from_id: int, from_port: int, to_id: int, to_port: int) -> void:
	var e := Vector4i(from_id, from_port, to_id, to_port)
	if not _graph.edges.has(e):
		return
	_push_undo()
	_graph.remove_edge(e)
	_notify(false)


## 给可钉口的自由元变量钉住玩家给的纹样(封程机假设口 / 溃散机出口 = 整口;
## 岔纹机出口 = 析取式的另一支)。返回 "" 成功,否则可直接显示的错误文案。
func pin_hypothesis(node_id: int, out_port: int, formula_text: String) -> String:
	if _kind(node_id) != ProofGraph.NodeKind.RULE:
		return "该节点不是仪器"
	var schema := Rules.get_rule((_graph.nodes[node_id] as ProofGraph.ProofNode).rule_id)
	if out_port < 0 or out_port >= schema.outputs.size() \
			or not schema.outputs[out_port].pinnable:
		return "该口不可钉纹样"
	var f := FormulaParser.parse(formula_text)
	if f == null:
		return "解析失败: " + FormulaParser.last_error
	if not f.is_ground():
		return "纹样还有未染纱(不能包含 ? 元变量)"
	_push_undo()
	_graph.pin_hypothesis(node_id, out_port, f)
	_notify(false)
	return ""


func unpin_hypothesis(node_id: int, out_port: int) -> void:
	if _kind(node_id) != ProofGraph.NodeKind.RULE:
		return
	if not (_graph.nodes[node_id] as ProofGraph.ProofNode).pinned.has(out_port):
		return
	_push_undo()
	_graph.unpin_hypothesis(node_id, out_port)
	_notify(false)


## 记录节点画布位置。纯视图元数据:不触发求解、不发信号(拖动别卡顿)。
func set_node_position(node_id: int, pos: Vector2) -> void:
	if _graph.nodes.has(node_id):
		_positions[node_id] = pos


func get_node_position(node_id: int) -> Vector2:
	return _positions.get(node_id, Vector2.ZERO)


# ---- 撤销 / 重做(快照式:每次编辑前存整盘,恢复时节点 id 不变) ----

func undo() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(save_state())
	_apply_state(_undo_stack.pop_back())
	_notify(true)


func redo() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(save_state())
	_apply_state(_redo_stack.pop_back())
	_notify(true)


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


# ---- 求解结果查询(board_updated 之后随取随新) ----

func is_solved() -> bool:
	return _last_result.solved


## 某输入口当前织出的纹样;可能仍含未染纱,节点不存在时为 null
func get_input_pattern(node_id: int, port: int) -> Formula:
	return _last_result.value_in(node_id, port)


func get_output_pattern(node_id: int, port: int) -> Formula:
	return _last_result.value_out(node_id, port)


## 该输入口是否真的有线接入(false = 纹样只是正向推导的期望值,UI 画幽灵)
func is_input_connected(node_id: int, port: int) -> bool:
	return _last_result.input_connected(node_id, port)


## 该输出口是否有线接出,或(可钉口)已被钉住
func is_output_connected(node_id: int, port: int) -> bool:
	return _last_result.output_connected(node_id, port)


## 某条线的状态(WireState.*);线不存在时返回 WireState.OK
func get_wire_state(from_id: int, from_port: int, to_id: int, to_port: int) -> int:
	return _last_result.edge_status.get(
			Vector4i(from_id, from_port, to_id, to_port), WireState.OK)


## 全量连线快照。board 每次 board_updated 后:clear_connections() + 逐条重挂并按 state 着色
func get_wires() -> Array[WireInfo]:
	var out: Array[WireInfo] = []
	for e in _graph.edges:
		var w := WireInfo.new()
		w.from_id = e.x
		w.from_port = e.y
		w.to_id = e.z
		w.to_port = e.w
		w.state = _last_result.edge_status.get(e, WireState.OK)
		out.append(w)
	return out


## 结论链上还没接线的输入口:x = 节点 id,y = 输入口下标(UI 画红框提示)
func get_missing_inputs() -> Array[Vector2i]:
	return _last_result.missing_inputs.duplicate()


# ---- 元数据(建 UI 用) ----

## 全部仪器 id,顺序即建议的仪器架顺序
static func all_rule_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in Rules.all_ids():
		out.append(id)
	return out


## 某种仪器长什么样(几个口、哪个是假设口)—— palette 与 MachineNode 构建用
static func describe_rule(rule_id: StringName) -> MachineInfo:
	var schema := Rules.get_rule(rule_id)
	if schema == null:
		return null
	var info := MachineInfo.new()
	info.rule_id = schema.id
	info.cn_name = schema.cn_name
	for p in schema.inputs:
		info.inputs.append(_port_info(p))
	for p in schema.outputs:
		info.outputs.append(_port_info(p))
	return info


func get_node_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _graph.nodes:
		out.append(id)
	return out


## 棋盘上某个节点的结构描述(board_rebuilt 后全量重建节点用)。
## 只描述结构;端口上"当前织出的纹样"随时在变,用 get_*_pattern 拉取。
func describe_node(node_id: int) -> NodeInfo:
	var n: ProofGraph.ProofNode = _graph.nodes.get(node_id)
	if n == null:
		return null
	var info := NodeInfo.new()
	info.id = n.id
	info.type = n.kind as int
	match n.kind:
		ProofGraph.NodeKind.ASSUMPTION:
			info.title = "线轴"
			info.outputs.append(_formula_port(n.ports_out[0]))
		ProofGraph.NodeKind.GOAL:
			info.title = "目标织机"
			info.inputs.append(_formula_port(n.ports_in[0]))
		ProofGraph.NodeKind.RULE:
			var machine := describe_rule(n.rule_id)
			info.title = machine.cn_name
			info.rule_id = n.rule_id
			info.inputs = machine.inputs
			info.outputs = machine.outputs
			for port: int in n.pinned:
				info.pinned[port] = FormulaParser.to_text(n.pinned[port])
	return info


# ---- 存档 ----

## 可直接 JSON.stringify 的纯数据(位置存成 [x, y] 数组)
func save_state() -> Dictionary:
	var pos: Dictionary = {}
	for id: int in _positions:
		pos[str(id)] = [_positions[id].x, _positions[id].y]
	return {"graph": _graph.to_dict(), "positions": pos}


## 读档(清空撤销历史)。数据可以来自 save_state 或 JSON 往返后的字典。
func load_state(d: Dictionary) -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_apply_state(d)
	_initial_state = save_state()
	_was_solved = false
	_notify(true)


# ---- 内部 ----

func _push_undo() -> void:
	_undo_stack.append(save_state())
	_redo_stack.clear()


func _apply_state(d: Dictionary) -> void:
	_graph = ProofGraph.from_dict(d.graph)
	_positions = {}
	for key: String in d.positions:
		var xy: Array = d.positions[key]
		_positions[int(key)] = Vector2(xy[0], xy[1])


func _notify(rebuilt: bool) -> void:
	_last_result = _graph.solve()
	if rebuilt:
		board_rebuilt.emit()
	board_updated.emit()
	if _last_result.solved and not _was_solved:
		proof_completed.emit()
	_was_solved = _last_result.solved


func _kind(node_id: int) -> int:
	var n: ProofGraph.ProofNode = _graph.nodes.get(node_id)
	return n.kind if n != null else -1


static func _is_hyp_out(n: ProofGraph.ProofNode, out_port: int) -> bool:
	if n.kind != ProofGraph.NodeKind.RULE:
		return false
	return Rules.get_rule(n.rule_id).outputs[out_port].is_hypothesis


static func _port_info(p: RuleSchema.PortSpec) -> PortInfo:
	var info := PortInfo.new()
	info.label = FormulaParser.to_text(p.template)
	info.is_hypothesis = p.is_hypothesis
	info.scope_input = p.scope_input
	info.pinnable = p.pinnable
	return info


static func _formula_port(f: Formula) -> PortInfo:
	var info := PortInfo.new()
	info.label = FormulaParser.to_text(f)
	return info
