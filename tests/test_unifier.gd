extends TestBase
## Unifier:合一、occurs check、冲突定位、顺序无关


func test_basic_propagation() -> bool:
	var r := Unifier.solve([[f("?P & B"), f("A & ?Q")]])
	return check((r.conflicts as Array).is_empty(), "应无冲突") \
		and check(Unifier.resolve(f("?P"), r.subst).equals(f("A")), "?P 应解得 A") \
		and check(Unifier.resolve(f("?Q"), r.subst).equals(f("B")), "?Q 应解得 B")


func test_occurs_check() -> bool:
	# ?a ≐ ?a∧B 会造出无限纹样,必须判为冲突
	var r := Unifier.solve([[f("?a"), f("?a & B")]])
	return check(r.conflicts == [0], "自包含绑定应被 occurs check 拦下")


func test_occurs_check_via_chain() -> bool:
	# 经链条间接自包含:?x ≐ ?y,再 ?y ≐ ?x∧B
	var r := Unifier.solve([[f("?x"), f("?y")], [f("?y"), f("?x & B")]])
	return check(r.conflicts == [1], "间接自包含也应被拦下")


func test_chain_resolve() -> bool:
	var r := Unifier.solve([[f("?x"), f("?y")], [f("?y"), f("A")]])
	return check(Unifier.resolve(f("?x"), r.subst).equals(f("A")), "沿绑定链应解到底")


func test_conflict_located_and_rest_continues() -> bool:
	var r := Unifier.solve([[f("A"), f("A")], [f("A"), f("B")], [f("?P"), f("C")]])
	return check(r.conflicts == [1], "冲突应精确定位在第 1 条(按插入序)") \
		and check(Unifier.resolve(f("?P"), r.subst).equals(f("C")), "冲突之后的方程应照常求解")


func test_order_independence() -> bool:
	# 方程顺序打乱,最终解一致
	var eqs_a := [[f("?x"), f("?y > C")], [f("?y"), f("A & B")]]
	var eqs_b := [[f("?y"), f("A & B")], [f("?x"), f("?y > C")]]
	var ra := Unifier.solve(eqs_a)
	var rb := Unifier.solve(eqs_b)
	var want := f("(A & B) > C")
	return check(Unifier.resolve(f("?x"), ra.subst).equals(want), "顺序 a 应解出 (A∧B)→C") \
		and check(Unifier.resolve(f("?x"), rb.subst).equals(want), "顺序 b 应解出同样结果")
