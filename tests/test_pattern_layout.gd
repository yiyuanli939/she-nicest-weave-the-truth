extends TestBase
## PatternView.layout() 纯几何断言(headless,不开窗)。


func _leaves(entries: Array[Dictionary], shape: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries:
		if e.shape == shape:
			out.append(e)
	return out


func _leaf_named(entries: Array[Dictionary], n: StringName) -> Dictionary:
	for e in entries:
		if e.shape in ["rect", "tri"] and e.get("name", &"") == n:
			return e
	return {}


## v1.1 §4.2:按路径取子式区域(纹样边框按子命题着色用),与 layout 同一套切分
func test_region_of_path() -> bool:
	var r := Rect2(0, 0, 100, 100)
	var whole := PatternView.region_of_path(f("A & B"), r, [] as Array[int])
	var ok := check(whole.shape == "rect" and whole.rect == r, "[] = 整幅")
	var l := PatternView.region_of_path(f("A & B"), r, [0] as Array[int])
	var rr := PatternView.region_of_path(f("A & B"), r, [1] as Array[int])
	ok = check(l.rect == Rect2(0, 0, 50, 100) and rr.rect == Rect2(50, 0, 50, 100), "并织:左右两半") and ok
	var top := PatternView.region_of_path(f("A > B"), r, [0] as Array[int])
	var bottom := PatternView.region_of_path(f("A > B"), r, [1] as Array[int])
	ok = check(top.rect == Rect2(0, 0, 100, 50) and bottom.rect == Rect2(0, 50, 100, 50), "迭层:上下两半") and ok
	var tl := PatternView.region_of_path(f("A | B"), r, [0] as Array[int])
	var br := PatternView.region_of_path(f("A | B"), r, [1] as Array[int])
	ok = check(tl.shape == "tri" and tl.points == PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(0, 100)]), "岔纹左上三角") and ok
	ok = check(br.shape == "tri" and br.points == PackedVector2Array([Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]), "岔纹右下三角") and ok
	var nested := PatternView.region_of_path(f("(A & B) | C"), r, [0, 1] as Array[int])
	ok = check(nested.shape == "rect" and nested.rect == Rect2(24, 0, 24, 48), "岔纹子式退回内接矩形再切分(得 %s)" % str(nested)) and ok
	ok = check(PatternView.region_of_path(f("A"), r, [0] as Array[int]).is_empty(), "越过叶子 → 空") and ok
	return ok


func test_and_splits_vertically() -> bool:
	var es := PatternView.layout(f("A & B"), Rect2(0, 0, 100, 100))
	var a := _leaf_named(es, &"A")
	var b := _leaf_named(es, &"B")
	var lines := _leaves(es, "line")
	return check(not a.is_empty() and not b.is_empty(), "应有 A、B 两叶") \
		and check(a.rect == Rect2(0, 0, 50, 100), "A 占左半 (得 %s)" % a.rect) \
		and check(b.rect == Rect2(50, 0, 50, 100), "B 占右半 (得 %s)" % b.rect) \
		and check(lines.size() == 1 and lines[0].from == Vector2(50, 0) and lines[0].to == Vector2(50, 100), "竖分割线在 x=50")


func test_imp_antecedent_on_top() -> bool:
	var es := PatternView.layout(f("A > B"), Rect2(0, 0, 100, 100))
	var a := _leaf_named(es, &"A")
	var b := _leaf_named(es, &"B")
	return check(a.rect == Rect2(0, 0, 100, 50), "前件 A 在上半 (得 %s)" % a.rect) \
		and check(b.rect == Rect2(0, 50, 100, 50), "后件 B 在下半 (得 %s)" % b.rect)


func test_or_two_triangles() -> bool:
	var es := PatternView.layout(f("A | B"), Rect2(0, 0, 100, 100))
	var tris := _leaves(es, "tri")
	var lines := _leaves(es, "line")
	return check(tris.size() == 2, "应有两个三角 (得 %d)" % tris.size()) \
		and check(_leaf_named(es, &"A").shape == "tri" and _leaf_named(es, &"B").shape == "tri", "A、B 各占一三角") \
		and check(lines.size() == 1 and lines[0].from == Vector2(100, 0) and lines[0].to == Vector2(0, 100), "对角线 TR→BL")


func test_line_width_decreases_with_depth() -> bool:
	var es := PatternView.layout(f("A & (B & C)"), Rect2(0, 0, 100, 100))
	var widths: Array[float] = []
	for e in _leaves(es, "line"):
		widths.append(e.width)
	widths.sort()
	return check(widths.size() == 2, "两条分割线") \
		and check(widths[0] < widths[1], "内层线更细 (得 %s)" % str(widths)) \
		and check(is_equal_approx(widths[1], PatternView.BASE_LINE_W), "外层线 = 基准宽")


func test_meta_bot_null_leaves() -> bool:
	var meta := PatternView.layout(f("?P"), Rect2(0, 0, 10, 10))
	var bot := PatternView.layout(f("false"), Rect2(0, 0, 10, 10))
	var blank := PatternView.layout(null, Rect2(0, 0, 10, 10))
	return check(meta.size() == 1 and meta[0].kind == Formula.Kind.META, "META 单叶") \
		and check(bot.size() == 1 and bot[0].kind == Formula.Kind.BOT, "BOT 单叶") \
		and check(blank.size() == 1 and blank[0].kind == -1, "null → 空白叶")


func test_depth_cutoff() -> bool:
	var src := "A"
	for i in 10:
		src = "(%s) & A" % src
	var es := PatternView.layout(f(src), Rect2(0, 0, 100, 100))
	return check(_leaves(es, "deep").size() > 0, "超深应出现省略织纹条目")


func test_view_instantiates_headless() -> bool:
	var v := PatternView.new()
	v.formula_text = "A & ?P"
	var ok := check(v.formula != null, "formula_text 应解析成功")
	v.formula_text = "A &"
	ok = ok and check(v.formula == null, "坏公式 → formula 为 null(错纹)")
	var color_a := v.atom_color(&"A")
	ok = ok and check(color_a.a == 1.0, "原子回退色应不透明")
	v.free()
	return ok
