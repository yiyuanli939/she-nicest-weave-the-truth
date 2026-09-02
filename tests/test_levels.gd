extends TestBase
## 关卡/笔记数据校验:catalog 载入、公式可解析、规则存在、章名关名按美术规范、笔记 = 七台仪器。


func test_catalog_loads_16_levels() -> bool:
	var cat := LevelCatalog.load_default()
	return check(cat != null, "catalog.tres 应能加载") \
		and check(cat.chapters.size() == 4, "4 章 (得 %d)" % cat.chapters.size()) \
		and check(cat.all_levels().size() == 16, "16 关 (得 %d)" % cat.all_levels().size())


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


## 诺拉的笔记 = 七台仪器各一条说明,顺序同仪器架,全量常驻(不解锁)
## 诺拉的笔记 = 七台仪器各一张整页图(标题/正文全画在图里,引擎侧无文案)
func test_notebook_is_machine_manual() -> bool:
	var nb := NotebookCatalog.load_default()
	var ok := check(nb != null and nb.entries.size() == Rules.all_ids().size(), "笔记条数 = 仪器数")
	var expected := [&"and_intro", &"and_elim", &"imp_intro", &"imp_elim", &"or_intro", &"or_elim", &"false_elim"]
	for i in expected.size():
		var e := nb.entry(expected[i])
		ok = check(e != null, "仪器 %s 应有笔记条目" % expected[i]) and ok
		if e != null:
			ok = check(e.id == nb.entries[i].id, "条目顺序应同仪器架:%s" % expected[i]) and ok
			ok = check(e.image != "" and ResourceLoader.exists(e.image), "%s 整页图存在:%s" % [expected[i], e.image]) and ok
	return ok


## 关卡对话(进关前 intro / 通关后 outro)的场景/人物/表情都要是登记表里的合法值
func test_dialogue_lines_reference_registered_art() -> bool:
	var cat := LevelCatalog.load_default()
	var ok := true
	for lv in cat.all_levels():
		for dlg: DialogueRes in [lv.intro_dialogue, lv.outro_dialogue]:
			if dlg == null:
				continue
			for line: DialogueLine in dlg.lines:
				ok = check(line.scene == "" or StoryArt.SCENES.has(line.scene), "%s 场景 %s" % [lv.id, line.scene]) and ok
				ok = check(line.left_char == "" or (StoryArt.CHARACTERS.has(line.left_char) and not StoryArt.is_nora(line.left_char)), "%s 左侧人物 %s" % [lv.id, line.left_char]) and ok
				ok = check(StoryArt.EXPRESSIONS.has(line.left_expr) and StoryArt.EXPRESSIONS.has(line.nora_expr), "%s 表情" % lv.id) and ok
	# 剧情表注意事项②:4-3 是通关后剧情 → 最后一关必须有 outro、没有 intro
	var last: LevelDef = cat.all_levels()[-1]
	ok = check(last.outro_dialogue != null and not last.outro_dialogue.lines.is_empty(), "l16 有通关后剧情(4-3)") and ok
	ok = check(last.intro_dialogue == null or last.intro_dialogue.lines.is_empty(), "l16 无进关对话") and ok
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



## 仪器按关上架(2026-09-02 编排):l01 一台都没有,之后逐关累计;每关解法只能用本关架上的仪器
func test_rules_unlock_per_level() -> bool:
	var cat := LevelCatalog.load_default()
	var debut: Dictionary = {   # 本关新上架的仪器
		&"l02": &"and_intro", &"l03": &"and_elim", &"l06": &"imp_elim", &"l07": &"imp_intro",
		&"l11": &"or_intro", &"l12": &"or_elim", &"l14": &"false_elim",
	}
	var shelved: Array[StringName] = []
	var ok := check(cat.all_levels()[0].allowed_rules.is_empty(), "l01 一台仪器都不上架")
	for lv in cat.all_levels():
		if debut.has(lv.id):
			shelved.append(debut[lv.id])
		ok = check(lv.allowed_rules == shelved, "%s 架上仪器应为 %s,得 %s" % [lv.id, str(shelved), str(lv.allowed_rules)]) and ok
		var sol: Dictionary = LevelSolutions.DATA.get(lv.id, {})
		ok = check(not sol.is_empty(), "%s 缺脚本化解法" % lv.id) and ok
		for r in sol.get("m", []):
			ok = check(lv.allowed_rules.has(r), "%s 解法用了未上架的 %s" % [lv.id, r]) and ok
	ok = check(shelved.size() == Rules.all_ids().size(), "七台仪器到末关全部上架") and ok
	return ok


## 2026-09-02 编排:第一章第三纹是新加的裸拆股关(无剧情、直进棋盘),原第三/四纹后移;
## 第二章 2-2/2-3 只对调题目(2-2 = 封程裸机),剧情按「章-节」位置不动;「章-节」映射随目录变
func test_reordered_levels_2026_09() -> bool:
	var cat := LevelCatalog.load_default()
	var l03 := cat.find(&"l03")
	var l07 := cat.find(&"l07")
	var l08 := cat.find(&"l08")
	var ok := check(cat.chapters[0].levels.size() == 5 and cat.chapters[1].levels.size() == 5
			and cat.chapters[2].levels.size() == 3 and cat.chapters[3].levels.size() == 3, "各章 5/5/3/3 关")
	ok = check(l03.assumptions.size() == 1 and l03.assumptions[0] == "A & B" and l03.goal == "A"
			and l03.title == "第三纹", "l03 = A & B ⊢ A,第三纹") and ok
	ok = check(l03.intro_dialogue == null or l03.intro_dialogue.lines.is_empty(), "l03 无进关剧情") and ok
	ok = check(cat.find(&"l04").goal == "B & A" and cat.find(&"l04").title == "第四纹", "原第三纹后移为 l04 第四纹") and ok
	ok = check(l07.goal == "A > A" and l07.assumptions.is_empty() and l07.title == "第二纹", "2-2 = ⊢ A > A(封程裸机)") and ok
	ok = check(l08.goal == "A > C" and l08.title == "第三纹", "2-3 = A > B, B > C ⊢ A > C") and ok
	ok = check(cat.find(&"l11").robot_cue_on_win == "panic" and cat.chapter_of(cat.find(&"l11")) == 2
			and cat.find(&"l11").title == "第一纹", "3-1 = l11,通关演出 panic") and ok
	var ep: Dictionary = load("res://tools/import_dialogue.gd").episode_map()
	ok = check(ep.get("1-3") == "l03" and ep.get("1-5") == "l05" and ep.get("2-1") == "l06"
			and ep.get("3-1") == "l11" and ep.get("4-3") == "l16" and ep.size() == 16, "章-节 → id 映射随目录") and ok
	return ok


## 剧情表 information/dialogue.csv 与 .tres 逐句一致(关卡重排时剧情按「章-节」位置留在原处,靠这条盯着不错位)
func test_tres_dialogue_matches_csv() -> bool:
	var importer: GDScript = load("res://tools/import_dialogue.gd")
	var csv := FileAccess.get_file_as_string("res://information/dialogue.csv")
	var r: Dictionary = importer.parse_csv(csv, importer.episode_map())
	var ok := check((r.errors as Array).is_empty(), "剧情表无错误: %s" % str(r.errors))
	var cat := LevelCatalog.load_default()
	for lv in cat.all_levels():
		var got: Dictionary = r.levels.get(String(lv.id), {intro = null, outro = null})
		for slot in ["intro", "outro"]:
			var want: DialogueRes = got[slot]
			var have: DialogueRes = lv.intro_dialogue if slot == "intro" else lv.outro_dialogue
			var want_n: int = want.lines.size() if want != null else 0
			var have_n: int = have.lines.size() if have != null else 0
			ok = check(want_n == have_n, "%s %s 句数:表 %d / tres %d" % [lv.id, slot, want_n, have_n]) and ok
			for i in mini(want_n, have_n):
				ok = check(want.lines[i].text == have.lines[i].text and want.lines[i].speaker == have.lines[i].speaker,
						"%s %s 第 %d 句与表不同" % [lv.id, slot, i + 1]) and ok
	return ok


## 关卡编排版本:旧版存档(无 layout 字段 = 1)的 boards 是别的题目的棋盘 → 读档丢弃 boards,保留 solved 与 settings
func test_save_layout_version_drops_stale_boards() -> bool:
	var f := FileAccess.open(SaveManager.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({solved = {"l05": true}, boards = {"l05": {"graph": {}, "positions": {}}}, settings = {"robot_turn": "left"}}))
	f.close()
	var sm := SaveManager.open()
	var ok := check(sm.is_solved(&"l05") and sm.settings.get("robot_turn") == "left", "旧档 solved/settings 保留") \
		and check(sm.board_state(&"l05").is_empty(), "旧编排的棋盘丢弃")
	sm.set_board_state(&"l05", {"graph": {}, "positions": {}})
	sm.save()
	var sm2 := SaveManager.open()
	ok = check(not sm2.board_state(&"l05").is_empty(), "新档带 layout 版本,棋盘照读") and ok
	sm2.wipe()
	return ok
