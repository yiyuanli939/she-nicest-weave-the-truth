extends TestBase
## 序列化:棋盘 → dict → JSON 文本 → 读回 → 求解结果不变(存档的正确性)


func test_json_roundtrip_conj() -> bool:
	var g := ProofGraph.new()
	var assum := g.add_assumption_node(f("A & B"))
	var goal := g.add_goal_node(f("B & A"))
	var split := g.add_rule_node(&"and_elim")
	var join := g.add_rule_node(&"and_intro")
	g.add_edge(Vector4i(assum, 0, split, 0))
	g.add_edge(Vector4i(split, 1, join, 0))
	g.add_edge(Vector4i(split, 0, join, 1))
	g.add_edge(Vector4i(join, 0, goal, 0))
	return _roundtrip_stays_solved(g)


func test_json_roundtrip_with_pins() -> bool:
	var g := ProofGraph.new()
	var goal := g.add_goal_node(f("A > (B > A)"))
	var outer := g.add_rule_node(&"imp_intro")
	var inner := g.add_rule_node(&"imp_intro")
	g.pin_hypothesis(outer, 1, f("A"))
	g.pin_hypothesis(inner, 1, f("B"))
	g.add_edge(Vector4i(outer, 1, inner, 0))
	g.add_edge(Vector4i(inner, 0, outer, 0))
	g.add_edge(Vector4i(outer, 0, goal, 0))
	return _roundtrip_stays_solved(g)


## 经 JSON 文本走一圈(整数会变浮点、字典键会变字符串,from_dict 必须扛住)
func _roundtrip_stays_solved(g: ProofGraph) -> bool:
	if not check(g.solve().solved, "前提:原棋盘本身应是完成态"):
		return false
	var text := JSON.stringify(g.to_dict())
	var g2 := ProofGraph.from_dict(JSON.parse_string(text))
	var r2 := g2.solve()
	return check(r2.solved, "读回的棋盘应仍是完成态") \
		and check(g2.edges == g.edges, "边表应原样读回")


func test_from_dict_drops_bad_pins() -> bool:
	var g := ProofGraph.new()
	var fe := g.add_rule_node(&"false_elim")
	var oe := g.add_rule_node(&"or_elim")
	var d := g.to_dict()
	for nd: Dictionary in d.nodes:
		if int(nd.id) == fe:
			nd.pinned = {"0": "?x"}   # 坏档:钉了未染纱(不过滤会让 walk 死循环)
		elif int(nd.id) == oe:
			nd.pinned = {"1": "A"}    # 旧档:钉在如今不可钉的汇路机假设口
	var g2 := ProofGraph.from_dict(d)
	var r := g2.solve()
	return check((g2.nodes[fe] as ProofGraph.ProofNode).pinned.is_empty(), "含未染纱的钉应被丢弃") \
		and check((g2.nodes[oe] as ProofGraph.ProofNode).pinned.is_empty(), "不可钉口的钉应被丢弃") \
		and check(r != null and not r.solved, "过滤后求解应正常返回")
