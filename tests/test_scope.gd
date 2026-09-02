extends TestBase
## 辖域检查:局部假设只许在"汇入本机封存口"的子证明里用,越界必须被抓。


## 假设直接接到结论 = 最赤裸的越界
func test_hypothesis_escapes_to_goal() -> bool:
	var g := ProofGraph.new()
	var goal := g.add_goal_node(f("A"))
	var m := g.add_rule_node(&"imp_intro")
	g.pin_hypothesis(m, 1, f("A"))
	var e := Vector4i(m, 1, goal, 0)
	g.add_edge(e)
	var r := g.solve()
	return check(r.edge_status[e] == SolveResult.EdgeStatus.ESCAPED_HYP, "越界假设应标 ESCAPED_HYP") \
		and check(not r.solved, "纹样虽对得上,越界也不能算赢")


## 假设穿过多台机器、最终在封存口消掉 = 合法:⊢ (A∧B)→(B∧A)
func test_hypothesis_carried_then_discharged() -> bool:
	var g := ProofGraph.new()
	var goal := g.add_goal_node(f("(A & B) > (B & A)"))
	var m := g.add_rule_node(&"imp_intro")
	g.pin_hypothesis(m, 1, f("A & B"))
	var split := g.add_rule_node(&"and_elim")
	var join := g.add_rule_node(&"and_intro")
	var wired := g.add_edge(Vector4i(m, 1, split, 0)) \
		and g.add_edge(Vector4i(split, 1, join, 0)) \
		and g.add_edge(Vector4i(split, 0, join, 1)) \
		and g.add_edge(Vector4i(join, 0, m, 0)) \
		and g.add_edge(Vector4i(m, 0, goal, 0))
	var r := g.solve()
	return check(wired, "五条线都应接得上") and check(r.solved, "合法用假设的证明应完成")


## v1.1 §2:每条线是否搭载未消去的假设要暴露给 UI(整条画假设色)
func test_edge_hyps_exposed() -> bool:
	var g := ProofGraph.new()
	var goal := g.add_goal_node(f("(A & B) > (B & A)"))
	var m := g.add_rule_node(&"imp_intro")
	g.pin_hypothesis(m, 1, f("A & B"))
	var split := g.add_rule_node(&"and_elim")
	var join := g.add_rule_node(&"and_intro")
	var e_hyp := Vector4i(m, 1, split, 0)
	var e1 := Vector4i(split, 1, join, 0)
	var e2 := Vector4i(split, 0, join, 1)
	var e_back := Vector4i(join, 0, m, 0)
	var e_goal := Vector4i(m, 0, goal, 0)
	for e in [e_hyp, e1, e2, e_back, e_goal]:
		g.add_edge(e)
	var r := g.solve()
	return check(r.solved, "合法证明完成") \
		and check(r.carries_hyp(e_hyp) and r.carries_hyp(e1) and r.carries_hyp(e2) and r.carries_hyp(e_back),
				"假设口出发、穿过拆股/并织、回到封程机 Q 口的四条线都搭载假设") \
		and check(not r.carries_hyp(e_goal), "封程机出口的线已封存假设,不搭载") \
		and check(not r.carries_hyp(Vector4i(99, 0, 98, 0)), "不存在的边 → false")


## 汇路机(∨消去)双假设各归各的散口 = 合法:A∨B ⊢ B∨A
func test_or_elim_scopes_ok() -> bool:
	var g := _or_swap_board(false)
	return check(g.solve().solved, "A∨B ⊢ B∨A 应完成")


## 同一棋盘、两条汇流线互换 → 假设流错了口,必须报越界
func test_or_elim_crossed_escapes() -> bool:
	var g := _or_swap_board(true)
	var r := g.solve()
	var escaped := false
	for e in g.edges:
		if r.edge_status[e] == SolveResult.EdgeStatus.ESCAPED_HYP:
			escaped = true
	return check(not r.solved, "假设窜口不能算赢") and check(escaped, "应有边标 ESCAPED_HYP")


## 搭 A∨B ⊢ B∨A 的棋盘。汇路机口位:入 [P∨Q, R(散口1), R(散口2)],
## 出 [R, 假设P(封存于入1), 假设Q(封存于入2)]。
## crossed = true 时把两条汇流线接反(纹样仍一致,只有辖域错)。
func _or_swap_board(crossed: bool) -> ProofGraph:
	var g := ProofGraph.new()
	var assum := g.add_assumption_node(f("A | B"))
	var goal := g.add_goal_node(f("B | A"))
	var oe := g.add_rule_node(&"or_elim")
	var m1 := g.add_rule_node(&"or_intro")   # 从假设 A 织出 B∨A(用出口 1,另一支钉 B)
	var m2 := g.add_rule_node(&"or_intro")   # 从假设 B 织出 B∨A(用出口 0,另一支钉 A)
	g.pin_hypothesis(m1, 1, f("B"))
	g.pin_hypothesis(m2, 0, f("A"))
	g.add_edge(Vector4i(assum, 0, oe, 0))
	g.add_edge(Vector4i(oe, 1, m1, 0))
	g.add_edge(Vector4i(oe, 2, m2, 0))
	g.add_edge(Vector4i(m1, 1, oe, 2 if crossed else 1))
	g.add_edge(Vector4i(m2, 0, oe, 1 if crossed else 2))
	g.add_edge(Vector4i(oe, 0, goal, 0))
	return g
