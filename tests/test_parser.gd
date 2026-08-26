extends TestBase
## FormulaParser:优先级、结合性、往返、报错


func test_precedence() -> bool:
	return check(f("A & B > C | D").key() == ">(&(A,B),|(C,D))", "& 高于 | 高于 >")


func test_associativity() -> bool:
	return check(f("A > B > C").key() == ">(A,>(B,C))", "> 应右结合") \
		and check(f("(A > B) > C").key() == ">(>(A,B),C)", "括号应改变结合") \
		and check(f("A & B & C").key() == "&(&(A,B),C)", "& 应左结合")


func test_bot_and_meta() -> bool:
	return check(f("false").kind == Formula.Kind.BOT, "false 应解析为 ⊥") \
		and check(f("⊥").kind == Formula.Kind.BOT, "⊥ 符号也应支持") \
		and check(f("?17").kind == Formula.Kind.META and f("?17").name == &"17", "?17 应为元变量 17")


func test_roundtrip() -> bool:
	# 右嵌套同级运算必须靠括号才能原样读回 —— to_text 的关键正确性
	var tricky := Formula.conj(Formula.atom(&"A"), f("B & C"))
	var samples: Array[Formula] = [tricky, f("A & B > C | D"), f("(A > B) > C"),
		f("(A | B) & C"), f("?P > false"), f("A | (B & C) | D")]
	for g in samples:
		var back := FormulaParser.parse(FormulaParser.to_text(g))
		if not check(back != null and back.equals(g),
				"往返失败: %s → %s" % [g.key(), FormulaParser.to_text(g)]):
			return false
	return true


func test_errors_return_null() -> bool:
	return check(FormulaParser.parse("A &") == null, "残缺公式应报错") \
		and check(FormulaParser.parse("(A") == null, "缺右括号应报错") \
		and check(FormulaParser.parse("") == null, "空串应报错") \
		and check(FormulaParser.parse("A B") == null, "多余内容应报错") \
		and check(not FormulaParser.last_error.is_empty(), "last_error 应说明原因")
