extends TestBase
## 中英本地化守门：术语、人名、章节、笔记和 99 句正式剧情都必须有英文；
## 中文美术查找键保持原样。标题页语言按钮还要符合右上角、圆角半透明底的要求。


const TERMS: Dictionary = {
	"静语丝": "Hush Thread",
	"静语纹": "Hush Pattern",
	"静语织机": "Hush Loom",
	"并纹": "Joined Pattern",
	"岔纹": "Forked Pattern",
	"叠层纹": "Layered Pattern",
	"迭层纹": "Layered Pattern",
	"焦纹": "Scorched Pattern",
	"并织机": "Joining Machine",
	"拆股机": "Splitting Machine",
	"封程机": "Binding Machine",
	"引渡机": "Relay Machine",
	"岔纹机": "Forking Machine",
	"汇路机": "Convergence Machine",
	"溃散机": "Unraveling Machine",
	"诺拉·拉芙蒂": "Nora Lafferty",
	"莉娅·科尔宾": "Leah Corbin",
	"亚瑟·威客利夫": "Arthur Wycliffe",
}


func _set_en() -> void:
	(Engine.get_main_loop() as SceneTree).root.get_node("L10n").set_locale("en", false)


func _restore_zh() -> void:
	(Engine.get_main_loop() as SceneTree).root.get_node("L10n").set_locale("zh_CN", false)


func test_locale_normalization_and_switch_label() -> bool:
	var script: GDScript = load("res://game/localization.gd")
	var l10n := (Engine.get_main_loop() as SceneTree).root.get_node("L10n")
	var ok := check(script.normalize_locale("en_US") == "en" and script.normalize_locale("EN-gb") == "en",
			"英文地区码统一为 en")
	ok = check(script.normalize_locale("zh_CN") == "zh_CN" and script.normalize_locale("fr") == "zh_CN",
			"非英文回落中文") and ok
	l10n.set_locale("zh_CN", false)
	ok = check(l10n.switch_label() == "EN", "中文界面按钮显示 EN") and ok
	_set_en()
	ok = check(l10n.switch_label() == "中文", "英文界面按钮显示中文") and ok
	_restore_zh()
	return ok


func test_glossary_and_names_are_consistent() -> bool:
	_set_en()
	var ok := true
	for source: String in TERMS:
		ok = check(TranslationServer.translate(source) == TERMS[source], "%s → %s" % [source, TERMS[source]]) and ok
	ok = check(TranslationServer.translate("美术与策划:焰陶") == "Art & Design: CeramicWitch",
			"英文开发者署名使用 CeramicWitch") and ok
	_restore_zh()
	return ok


func test_all_level_and_notebook_text_has_english() -> bool:
	_set_en()
	var ok := true
	var cat := LevelCatalog.load_default()
	for ch: ChapterDef in cat.chapters:
		ok = check(TranslationServer.translate(ch.title) != ch.title, "章名有英文:%s" % ch.title) and ok
		for lv: LevelDef in ch.levels:
			ok = check(TranslationServer.translate(lv.title) != lv.title, "关名有英文:%s" % lv.title) and ok
	var nb := NotebookCatalog.load_default()
	for e: NotebookEntry in nb.entries:
		ok = check(TranslationServer.translate(e.title) != e.title, "笔记标题有英文:%s" % e.title) and ok
		ok = check(TranslationServer.translate(e.description) != e.description, "笔记正文有英文:%s" % e.title) and ok
	_restore_zh()
	return ok


func test_all_99_dialogue_lines_have_english() -> bool:
	_set_en()
	var count := 0
	var ok := true
	for lv: LevelDef in LevelCatalog.load_default().all_levels():
		for dlg: DialogueRes in [lv.intro_dialogue, lv.outro_dialogue]:
			if dlg == null:
				continue
			for line: DialogueLine in dlg.lines:
				count += 1
				ok = check(TranslationServer.translate(line.text) != line.text, "%s 第 %d 句有英文" % [lv.id, count]) and ok
				ok = check(TranslationServer.translate(StoryArt.display_name(line.speaker)) != StoryArt.display_name(line.speaker),
						"发言人有英文:%s" % line.speaker) and ok
	ok = check(count == 99, "正式剧情共 99 句(得 %d)" % count) and ok
	_restore_zh()
	return ok


func test_dialogue_box_uses_translated_text_for_typewriter() -> bool:
	_set_en()
	var tree := Engine.get_main_loop() as SceneTree
	var box := DialogueBox.new()
	tree.root.add_child(box)
	var line := DialogueLine.new()
	line.speaker = "诺拉·拉芙蒂"
	line.text = "那代价呢？"
	var dlg := DialogueRes.new()
	dlg.lines.append(line)
	box.play(dlg)
	var expected := TranslationServer.translate(line.text)
	var ok := check(box._speaker.text == "Nora Lafferty" and box._text.text == expected, "对话框写入实际英文")
	ok = check(box._text.get_total_character_count() == expected.length(), "打字机按英文长度计数") and ok
	tree.root.remove_child(box)
	box.free()
	_restore_zh()
	return ok


func test_language_button_style_and_english_menu_bounds() -> bool:
	_restore_zh()
	var menu := MainMenu.new()
	menu._add_language_button()
	var lang := menu._lang_btn
	var normal := lang.get_theme_stylebox("normal") as StyleBoxFlat
	var ok := check(lang.text == "EN", "中文界面语言按钮显示 EN")
	ok = check(lang.position.x + lang.size.x <= 3840.0 and lang.position.y >= 0.0, "语言按钮位于右上角画面内") and ok
	ok = check(normal != null and normal.bg_color.a < 1.0 and normal.corner_radius_top_left > 0,
			"语言按钮是圆角半透明矩形") and ok
	menu.free()

	_set_en()
	menu = MainMenu.new()
	menu._add_language_button()
	ok = check(menu._lang_btn.text == "中文", "英文界面语言按钮显示中文") and ok
	for i in 5:
		var b := menu._add_option(i, ["开始游戏", "重置进度", "开发者信息", "退出游戏", "设置"][i], func() -> void: pass)
		ok = check(b.position.x >= 0.0 and b.position.x + b.size.x <= 3840.0,
				"英文主菜单第 %d 项没有超出画面(%.0f..%.0f)" % [i + 1, b.position.x, b.position.x + b.size.x]) and ok
	menu.free()
	_restore_zh()
	return ok


func test_internal_art_keys_are_not_translated() -> bool:
	_set_en()
	var ok := true
	for key in ["工坊", "诺拉房间", "伦敦街上", "默认", "苦恼", "严肃", "惊讶"]:
		ok = check(TranslationServer.translate(key) == key, "内部美术键保持中文:%s" % key) and ok
	_restore_zh()
	return ok
