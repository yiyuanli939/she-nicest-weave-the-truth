class_name ProofGraph
extends RefCounted
## 证明棋盘的逻辑模型 —— 整个游戏唯一的 source of truth。
## UI(GraphEdit)只是它的投影:每次编辑先改这里,再 solve(),
## 然后按返回的 SolveResult 刷新画面。
##
## 节点三类:ASSUMPTION(线轴,给定命题)、GOAL(目标织机)、RULE(仪器)。
## 边 Vector4i(from 节点, from 输出口, to 节点, to 输入口),按插入序存放
## —— 这个顺序同时决定合一的方程顺序,保证冲突归因稳定。

enum NodeKind { ASSUMPTION, GOAL, RULE }

class ProofNode:
	var id: int
	var kind: int
	var rule_id: StringName            ## 仅 RULE 有
	var ports_in: Array[Formula] = []  ## 实例化后的输入口命题
	var ports_out: Array[Formula] = [] ## 实例化后的输出口命题
	var pinned: Dictionary = {}        ## {假设口下标: Formula} 玩家钉住的假设纹样


var nodes: Dictionary = {}        # id -> ProofNode
var edges: Array[Vector4i] = []
var _next_id: int = 1
var _next_meta: int = 1           # 元变量新鲜名计数器,全棋盘唯一


# ---- 编辑操作(UI 的每个动作都落到这几个函数上) ----

## 放一台仪器。模板的模式变量在这里统一换成新鲜元变量(硬规则 4:防捕获)。
func add_rule_node(rule_id: StringName) -> int:
	var schema := Rules.get_rule(rule_id)
	assert(schema != null, "未知规则: %s" % rule_id)
	var fresh: Dictionary = {}
	for port in schema.inputs + schema.outputs:
		for m in port.template.metas():
			if not fresh.has(m):
				fresh[m] = StringName(str(_next_meta))
				_next_meta += 1
	var n := _new_node(NodeKind.RULE)
	n.rule_id = rule_id
	for port in schema.inputs:
		n.ports_in.append(port.template.rename_metas(fresh))
	for port in schema.outputs:
		n.ports_out.append(port.template.rename_metas(fresh))
	return n.id


func add_assumption_node(f: Formula) -> int:
	var n := _new_node(NodeKind.ASSUMPTION)
	n.ports_out.append(f)
	return n.id


func add_goal_node(f: Formula) -> int:
	var n := _new_node(NodeKind.GOAL)
	n.ports_in.append(f)
	return n.id


func remove_node(id: int) -> void:
	nodes.erase(id)
	var kept: Array[Vector4i] = []
	for e in edges:
		if e.x != id and e.z != id:
			kept.append(e)
	edges = kept


## 连线。拒绝:节点/口不存在、自环(假设口除外)、输入口已被占用(单口单线)。
## 假设口的自环合法且必需:⊢A→A 就是封程机假设口直接接回本机封存口;
## 假设边不算依赖(_topo_order 排除),不会造成循环论证。
func add_edge(e: Vector4i) -> bool:
	var from: ProofNode = nodes.get(e.x)
	var to: ProofNode = nodes.get(e.z)
	if from == null or to == null:
		return false
	if e.y < 0 or e.y >= from.ports_out.size() or e.w < 0 or e.w >= to.ports_in.size():
		return false
	if e.x == e.z and not _is_hyp_edge(e):
		return false
	for old in edges:
		if old.z == e.z and old.w == e.w:
			return false
	edges.append(e)
	return true


func remove_edge(e: Vector4i) -> void:
	edges.erase(e)


## 玩家在封程机上"钉住"假设纹样(f 必须是编辑器产出的全染色纹样)
func pin_hypothesis(node_id: int, out_port: int, f: Formula) -> void:
	var n: ProofNode = nodes[node_id]
	var schema := Rules.get_rule(n.rule_id)
	assert(schema.outputs[out_port].is_hypothesis, "只有假设口可以钉纹样")
	assert(f.is_ground(), "钉住的纹样不能含未染纱")
	n.pinned[out_port] = f


func unpin_hypothesis(node_id: int, out_port: int) -> void:
	(nodes[node_id] as ProofNode).pinned.erase(out_port)


func _new_node(kind: int) -> ProofNode:
	var n := ProofNode.new()
	n.id = _next_id
	n.kind = kind
	_next_id += 1
	nodes[n.id] = n
	return n


# ---- 求解:五步管线 ----

func solve() -> SolveResult:
	var result := SolveResult.new()

	# 1) 收集方程。钉住的假设放最前(它们两端一定能合一,冲突就都归因到连线上)。
	var eqs: Array = []
	for id: int in nodes:
		var n: ProofNode = nodes[id]
		for port: int in n.pinned:
			eqs.append([n.ports_out[port], n.pinned[port]])
	var first_edge_eq := eqs.size()
	for e in edges:
		eqs.append([_out_formula(e), _in_formula(e)])

	# 2) 合一
	var uni := Unifier.solve(eqs)
	var subst: Dictionary = uni.subst
	for i: int in uni.conflicts:
		if i >= first_edge_eq:
			result.edge_status[edges[i - first_edge_eq]] = SolveResult.EdgeStatus.CONFLICT

	# 3) 环检测(顺便得到辖域检查要用的拓扑序)
	var topo := _topo_order()
	var on_cycle: Dictionary = {}
	for id: int in nodes:
		if not topo.has(id):
			on_cycle[id] = true
	for e in edges:
		if on_cycle.has(e.x) or on_cycle.has(e.z):
			_mark(result, e, SolveResult.EdgeStatus.CYCLE)

	# 4) 辖域检查
	var edge_hyps := _propagate_hyps(topo)
	var goal := _goal_node()
	for e in edges:
		if goal != null and e.z == goal.id and not (edge_hyps[e] as Dictionary).is_empty():
			_mark(result, e, SolveResult.EdgeStatus.ESCAPED_HYP)

	# 展开每个端口的最终纹样;顺便把"还含未染纱"的边标为欠定
	for id: int in nodes:
		var n: ProofNode = nodes[id]
		for i in n.ports_in.size():
			result.port_values[Vector3i(id, 0, i)] = Unifier.resolve(n.ports_in[i], subst)
		for i in n.ports_out.size():
			result.port_values[Vector3i(id, 1, i)] = Unifier.resolve(n.ports_out[i], subst)
		for port: int in n.pinned:
			result.connected_ports[Vector3i(id, 1, port)] = true
	for e in edges:
		result.connected_ports[Vector3i(e.x, 1, e.y)] = true
		result.connected_ports[Vector3i(e.z, 0, e.w)] = true
	for e in edges:
		if not Unifier.resolve(_in_formula(e), subst).is_ground():
			_mark(result, e, SolveResult.EdgeStatus.UNDERSPEC)
	for e in edges:
		if not result.edge_status.has(e):
			result.edge_status[e] = SolveResult.EdgeStatus.OK

	# 5) 胜利判定:结论的祖先子图必须完备、全 OK
	result.solved = _check_victory(result, goal)
	return result


## 结论已连,且它的祖先子图里:每台仪器输入口全接线、每条边状态 OK。
## (边 OK 已蕴含:无冲突、无环、假设未越界、纹样全部染色完成。)
func _check_victory(result: SolveResult, goal: ProofNode) -> bool:
	if goal == null:
		return false
	var visited: Dictionary = {goal.id: true}
	var queue: Array[int] = [goal.id]
	var ok := true
	while not queue.is_empty():
		var id: int = queue.pop_back()
		var n: ProofNode = nodes[id]
		for q in n.ports_in.size():
			var found: Vector4i = Vector4i(-1, -1, -1, -1)
			for e in edges:
				if e.z == id and e.w == q:
					found = e
					break
			if found.x < 0:
				result.missing_inputs.append(Vector2i(id, q))
				ok = false
				continue
			if result.edge_status[found] != SolveResult.EdgeStatus.OK:
				ok = false
			if not visited.has(found.x):
				visited[found.x] = true
				queue.append(found.x)
	return ok


# ---- 求解的内部步骤 ----

func _out_formula(e: Vector4i) -> Formula:
	return (nodes[e.x] as ProofNode).ports_out[e.y]


func _in_formula(e: Vector4i) -> Formula:
	return (nodes[e.z] as ProofNode).ports_in[e.w]


func _goal_node() -> ProofNode:
	for id: int in nodes:
		if (nodes[id] as ProofNode).kind == NodeKind.GOAL:
			return nodes[id]
	return null


## Kahn 拓扑排序。返回 {节点 id: 拓扑序号};不在其中的节点在环上(或环的下游)。
##
## 关键:假设口出发的边不算依赖。封程机的假设口 → 子证明 → 回到本机
## 输入口,在节点图上看着像环,但假设是"源头"(不依赖本机的输入),
## 并非循环论证。只有全走普通口的环才是真环(结论依赖了它自己)。
func _topo_order() -> Dictionary:
	var in_degree: Dictionary = {}
	for id: int in nodes:
		in_degree[id] = 0
	for e in edges:
		if not _is_hyp_edge(e):
			in_degree[e.z] += 1
	var queue: Array[int] = []
	for id: int in nodes:
		if in_degree[id] == 0:
			queue.append(id)
	var order: Dictionary = {}
	while not queue.is_empty():
		var id: int = queue.pop_front()
		order[id] = order.size()
		for e in edges:
			if e.x == id and not _is_hyp_edge(e):
				in_degree[e.z] -= 1
				if in_degree[e.z] == 0:
					queue.append(e.z)
	return order


func _is_hyp_edge(e: Vector4i) -> bool:
	var n: ProofNode = nodes[e.x]
	if n.kind != NodeKind.RULE:
		return false
	return Rules.get_rule(n.rule_id).outputs[e.y].is_hypothesis


## 辖域检查的核心:沿拓扑序,算出每条边上"搭载"的未封存假设集合。
##
## 假设的身份 HypId = Vector2i(机器 id, 假设口下标)。规则只有两条:
##   * 从假设口出发的边,搭载 {它自己};
##   * 从普通输出口出发的边,搭载本机所有输入边的并集 ——
##     但假设 h 流进"它自己那台机器的 scope_input 号输入口"时被封存(剔除)。
## 于是:合法用法的假设最终都在自己的封存口消失;越界的会一路搭载到
## 结论,在那里被抓(ESCAPED_HYP)。多层嵌套、汇路机双假设都不需要特判。
func _propagate_hyps(topo: Dictionary) -> Dictionary:
	var edge_hyps: Dictionary = {}          # 边 -> {HypId: true}
	for e in edges:
		# 假设边开局即知搭载什么(它就是源头),不用等上游 —— 这也是
		# _topo_order 能把它排除出依赖的原因
		edge_hyps[e] = {Vector2i(e.x, e.y): true} if _is_hyp_edge(e) else {}
	var by_order := topo.keys()
	by_order.sort_custom(func(a: int, b: int) -> bool: return topo[a] < topo[b])
	for id: int in by_order:
		# 汇总流入本机、且没在本机封存口被封存的假设
		var carried: Dictionary = {}
		for e in edges:
			if e.z != id:
				continue
			if not _is_hyp_edge(e) and not topo.has(e.x):
				continue   # 来自环上节点的普通边不可信,跳过(环已单独报错)
			for h: Vector2i in edge_hyps[e]:
				if not _discharged_here(h, id, e.w):
					carried[h] = true
		# 写到本机的每条普通出边上(假设出边已在上面定死)
		for e in edges:
			if e.x == id and not _is_hyp_edge(e):
				edge_hyps[e] = carried.duplicate()
	return edge_hyps


func _discharged_here(h: Vector2i, node_id: int, in_port: int) -> bool:
	if h.x != node_id:
		return false
	var schema := Rules.get_rule((nodes[node_id] as ProofNode).rule_id)
	return schema.outputs[h.y].scope_input == in_port


## 状态标记:先标的错误优先(冲突 > 环 > 越界 > 欠定,按调用顺序)
func _mark(result: SolveResult, e: Vector4i, status: int) -> void:
	if not result.edge_status.has(e):
		result.edge_status[e] = status


# ---- 序列化(存档 / 关卡棋盘恢复;公式经 FormulaParser 文本往返) ----

func to_dict() -> Dictionary:
	var node_list: Array = []
	for id: int in nodes:
		var n: ProofNode = nodes[id]
		var pinned_text: Dictionary = {}
		for port: int in n.pinned:
			pinned_text[str(port)] = FormulaParser.to_text(n.pinned[port])
		node_list.append({
			"id": n.id,
			"kind": n.kind,
			"rule_id": String(n.rule_id),
			"ports_in": n.ports_in.map(FormulaParser.to_text),
			"ports_out": n.ports_out.map(FormulaParser.to_text),
			"pinned": pinned_text,
		})
	return {
		"next_meta": _next_meta,
		"nodes": node_list,
		"edges": edges.map(func(e: Vector4i) -> Array: return [e.x, e.y, e.z, e.w]),
	}


## 注意:JSON 往返会把整数变成浮点、把字典键变成字符串,这里统一转回来。
static func from_dict(d: Dictionary) -> ProofGraph:
	var g := ProofGraph.new()
	g._next_meta = int(d.next_meta)
	for nd: Dictionary in d.nodes:
		var n := ProofNode.new()
		n.id = int(nd.id)
		n.kind = int(nd.kind)
		n.rule_id = StringName(nd.rule_id)
		for t: String in nd.ports_in:
			n.ports_in.append(FormulaParser.parse(t))
		for t: String in nd.ports_out:
			n.ports_out.append(FormulaParser.parse(t))
		for port_key: String in nd.pinned:
			n.pinned[int(port_key)] = FormulaParser.parse(nd.pinned[port_key])
		g.nodes[n.id] = n
		g._next_id = maxi(g._next_id, n.id + 1)
	for e: Array in d.edges:
		g.edges.append(Vector4i(int(e[0]), int(e[1]), int(e[2]), int(e[3])))
	return g
