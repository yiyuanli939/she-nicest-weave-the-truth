extends TestBase
## ProofGraph:搭棋盘 → solve → 检查胜负与边状态。
## 两个"验收证明"也在这里:A∧B ⊢ B∧A 和 ⊢ A→(B→A)。


## 验收证明 1:A∧B ⊢ B∧A(拆股机拆开,并织机反着织回去)
func test_conj_swap_solved() -> bool:
	var g := ProofGraph.new()
	var assum := g.add_assumption_node(f("A & B"))
	var goal := g.add_goal_node(f("B & A"))
	var split := g.add_rule_node(&"and_elim")
	var join := g.add_rule_node(&"and_intro")
	var wired := g.add_edge(Vector4i(assum, 0, split, 0)) \
		and g.add_edge(Vector4i(split, 1, join, 0)) \
		and g.add_edge(Vector4i(split, 0, join, 1)) \
		and g.add_edge(Vector4i(join, 0, goal, 0))
	var r := g.solve()
	return check(wired, "四条线都应接得上") \
		and check(r.solved, "证明应完成") \
		and check(r.value_out(join, 0).equals(f("B & A")), "并织机应织出 B∧A")


## 验收证明 2:⊢ A→(B→A)(双层封程机,内层直接用外层的假设)
func test_nested_imp_solved() -> bool:
	var g := ProofGraph.new()
	var goal := g.add_goal_node(f("A > (B > A)"))
	var outer := g.add_rule_node(&"imp_intro")
	var inner := g.add_rule_node(&"imp_intro")
	g.pin_hypothesis(outer, 1, f("A"))
	g.pin_hypothesis(inner, 1, f("B"))
	var wired := g.add_edge(Vector4i(outer, 1, inner, 0)) \
		and g.add_edge(Vector4i(inner, 0, outer, 0)) \
		and g.add_edge(Vector4i(outer, 0, goal, 0))
	var r := g.solve()
	return check(wired, "三条线都应接得上") \
		and check(r.solved, "证明应完成") \
		and check(r.value_out(outer, 0).equals(f("A > (B > A)")), "封程机应织出 A→(B→A)")


## ⊢ A→A:假设口自环(接回本机封存口)是合法且必需的;普通口自环仍拒绝
func test_identity_self_hyp_edge() -> bool:
	var g := ProofGraph.new()
	var goal := g.add_goal_node(f("A > A"))
	var m := g.add_rule_node(&"imp_intro")
	g.pin_hypothesis(m, 1, f("A"))
	var hyp_loop := g.add_edge(Vector4i(m, 1, m, 0))
	var plain_loop := g.add_edge(Vector4i(m, 0, m, 0))
	g.add_edge(Vector4i(m, 0, goal, 0))
	var r := g.solve()
	return check(hyp_loop, "假设口自环应放行") \
		and check(not plain_loop, "普通输出口自环仍应拒绝") \
		and check(r.solved, "⊢ A→A 应完成") \
		and check(r.value_out(m, 0).equals(f("A > A")), "封程机应织出 A→A")


func test_missing_input_blocks() -> bool:
	var g := ProofGraph.new()
	var assum := g.add_assumption_node(f("A & B"))
	var goal := g.add_goal_node(f("B & A"))
	var split := g.add_rule_node(&"and_elim")
	var join := g.add_rule_node(&"and_intro")
	g.add_edge(Vector4i(assum, 0, split, 0))
	g.add_edge(Vector4i(split, 1, join, 0))
	# 故意不接 join 的 1 号口
	g.add_edge(Vector4i(join, 0, goal, 0))
	var r := g.solve()
	return check(not r.solved, "缺输入不能算赢") \
		and check(r.missing_inputs.has(Vector2i(join, 1)), "应指出缺的正是 join 的 1 号口")


func test_conflict_marked() -> bool:
	var g := ProofGraph.new()
	var assum := g.add_assumption_node(f("A"))
	var goal := g.add_goal_node(f("B"))
	var e := Vector4i(assum, 0, goal, 0)
	g.add_edge(e)
	var r := g.solve()
	return check(r.edge_status[e] == SolveResult.EdgeStatus.CONFLICT, "A 接到 B 应标冲突") \
		and check(not r.solved, "冲突不能算赢")


func test_cycle_marked() -> bool:
	var g := ProofGraph.new()
	var a := g.add_rule_node(&"and_intro")
	var b := g.add_rule_node(&"and_elim")
	var e1 := Vector4i(a, 0, b, 0)
	var e2 := Vector4i(b, 0, a, 0)
	g.add_edge(e1)
	g.add_edge(e2)
	var r := g.solve()
	return check(r.edge_status[e1] == SolveResult.EdgeStatus.CYCLE, "环上的边应标 CYCLE") \
		and check(r.edge_status[e2] == SolveResult.EdgeStatus.CYCLE, "环上的边应标 CYCLE")


func test_underspec_marked() -> bool:
	var g := ProofGraph.new()
	var assum := g.add_assumption_node(f("A"))
	var join := g.add_rule_node(&"and_intro")
	var split := g.add_rule_node(&"and_elim")
	g.add_edge(Vector4i(assum, 0, join, 0))
	var e := Vector4i(join, 0, split, 0)   # 此线织样为 A∧?,右半仍是未染纱
	g.add_edge(e)
	var r := g.solve()
	return check(r.edge_status[e] == SolveResult.EdgeStatus.UNDERSPEC, "含未染纱的线应标欠定")


func test_edge_rules() -> bool:
	var g := ProofGraph.new()
	var a := g.add_assumption_node(f("A"))
	var join := g.add_rule_node(&"and_intro")
	return check(g.add_edge(Vector4i(a, 0, join, 0)), "正常接线应成功") \
		and check(not g.add_edge(Vector4i(a, 0, join, 0)), "输入口已占用应拒绝(单口单线)") \
		and check(not g.add_edge(Vector4i(join, 0, join, 1)), "自环应拒绝") \
		and check(not g.add_edge(Vector4i(a, 5, join, 1)), "不存在的端口应拒绝")
