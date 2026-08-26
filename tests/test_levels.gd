extends TestBase
## 关卡/笔记本数据校验:catalog 载入、公式可解析、规则存在、解锁链完整。


func test_catalog_loads_17_levels() -> bool:
	var cat := LevelCatalog.load_default()
	return check(cat != null, "catalog.tres 应能加载") \
		and check(cat.chapters.size() == 5, "5 章 (得 %d)" % cat.chapters.size()) \
		and check(cat.all_levels().size() == 17, "17 关 (得 %d)" % cat.all_levels().size())


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


func test_notebook_unlocks_exist() -> bool:
	var nb := NotebookCatalog.load_default()
	var cat := LevelCatalog.load_default()
	var ok := check(nb != null and nb.entries.size() == 5, "笔记本 5 条")
	for lv in cat.all_levels():
		for entry_id in lv.notebook_unlocks:
			ok = check(nb.entry(entry_id) != null, "%s 解锁了不存在的条目 %s" % [lv.id, entry_id]) and ok
	for e in nb.entries:
		if e.demo_formula != "":
			ok = check(FormulaParser.parse(e.demo_formula) != null, "笔记 %s 公式坏" % e.id) and ok
	return ok


func test_save_manager_roundtrip() -> bool:
	var sm := SaveManager.new()
	sm.mark_solved(&"l01")
	sm.set_board_state(&"l01", {"graph": {}, "positions": {}})
	sm.unlock_notebook(&"notebook_and")
	var dup := check(not sm.unlock_notebook(&"notebook_and"), "重复解锁应返回 false")
	sm.save()
	var sm2 := SaveManager.open()
	var ok := check(sm2.is_solved(&"l01"), "读档 solved") \
		and check(sm2.notebook.has("notebook_and"), "读档 notebook") \
		and check(not sm2.board_state(&"l01").is_empty(), "读档棋盘")
	sm2.wipe()
	var sm3 := SaveManager.open()
	return dup and ok and check(not sm3.is_solved(&"l01"), "wipe 生效")
