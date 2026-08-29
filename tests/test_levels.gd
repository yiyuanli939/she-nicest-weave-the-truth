extends TestBase
## 关卡/笔记数据校验:catalog 载入、公式可解析、规则存在、章名关名按美术规范、笔记 = 七台仪器。


func test_catalog_loads_15_levels() -> bool:
	var cat := LevelCatalog.load_default()
	return check(cat != null, "catalog.tres 应能加载") \
		and check(cat.chapters.size() == 4, "4 章 (得 %d)" % cat.chapters.size()) \
		and check(cat.all_levels().size() == 15, "15 关 (得 %d)" % cat.all_levels().size())


func test_levels_wellformed() -> bool:
	var cat := LevelCatalog.load_default()
	var ok := true
	var seen: Dictionary = {}
	for lv in cat.all_levels():
		ok = check(not seen.has(lv.id), "关卡 id 重复: %s" % lv.id) and ok
		seen[lv.id] = true
		ok = check(FormulaParser.parse(lv.goal) != null, "%s 目标解析: %s" % [lv.id, lv.goal]) and ok
		for a in lv.assumptions:
			ok = check(FormulaParser.parse(a) != null, "%s 假设解析: %s" % [lv.id, a]) and ok
		for r in lv.allowed_rules:
			ok = check(Rules.get_rule(r) != null, "%s 引用未知仪器: %s" % [lv.id, r]) and ok
		ok = check(not lv.atoms.is_empty(), "%s atoms 为空" % lv.id) and ok
		ok = check(lv.title != "", "%s 缺标题" % lv.id) and ok
	return ok


func test_setup_every_level() -> bool:
	var cat := LevelCatalog.load_default()
	var ok := true
	for lv in cat.all_levels():
		var s := ProofSession.new()
		var err := s.setup(lv.assumptions, lv.goal)
		ok = check(err == "", "%s setup 失败: %s" % [lv.id, err]) and ok
		s.free()
	return ok


## 美术规范:章名「第N章 X」、关名「第N纹」且章内从「第一纹」起计
func test_titles_follow_art_spec() -> bool:
	var cat := LevelCatalog.load_default()
	var ok := true
	var expected_ch := ["第一章 并纹", "第二章 叠层纹", "第三章 岔纹", "第四章 焦纹"]
	for i in cat.chapters.size():
		ok = check(cat.chapters[i].title == expected_ch[i], "章名 %s" % cat.chapters[i].title) and ok
		var nums := ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
		for j in cat.chapters[i].levels.size():
			var lv: LevelDef = cat.chapters[i].levels[j]
			ok = check(lv.title == "第%s纹" % nums[j], "%s 关名应为第%s纹,得 %s" % [lv.id, nums[j], lv.title]) and ok
	return ok


## 织者笔记 = 七台仪器各一条说明,顺序同仪器架,全量常驻(不解锁)
func test_notebook_is_machine_manual() -> bool:
	var nb := NotebookCatalog.load_default()
	var ok := check(nb != null and nb.entries.size() == Rules.all_ids().size(), "笔记条数 = 仪器数")
	var expected := [&"and_intro", &"and_elim", &"imp_intro", &"imp_elim", &"or_intro", &"or_elim", &"false_elim"]
	for i in expected.size():
		var e := nb.entry(expected[i])
		ok = check(e != null, "仪器 %s 应有笔记条目" % expected[i]) and ok
		if e != null:
			ok = check(e.id == nb.entries[i].id, "条目顺序应同仪器架:%s" % expected[i]) and ok
			ok = check(e.title != "" and e.body != "", "%s 标题/正文不为空" % expected[i]) and ok
			for sym in ["∧", "∨", "→", "⊥", "?P", "?Q"]:
				ok = check(not e.body.contains(sym), "%s 正文不得含逻辑符号 %s" % [expected[i], sym]) and ok
	return ok


## 占位对话的场景/人物/表情都要是登记表里的合法值(正式台词也走同一校验)
func test_dialogue_lines_reference_registered_art() -> bool:
	var cat := LevelCatalog.load_default()
	var ok := true
	for lv in cat.all_levels():
		if lv.intro_dialogue == null:
			continue
		for line: DialogueLine in lv.intro_dialogue.lines:
			ok = check(line.scene == "" or StoryArt.SCENES.has(line.scene), "%s 场景 %s" % [lv.id, line.scene]) and ok
			ok = check(line.left_char == "" or (StoryArt.CHARACTERS.has(line.left_char) and not StoryArt.is_nora(line.left_char)), "%s 左侧人物 %s" % [lv.id, line.left_char]) and ok
			ok = check(StoryArt.EXPRESSIONS.has(line.left_expr) and StoryArt.EXPRESSIONS.has(line.nora_expr), "%s 表情" % lv.id) and ok
	return ok


func test_save_manager_roundtrip() -> bool:
	var sm := SaveManager.new()
	sm.mark_solved(&"l01")
	sm.set_board_state(&"l01", {"graph": {}, "positions": {}})
	sm.save()
	var sm2 := SaveManager.open()
	var ok := check(sm2.is_solved(&"l01"), "读档 solved") \
		and check(not sm2.board_state(&"l01").is_empty(), "读档棋盘")
	sm2.wipe()
	var sm3 := SaveManager.open()
	return ok and check(not sm3.is_solved(&"l01"), "wipe 生效")

