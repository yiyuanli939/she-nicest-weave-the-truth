extends TestBase
## 穷举 / 随机式回归:正向求解器在"每台机器 × 每个口 × 每种接法"下都不崩、不死循环、
## 守住不变量;每关解法的每个钉、每条线都必要,且接线顺序无关;存档残留无害。
## 所有随机都用固定种子,失败可复现。

const POOL: Array[String] = ["A", "B", "A & B", "A | B", "A > B", "false", "B > A", "(A > B) > A"]


# ---- 1. 机器两两全枚举:每对(出口 → 入口)接一条线 ----

func test_every_rule_pair_every_port() -> bool:
	var ok := true
	var count := 0
	for ru in Rules.all_ids():
		for rv in Rules.all_ids():
			var su := Rules.get_rule(ru)
			var sv := Rules.get_rule(rv)
			for i in su.outputs.size():
				for j in sv.inputs.size():
					var g := ProofGraph.new()
					var u := g.add_rule_node(ru)
					var v := g.add_rule_node(rv)
					if not g.add_edge(Vector4i(u, i, v, j)):
						continue
					count += 1
					ok = _invariants(g, "%s.out%d → %s.in%d" % [ru, i, rv, j]) and ok
	return check(count >= 40, "应枚举到几十种接法(得 %d)" % count) and ok


## 同一台机器自己接自己:只有假设口允许(封程机 ⊢A→A 的自环),其余一律拒绝
func test_every_rule_self_edge() -> bool:
	var ok := true
	for rid in Rules.all_ids():
		var schema := Rules.get_rule(rid)
		for i in schema.outputs.size():
			for j in schema.inputs.size():
				var g := ProofGraph.new()
				var u := g.add_rule_node(rid)
				var accepted := g.add_edge(Vector4i(u, i, u, j))
				ok = check(accepted == schema.outputs[i].is_hypothesis,
						"%s.out%d → 自己.in%d:假设口才许自环" % [rid, i, j]) and ok
				if accepted:
					ok = _invariants(g, "%s 自环 %d→%d" % [rid, i, j]) and ok
	return ok


## 每个可钉口钉每种纹样:钉值原样出现在出口纹样里,且不被任何下游改写
func test_every_pinnable_port_every_pin_value() -> bool:
	var ok := true
	for rid in Rules.all_ids():
		var schema := Rules.get_rule(rid)
		for p in schema.outputs.size():
			if not schema.outputs[p].pinnable:
				continue
			for txt in POOL:
				var g := ProofGraph.new()
				var goal := g.add_goal_node(f("B"))          # 故意和大多数钉值对不上
				var u := g.add_rule_node(rid)
				g.pin_hypothesis(u, p, f(txt))
				var e := Vector4i(u, p, goal, 0)
				g.add_edge(e)
				var r := g.solve()
				var n: ProofGraph.ProofNode = g.nodes[u]
				var got := _subtree_at_meta(n.ports_out[p], r.value_out(u, p), ProofGraph._port_free_meta(n, p))
				ok = check(got != null and got.equals(f(txt)), "%s.out%d 钉 %s 后应原样织出" % [rid, p, txt]) and ok
				ok = check(r.edge_status[e] != SolveResult.EdgeStatus.OK or r.value_out(u, p).equals(f("B")),
						"%s.out%d 钉 %s 接目标 B:要么冲突/欠定,要么恰好相等" % [rid, p, txt]) and ok
	return ok


# ---- 2. 随机图:不变量 + 接线顺序无关 + 序列化往返 ----

func test_random_graphs_hold_invariants() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260827
	var rule_ids := Rules.all_ids()
	var ok := true
	for trial in 300:
		var g := ProofGraph.new()
		var ids: Array[int] = []
		for k in rng.randi_range(0, 2):
			ids.append(g.add_assumption_node(f(POOL[rng.randi_range(0, POOL.size() - 1)])))
		ids.append(g.add_goal_node(f(POOL[rng.randi_range(0, POOL.size() - 1)])))
		for k in rng.randi_range(1, 4):
			ids.append(g.add_rule_node(rule_ids[rng.randi_range(0, rule_ids.size() - 1)]))
		for id in ids:
			var n: ProofGraph.ProofNode = g.nodes[id]
			if n.kind != ProofGraph.NodeKind.RULE:
				continue
			var schema := Rules.get_rule(n.rule_id)
			for p in schema.outputs.size():
				if schema.outputs[p].pinnable and rng.randf() < 0.5:
					g.pin_hypothesis(id, p, f(POOL[rng.randi_range(0, POOL.size() - 1)]))
		for k in rng.randi_range(0, 9):
			var a: int = ids[rng.randi_range(0, ids.size() - 1)]
			var b: int = ids[rng.randi_range(0, ids.size() - 1)]
			var na: ProofGraph.ProofNode = g.nodes[a]
			var nb: ProofGraph.ProofNode = g.nodes[b]
			if na.ports_out.is_empty() or nb.ports_in.is_empty():
				continue
			g.add_edge(Vector4i(a, rng.randi_range(0, na.ports_out.size() - 1),
					b, rng.randi_range(0, nb.ports_in.size() - 1)))
		var tag := "random#%d" % trial
		ok = _invariants(g, tag) and ok
		# 接线顺序无关:胜负与"哪些边 OK 之外"的结论不该随插入序变化
		var r := g.solve()
		for round in 3:
			var d := g.to_dict()
			_shuffle(d.edges, rng)
			var g2 := ProofGraph.from_dict(d)
			var r2 := g2.solve()
			ok = check(r2.solved == r.solved, "%s 乱序后胜负应一致" % tag) and ok
			ok = check(r2.missing_inputs.size() == r.missing_inputs.size(), "%s 乱序后缺口数应一致" % tag) and ok
	return ok


# ---- 3. 每关解法:能通关;去掉任一钉/任一线都不通关;乱序接线仍通关;钉的原子本关可用 ----

func test_level_solutions_complete_minimal_and_order_free() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	var ok := true
	for lv in LevelCatalog.load_default().all_levels():
		ok = check(LevelSolutions.DATA.has(lv.id), "%s 缺脚本化解法" % lv.id) and ok
		if not LevelSolutions.DATA.has(lv.id):
			continue
		var sol: Dictionary = LevelSolutions.DATA[lv.id]
		var full := _build_level(lv, sol, -1, -1, [])
		ok = check(full.is_solved(), "%s 完整解法应通关" % lv.id) and ok
		full.free()
		for k in (sol.p as Array).size():
			var s := _build_level(lv, sol, k, -1, [])
			ok = check(not s.is_solved(), "%s 少钉第 %d 个不该通关(钉是必要的)" % [lv.id, k]) and ok
			s.free()
		for k in (sol.w as Array).size():
			var s := _build_level(lv, sol, -1, k, [])
			ok = check(not s.is_solved(), "%s 少接第 %d 条线不该通关(线是必要的)" % [lv.id, k]) and ok
			s.free()
		for round in 4:
			var order: Array = range((sol.w as Array).size())
			_shuffle(order, rng)
			var s := _build_level(lv, sol, -1, -1, order)
			ok = check(s.is_solved(), "%s 接线顺序 %s 也应通关" % [lv.id, str(order)]) and ok
			s.free()
		for pin: Array in sol.p:
			var pf := f(pin[2])
			for a in _atoms_of(pf):
				ok = check(lv.atoms.has(a), "%s 要钉的原子 %s 不在本关 atoms 里,编辑器画不出来" % [lv.id, a]) and ok
			ok = check(lv.allow_bot or not _contains_bot(pf), "%s 要钉焦纹但本关没解锁焦纹笔刷" % lv.id) and ok
	return ok


# ---- 4. 存档残留:删掉的关卡 id / 旧版 notebook 字段留在档里不该出事 ----

func test_legacy_save_entries_are_harmless() -> bool:
	var sm := SaveManager.new()
	sm.mark_solved(&"l16")
	sm.mark_solved(&"l17")
	sm.set_board_state(&"l16", {"graph": {"next_meta": 2, "nodes": [], "edges": []}, "positions": {}})
	sm.save()
	# 旧版存档带 notebook 数组:读档应静默忽略
	var f := FileAccess.open(SaveManager.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({solved = {"l16": true, "l17": true}, boards = {}, notebook = ["notebook_tnd", "notebook_and"]}))
	f.close()
	var sm2 := SaveManager.open()
	var nb := NotebookCatalog.load_default()
	var ui := NotebookUI.new()
	var all_ids: Array = []
	for e in nb.entries:
		all_ids.append(e.id)
	ui.open(nb, all_ids)
	var shown: int = ui._entries.size()
	ui.open(nb, [])
	var shown_none: int = ui._entries.size()
	ui.free()
	var ok := check(sm2.is_solved(&"l16"), "残留的通关记录读回来照旧") \
		and check(shown == nb.entries.size(), "传全部 rule_id:显示 %d 条(得 %d)" % [nb.entries.size(), shown]) \
		and check(shown_none == 0, "传空:一条不显示(严格过滤,无空=全量兜底)") \
		and check(nb.entry(&"notebook_tnd") == null, "目录里不再有两仪条目")
	sm2.wipe()
	return ok


# ---- 5. ProofSession 随机操作序列:undo 全部回退到初态、redo 全部回到终态 ----

func test_session_random_ops_undo_redo() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rule_ids := Rules.all_ids()
	var ok := true
	for trial in 20:
		var s := ProofSession.new()
		s.setup(["A & B", "A > B"], "B")
		var initial := s.save_state()
		var steps := 0
		for k in rng.randi_range(3, 12):
			var ids := s.get_node_ids()
			match rng.randi_range(0, 4):
				0:
					s.place_machine(rule_ids[rng.randi_range(0, rule_ids.size() - 1)])
					steps += 1
				1:
					var a: int = ids[rng.randi_range(0, ids.size() - 1)]
					var b: int = ids[rng.randi_range(0, ids.size() - 1)]
					if s.connect_wire(a, 0, b, 0):
						steps += 1
				2:
					var id: int = ids[rng.randi_range(0, ids.size() - 1)]
					var info := s.describe_node(id)
					if info != null and info.type == ProofSession.NodeType.MACHINE:
						s.remove_machine(id)
						steps += 1
				3:
					var id: int = ids[rng.randi_range(0, ids.size() - 1)]
					var info := s.describe_node(id)
					if info != null and info.type == ProofSession.NodeType.MACHINE:
						for p in info.outputs.size():
							if info.outputs[p].pinnable:
								if s.pin_hypothesis(id, p, "A") == "":
									steps += 1
								break
				4:
					if s.can_undo():
						s.undo()
						steps -= 1
		# 收尾:把剩余的 redo 做完,让"终态"没有悬空的 redo 栈(否则重做全部会越过它)
		while s.can_redo():
			s.redo()
			steps += 1
		var final := s.save_state()
		var undone := 0
		while s.can_undo():
			s.undo()
			undone += 1
		ok = check(_same_graph(s.save_state(), initial), "trial %d 全部撤销应回到初态" % trial) and ok
		ok = check(undone == steps, "trial %d 撤销步数应等于有效操作数(%d vs %d)" % [trial, undone, steps]) and ok
		while s.can_redo():
			s.redo()
		ok = check(_same_graph(s.save_state(), final), "trial %d 全部重做应回到终态" % trial) and ok
		s.free()
	return ok


# ---- 工具 ----

## 一张图求解后必须成立的全部性质
func _invariants(g: ProofGraph, tag: String) -> bool:
	var r := g.solve()
	var ok := true
	var topo := g._topo_order()
	for id: int in g.nodes:
		var n: ProofGraph.ProofNode = g.nodes[id]
		for i in n.ports_in.size():
			ok = check(r.value_in(id, i) != null, "%s: 每个输入口都有纹样" % tag) and ok
		for i in n.ports_out.size():
			ok = check(r.value_out(id, i) != null, "%s: 每个输出口都有纹样" % tag) and ok
		for port: int in n.pinned:
			var got := _subtree_at_meta(n.ports_out[port], r.value_out(id, port), ProofGraph._port_free_meta(n, port))
			ok = check(got != null and got.equals(n.pinned[port]), "%s: 钉值不得被改写" % tag) and ok
			ok = check(r.output_connected(id, port), "%s: 钉住的口算 connected" % tag) and ok
	for e in g.edges:
		ok = check(r.edge_status.has(e), "%s: 每条边都有状态" % tag) and ok
		var st: int = r.edge_status.get(e, -1)
		var out_v := r.value_out(e.x, e.y)
		var in_v := r.value_in(e.z, e.w)
		ok = check(r.output_connected(e.x, e.y) and r.input_connected(e.z, e.w), "%s: 边两端算 connected" % tag) and ok
		match st:
			SolveResult.EdgeStatus.OK:
				ok = check(out_v.is_ground() and in_v.is_ground() and out_v.equals(in_v),
						"%s: OK 的边两侧必须全染色且相等" % tag) and ok
			SolveResult.EdgeStatus.UNDERSPEC:
				ok = check(not out_v.is_ground() or not in_v.is_ground(), "%s: 欠定的边至少一侧含未染纱" % tag) and ok
			SolveResult.EdgeStatus.CYCLE:
				ok = check(not topo.has(e.x) or not topo.has(e.z), "%s: CYCLE 的边至少一端在环上" % tag) and ok
			SolveResult.EdgeStatus.CONFLICT, SolveResult.EdgeStatus.ESCAPED_HYP:
				pass
			_:
				ok = check(false, "%s: 未知边状态 %d" % [tag, st]) and ok
		if topo.has(e.x) and topo.has(e.z):
			ok = check(st != SolveResult.EdgeStatus.CYCLE, "%s: 不在环上的边不该标 CYCLE" % tag) and ok
	# 严格正向:摘掉一条(不在环上的)普通边,上游节点的所有输出纹样纹丝不动。
	# 假设口出边不查:假设 → 子证明 → 回流到本机入口是正当的正向链路(封程机的
	# 结论本来就取决于子证明),不是反推。
	for e in g.edges:
		if not topo.has(e.x) or not topo.has(e.z) or g._is_hyp_edge(e):
			continue
		var g2 := ProofGraph.from_dict(g.to_dict())
		g2.remove_edge(e)
		var r2 := g2.solve()
		var up: ProofGraph.ProofNode = g.nodes[e.x]
		for i in up.ports_out.size():
			ok = check(r2.value_out(e.x, i).equals(r.value_out(e.x, i)),
					"%s: 摘掉下游线 %s 不得改变上游 %d 号出口(禁反推)" % [tag, str(e), i]) and ok
	if r.solved:
		var goal := g._goal_node()
		ok = check(goal != null and r.missing_inputs.is_empty(), "%s: 通关时不该有缺口" % tag) and ok
		for e in g.edges:
			if goal != null and e.z == goal.id:
				ok = check(r.edge_status[e] == SolveResult.EdgeStatus.OK, "%s: 通关时进目标的线必须 OK" % tag) and ok
	# 确定性 + 序列化往返
	var again := g.solve()
	var back := ProofGraph.from_dict(JSON.parse_string(JSON.stringify(g.to_dict()))).solve()
	for e in g.edges:
		ok = check(again.edge_status[e] == r.edge_status[e], "%s: 重解结果应确定" % tag) and ok
		ok = check(back.edge_status[e] == r.edge_status[e], "%s: JSON 往返后边状态不变" % tag) and ok
	for key: Vector3i in r.port_values:
		ok = check((back.port_values[key] as Formula).equals(r.port_values[key]), "%s: JSON 往返后纹样不变" % tag) and ok
	ok = check(back.solved == r.solved, "%s: JSON 往返后胜负不变" % tag) and ok
	return ok


## 模板里元变量 k 所在位置,在实际纹样里对应的子树
func _subtree_at_meta(template: Formula, value: Formula, k: StringName) -> Formula:
	if template.kind == Formula.Kind.META:
		return value if template.name == k else null
	if not template.is_binary() or not value.is_binary():
		return null
	var l := _subtree_at_meta(template.left, value.left, k)
	return l if l != null else _subtree_at_meta(template.right, value.right, k)


func _atoms_of(fm: Formula) -> Array[StringName]:
	var out: Array[StringName] = []
	if fm.kind == Formula.Kind.ATOM:
		out.append(fm.name)
	elif fm.is_binary():
		out.append_array(_atoms_of(fm.left))
		out.append_array(_atoms_of(fm.right))
	return out


func _contains_bot(fm: Formula) -> bool:
	if fm.kind == Formula.Kind.BOT:
		return true
	return fm.is_binary() and (_contains_bot(fm.left) or _contains_bot(fm.right))


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## 按 LevelSolutions.DATA 用纯 session API 搭一关;skip_pin/skip_wire = 跳过第几个(-1 不跳);
## order = 接线顺序(空 = 原序)。调用方负责 free。
func _build_level(lv: LevelDef, sol: Dictionary, skip_pin: int, skip_wire: int, order: Array) -> ProofSession:
	var s := ProofSession.new()
	assert(s.setup(lv.assumptions, lv.goal) == "")
	var machines: Array[int] = []
	for rid in sol.m:
		machines.append(s.place_machine(rid))
	for k in (sol.p as Array).size():
		if k == skip_pin:
			continue
		var pin: Array = sol.p[k]
		var err := s.pin_hypothesis(machines[int(String(pin[0]).substr(1))], pin[1], pin[2])
		assert(err == "", "%s 钉失败: %s" % [lv.id, err])
	var seq: Array = order if not order.is_empty() else range((sol.w as Array).size())
	for k in seq:
		if k == skip_wire:
			continue
		var w: Array = sol.w[k]
		s.connect_wire(LevelSolutions._resolve(w[0], s, machines), w[1],
				LevelSolutions._resolve(w[2], s, machines), w[3])
	return s


## 只比图结构(位置是视图元数据,undo 不保证)
func _same_graph(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a.graph) == JSON.stringify(b.graph)
