extends TestBase
## PatternEditor 核心(path_at / replace_at / brush_formula)headless 断言。

const R := Rect2(0, 0, 100, 100)


func test_build_a_imp_b_by_clicks() -> bool:
	var e := PatternEditor.new()
	e.brush = "imp"
	e.apply_brush_at(Vector2(50, 50), R)          # 孔 → 上下两孔
	e.brush = "atom:A"
	e.apply_brush_at(Vector2(50, 20), R)          # 上半 = A
	var mid_ok := check(not e.tree.is_ground(), "还剩下半孔,不该 ground")
	e.brush = "atom:B"
	e.apply_brush_at(Vector2(50, 80), R)          # 下半 = B
	var done := check(e.tree.equals(f("A > B")), "点出 A > B (得 %s)" % FormulaParser.to_text(e.tree)) \
		and check(e.tree.is_ground(), "填满后 ground")
	e.free()
	return mid_ok and done


## v1.1 §4.6:「挖回孔」笔刷删除;「清空」把画布擦回一个孔,空画布可确认(= 取消钉住)
func test_clear_canvas_and_empty_confirm() -> bool:
	var e := PatternEditor.new()
	var ok := check(e.is_canvas_empty() and not e._confirm.disabled, "刚打开:空画布,确认可按(= 取消钉住)")
	e.brush = "imp"
	e.apply_brush_at(Vector2(50, 50), R)
	ok = check(not e.is_canvas_empty() and e._confirm.disabled, "落了分割还有孔:不空、确认禁用") and ok
	e.clear_canvas()
	ok = check(e.is_canvas_empty() and e.tree.kind == Formula.Kind.META and not e._confirm.disabled, "清空后回到一个孔,确认可按") and ok
	ok = check(PatternEditor.brush_formula("erase") == null, "没有挖回孔笔刷") and ok
	var ids: Array = []
	for pair in PatternEditor.STRUCT_BRUSHES:
		ids.append(pair[0])
	ok = check(ids == ["and", "imp", "or"], "结构笔刷 并织/迭层/岔纹 三个(得 %s)" % str(ids)) and ok
	var cleared := [false]
	e.pattern_cleared.connect(func() -> void: cleared[0] = true)
	e._on_confirm()
	ok = check(cleared[0], "空画布确认 → pattern_cleared") and ok
	e.free()
	return ok


func test_or_triangle_sides() -> bool:
	var t := Formula.disj(Formula.meta(&"孔"), Formula.meta(&"孔"))
	var left := PatternEditor.path_at(t, R, Vector2(20, 20))     # 左上三角
	var right := PatternEditor.path_at(t, R, Vector2(80, 80))    # 右下三角
	return check(str(left) == "[0]", "左上 → 路径 [0] (得 %s)" % str(left)) \
		and check(str(right) == "[1]", "右下 → 路径 [1] (得 %s)" % str(right))


func test_nested_replace_keeps_siblings() -> bool:
	var t := f("A & (B | C)")
	var t2 := PatternEditor.replace_at(t, [1, 0] as Array[int], Formula.atom(&"D"))
	return check(t2.equals(f("A & (D | C)")), "只换 [1,0] (得 %s)" % FormulaParser.to_text(t2)) \
		and check(t.equals(f("A & (B | C)")), "原树不可变")


func test_bot_brush() -> bool:
	var e := PatternEditor.new()
	e.brush = "bot"
	e.apply_brush_at(Vector2(50, 50), R)
	var ok := check(e.tree.kind == Formula.Kind.BOT, "焦纹笔刷 → ⊥") and check(e.tree.is_ground(), "⊥ 算 ground")
	e.free()
	return ok
