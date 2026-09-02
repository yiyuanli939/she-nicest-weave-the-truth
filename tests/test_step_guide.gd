extends TestBase
## 关内操作指引(StepGuide):优先级与"做过就不显示"、从会话提取事实、新上架判定、存档记忆。
## v1.1 后只剩 钉/放/拉 三步(错线自动断开、新仪器笔记自动弹出)。


func test_next_step_priority_and_done() -> bool:
	var f := {has_rack = true, machines = 0, wires = 0, unpinned = false, pinned = false, solved = false}
	var ok := check(StepGuide.next_step(f, {}) == &"place", "空棋盘先提示放仪器")
	ok = check(StepGuide.next_step(f, {"place": true}) == &"", "放过仪器、盘上没机可拉线 → 不提示(翻笔记不再是指引,笔记自动弹出)") and ok
	f.machines = 1
	ok = check(StepGuide.next_step(f, {"place": true}) == &"wire", "有仪器没线 → 拉线") and ok
	f.unpinned = true
	ok = check(StepGuide.next_step(f, {"place": true}) == &"pin", "有未钉口 → 钉优先于拉线") and ok
	var all_done := {"pin": true, "place": true, "wire": true}
	ok = check(StepGuide.next_step(f, all_done) == &"", "全做过 → 不显示") and ok
	f.solved = true
	ok = check(StepGuide.next_step(f, {}) == &"", "已通关不显示") and ok
	var l01 := {has_rack = false, machines = 0, wires = 0, unpinned = false, pinned = false, solved = false}
	ok = check(StepGuide.next_step(l01, {}) == &"wire", "没有仪器架的关(l01)直接提示拉线") and ok
	ok = check(StepGuide.next_step(l01, {"wire": true}) == &"", "l01 拉过线就没了") and ok
	ok = check(StepGuide.ORDER.size() == 3 and not StepGuide.TEXT.has(&"fix") and not StepGuide.TEXT.has(&"notebook"), "只剩三步,没有断线/翻笔记") and ok
	for step in StepGuide.ORDER:
		ok = check(StepGuide.TEXT.has(step) and StepGuide.TEXT[step] != "", "%s 有文案" % step) and ok
	ok = check(not (StepGuide.TEXT[&"pin"] as String).contains("标题栏"), "钉纹样文案不再指向标题栏(按钮在纹样旁)") and ok
	return ok


func test_newly_done_from_facts() -> bool:
	var got := StepGuide.newly_done({machines = 1, wires = 1, pinned = true})
	var ok := check(got.has(&"place") and got.has(&"wire") and got.has(&"pin") and got.size() == 3, "放/拉/钉都算做过: %s" % str(got))
	ok = check(StepGuide.newly_done({machines = 0, wires = 0}).is_empty(), "空棋盘什么都没做过") and ok
	return ok


func test_facts_of_session() -> bool:
	var s := ProofSession.new()
	var ok := check(s.setup([], "A > A") == "", "setup")
	var f := StepGuide.facts_of(s, true)
	ok = check(f.has_rack and f.machines == 0 and f.wires == 0 and not f.unpinned and not f.solved, "空盘事实") and ok
	var m := s.place_machine(&"imp_intro")
	f = StepGuide.facts_of(s, true)
	ok = check(f.machines == 1 and f.unpinned and not f.pinned, "封程机放上:假设口未钉") and ok
	ok = check(s.pin_hypothesis(m, 1, "A") == "", "钉 A") and ok
	f = StepGuide.facts_of(s, true)
	ok = check(f.pinned and not f.unpinned, "钉住后没有未钉口") and ok
	s.connect_wire(m, 1, m, 0)
	s.connect_wire(m, 0, s.goal_id, 0)
	f = StepGuide.facts_of(s, true)
	ok = check(f.wires == 2 and f.solved, "接线后通关") and ok
	s.free()
	return ok


func test_catalog_debut_rules() -> bool:
	var cat := LevelCatalog.load_default()
	var ok := check(cat.debut_rules(cat.find(&"l01")).is_empty(), "l01 无新仪器")
	var l02 := cat.debut_rules(cat.find(&"l02"))
	ok = check(l02.size() == 1 and l02[0] == &"and_intro", "l02 新上架并织机") and ok
	var l03 := cat.debut_rules(cat.find(&"l03"))
	ok = check(l03.size() == 1 and l03[0] == &"and_elim", "l03 新上架拆股机") and ok
	ok = check(cat.debut_rules(cat.find(&"l04")).is_empty() and cat.debut_rules(cat.find(&"l05")).is_empty(), "l04/l05 没有新仪器") and ok
	var l07 := cat.debut_rules(cat.find(&"l07"))
	ok = check(l07.size() == 1 and l07[0] == &"imp_intro", "l07 新上架封程机") and ok
	ok = check(cat.debut_rules(LevelDef.new()).is_empty(), "目录外的关 → 空") and ok
	return ok


func test_save_remembers_steps() -> bool:
	var sm := SaveManager.new()
	var ok := check(sm.mark_step_done(&"place") and not sm.mark_step_done(&"place"), "首次记下返回 true,再记返回 false")
	sm.save()
	var sm2 := SaveManager.open()
	ok = check(sm2.is_step_done(&"place") and not sm2.is_step_done(&"wire"), "读档保留已做操作") and ok
	var f := {has_rack = true, machines = 0, wires = 0}
	ok = check(StepGuide.next_step(f, sm2.steps) == &"", "存档里的字符串键能挡住 StringName 步骤") and ok
	sm2.wipe()
	ok = check(not SaveManager.open().is_step_done(&"place"), "重置进度清掉指引记忆") and ok
	return ok
