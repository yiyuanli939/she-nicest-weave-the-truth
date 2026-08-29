extends TestBase
## tools/import_dialogue.gd 的纯函数部分:CSV 解析 + 校验(Excel 另存的 CSV 有引号/逗号/换行/BOM)。

const IMPORTER := "res://tools/import_dialogue.gd"


func _importer() -> GDScript:
	return load(IMPORTER)


func test_parse_basic_rows() -> bool:
	var csv := "﻿关卡id,发言人,场景,左侧人物,左侧表情,诺拉表情,台词,小机动作\r\n" \
		+ "l01,莉娅,工坊,莉娅,默认,,\"欢迎来到织坊,\n先认认线轴。\",greet\r\n" \
		+ "l01,诺拉·拉弗蒂,,,,惊讶,\"她说的\"\"线轴\"\"是什么?\",\r\n" \
		+ "l02,亚瑟·威客利夫,街景,亚瑟,默认,严肃,这事情可没你想得那么简单。,\r\n"
	var r: Dictionary = _importer().parse_csv(csv)
	var ok := check(r.errors.is_empty(), "无错误:%s" % str(r.errors)) \
		and check(r.levels.size() == 2 and r.levels.has("l01") and r.levels.has("l02"), "两关")
	if not ok:
		return false
	var l01: DialogueRes = r.levels["l01"]
	var a: DialogueLine = l01.lines[0]
	var b: DialogueLine = l01.lines[1]
	return check(l01.lines.size() == 2, "l01 两句") \
		and check(a.speaker == "莉娅" and a.scene == "工坊" and a.left_char == "莉娅" and a.robot_cue == "greet", "第一句字段") \
		and check(a.text == "欢迎来到织坊,\n先认认线轴。", "引号内逗号与换行保留") \
		and check(a.nora_expr == "默认", "空表情 → 默认") \
		and check(b.text == "她说的\"线轴\"是什么?", "双写引号还原") \
		and check(b.nora_expr == "惊讶" and b.left_char == "" and StoryArt.is_nora(b.speaker), "诺拉句") \
		and check((r.levels["l02"] as DialogueRes).lines[0].left_expr == "默认", "l02 左侧表情")


func test_invalid_rows_are_reported_and_skipped() -> bool:
	var csv := "关卡id,发言人,场景,左侧人物,左侧表情,诺拉表情,台词,小机动作\n" \
		+ "l03,莉娅,月球,,,,台词,\n" \
		+ "l03,莉娅,,诺拉,,,诺拉不能站左边,\n" \
		+ "l03,莉娅,,,狂喜,,未知表情,\n" \
		+ "l03,莉娅,工坊,,,,这句合法,\n"
	var r: Dictionary = _importer().parse_csv(csv)
	return check(r.errors.size() == 3, "三条错误 (得 %d: %s)" % [r.errors.size(), str(r.errors)]) \
		and check(r.levels.has("l03") and (r.levels["l03"] as DialogueRes).lines.size() == 1, "合法行仍导入")


func test_missing_required_header() -> bool:
	var r: Dictionary = _importer().parse_csv("关卡id,发言人\nl01,莉娅\n")
	return check(not r.errors.is_empty() and r.levels.is_empty(), "缺台词列应报错且不导入")


func test_first_line_of_each_level_needs_scene() -> bool:
	# 「场景空=沿用上一句」不跨关:某关首句没场景必须报错(策划只在全表第一行写场景是常见笔误)
	var csv := "关卡id,发言人,场景,台词\n" \
			+ "l01,莉娅,街景,首句有场景\n" \
			+ "l01,莉娅,,第二句沿用\n" \
			+ "l02,莉娅,,首句没场景\n" \
			+ "l02,莉娅,工坊,第二句才给\n"
	var r: Dictionary = _importer().parse_csv(csv)
	var ok := check(r.errors.size() == 1 and (r.errors[0] as String).contains("l02"),
			"只有 l02 报「首句没有场景」(得 %s)" % str(r.errors))
	ok = check((r.levels["l01"] as DialogueRes).lines.size() == 2, "l01 两句都解析成功") and ok
	return ok
