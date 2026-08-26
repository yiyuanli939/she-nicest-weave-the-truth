extends TestBase
## Formula:规范串、相等、不可变、查询


func test_key_and_equals() -> bool:
	var a := Formula.conj(Formula.atom(&"A"), Formula.atom(&"B"))
	return check(a.key() == "&(A,B)", "key 应为 &(A,B),实际 " + a.key()) \
		and check(a.equals(f("A & B")), "独立构造的相同公式应 equals") \
		and check(not a.equals(f("B & A")), "A∧B 不等于 B∧A(结构相等,不是逻辑等价)") \
		and check(not Formula.meta(&"A").equals(Formula.atom(&"A")), "元变量 ?A 不等于原子 A")


func test_subst_returns_new_tree() -> bool:
	var g := f("?P & B")
	var h := g.subst({&"P": Formula.atom(&"A")})
	return check(h.key() == "&(A,B)", "替换结果应为 A∧B") \
		and check(g.key() == "&(?P,B)", "原树必须原样不动(不可变)")


func test_queries() -> bool:
	var g := f("?P & (?Q > ?P)")
	return check(g.metas().size() == 2, "去重后应有 2 个元变量") \
		and check(g.contains_meta(&"Q"), "应含 ?Q") \
		and check(not g.contains_meta(&"Z"), "不应含 ?Z") \
		and check(not g.is_ground(), "含元变量不算落地") \
		and check(f("A & (B > false)").is_ground(), "无元变量即落地") \
		and check(f("A & (B > C)").depth() == 2, "深度应为 2")
