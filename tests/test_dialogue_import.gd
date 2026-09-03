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
	var l01: DialogueRes = r.levels["l01"].intro
	var a: DialogueLine = l01.lines[0]
	var b: DialogueLine = l01.lines[1]
	return check(l01.lines.size() == 2, "l01 两句") \
		and check(a.speaker == "莉娅" and a.scene == "工坊" and a.left_char == "莉娅" and a.robot_cue == "greet", "第一句字段") \
		and check(a.text == "欢迎来到织坊,\n先认认线轴。", "引号内逗号与换行保留") \
		and check(a.nora_expr == "默认", "空表情 → 默认") \
		and check(b.text == "她说的\"线轴\"是什么?", "双写引号还原") \
		and check(b.nora_expr == "惊讶" and b.left_char == "" and StoryArt.is_nora(b.speaker), "诺拉句") \
		and check((r.levels["l02"].intro as DialogueRes).lines[0].left_expr == "默认", "l02 左侧表情")


func test_invalid_rows_are_reported_and_skipped() -> bool:
	var csv := "关卡id,发言人,场景,左侧人物,左侧表情,诺拉表情,台词,小机动作\n" \
		+ "l03,莉娅,月球,,,,台词,\n" \
		+ "l03,莉娅,,诺拉,,,诺拉不能站左边,\n" \
		+ "l03,莉娅,,,狂喜,,未知表情,\n" \
		+ "l03,莉娅,工坊,,,,这句合法,\n"
	var r: Dictionary = _importer().parse_csv(csv)
	return check(r.errors.size() == 3, "三条错误 (得 %d: %s)" % [r.errors.size(), str(r.errors)]) \
		and check(r.levels.has("l03") and (r.levels["l03"].intro as DialogueRes).lines.size() == 1, "合法行仍导入")


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
	ok = check((r.levels["l01"].intro as DialogueRes).lines.size() == 2, "l01 两句都解析成功") and ok
	return ok


## 策划正式表:首行注意事项、别名表头、「章-节」关卡号、左位「无」/全名、4-3 → 通关后剧情
func test_planner_sheet_format() -> bool:
	var ep := {"1-1": "l01", "4-3": "l15"}
	var csv := "注意:4-3的剧情在玩家关卡完成之后播放,,,,,,\n" \
		+ "关卡,场景,主角表情,左位人物,左位人物表情,发言人,语句\n" \
		+ "1-1,工坊,,莉娅·科尔宾,,莉娅·科尔宾,第一次来东区的静语纹工坊?\n" \
		+ "1-1,,惊讶,无,,诺拉·拉芙蒂,这些就是静语织机?\n" \
		+ "4-3,诺拉房间,,亚瑟·威客利夫,严肃,诺拉·拉芙蒂,请检查这个前提。\n"
	var r: Dictionary = _importer().parse_csv(csv, ep)
	var ok := check(r.errors.is_empty(), "无错误:%s" % str(r.errors))
	if not ok:
		return false
	var l01: Dictionary = r.levels["l01"]
	var l15: Dictionary = r.levels["l15"]
	ok = check((l01.intro as DialogueRes).lines.size() == 2 and l01.outro == null, "1-1 → l01 进关对话两句") and ok
	var a: DialogueLine = (l01.intro as DialogueRes).lines[0]
	var b: DialogueLine = (l01.intro as DialogueRes).lines[1]
	ok = check(a.left_char == "莉娅" and a.nora_expr == "默认" and a.left_expr == "默认", "左位全名归一到短名;空表情=默认(注意事项①)") and ok
	ok = check(b.left_char == "" and b.nora_expr == "惊讶", "「无」= 左侧无人;主角表情列生效") and ok
	ok = check(l15.intro == null and (l15.outro as DialogueRes).lines.size() == 1, "4-3 → l15 通关后剧情,进关对话为空(注意事项②)") and ok
	ok = check((l15.outro as DialogueRes).lines[0].left_expr == "严肃", "左位人物表情列生效") and ok
	ok = check((l15.outro as DialogueRes).lines[0].scene == "诺拉房间" and StoryArt.SCENES.has("诺拉房间")
			and StoryArt.SCENES.has("伦敦街上"), "正式表的场景名已登记") and ok
	return ok


func test_outro_first_line_needs_scene() -> bool:
	var csv := "关卡,发言人,语句,场景\n4-3,莉娅·科尔宾,首句没场景,\n"
	var r: Dictionary = _importer().parse_csv(csv, {"4-3": "l15"})
	return check(r.errors.size() == 1 and (r.errors[0] as String).contains("通关后"),
			"通关后剧情首句没场景要报错(得 %s)" % str(r.errors))


## 英文台词列(语句_en / 台词_en / 英文语句)可缺:有则进 text_en,没有则空
func test_english_column_optional() -> bool:
	var with_en := "关卡,发言人,场景,语句,语句_en\n1-1,莉娅·科尔宾,工坊,第一句,\"First line, with a comma\"\n1-1,诺拉·拉芙蒂,,第二句,\n"
	var r: Dictionary = _importer().parse_csv(with_en, {"1-1": "l01"})
	var ok := check(r.errors.is_empty(), "无错误:%s" % str(r.errors))
	if not ok:
		return false
	var lines: Array = (r.levels["l01"].intro as DialogueRes).lines
	ok = check(lines[0].text == "第一句" and lines[0].text_en == "First line, with a comma", "语句_en 进 text_en") and ok
	ok = check(lines[1].text_en == "", "空译文 = 空串(英文模式显示中文)") and ok
	var without := "关卡,发言人,场景,语句\n1-1,莉娅·科尔宾,工坊,第一句\n"
	var r2: Dictionary = _importer().parse_csv(without, {"1-1": "l01"})
	ok = check(r2.errors.is_empty() and (r2.levels["l01"].intro as DialogueRes).lines[0].text_en == "", "没有英文列也照常导入") and ok
	return ok


func test_unknown_episode_reported() -> bool:
	var r: Dictionary = _importer().parse_csv("关卡,发言人,语句\n9-9,莉娅,台词\n", {"1-1": "l01"})
	return check(not r.errors.is_empty() and r.levels.is_empty(), "目录外的「章-节」要报错且不导入")
