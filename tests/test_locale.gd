extends TestBase
## 英文版(game/loc.gd):翻译表 locale/ui.csv 完整(键唯一、zh = 键、en 非空且全在字体里)、
## 代码/关卡里每条玩家可见的中文都在表里(否则英文模式漏中文)、切 locale 往返、按语言换图的表、台词英文列。

const UI_CSV := "res://locale/ui.csv"
## 英文文案只许 ASCII 加这几个排版符(站酷小薇体没有重音字母、没有「·」;弯引号 “ ” ‘ ’ 在这套字体里是全角字形、两边留大空,英文一律用直引号)
const EN_EXTRA := ["–", "—", "…"]
## 扫字面量的目录(test_theme 的五个 + 逻辑/接口/关卡层)
const SCAN_DIRS := ["res://ui", "res://board", "res://pattern", "res://narrative", "res://game", "res://api", "res://logic", "res://levels"]
## 含汉字但不是显示文本的字面量:美术登记键 / 表情键 / 内部名 / 量字形用的字 / 语音唤醒短语 / 只进日志的格式串
const EXCLUDE := [
	"默认", "苦恼", "严肃", "惊讶", "工坊", "宿舍", "街景", "伦敦街上", "诺拉房间", "诺拉", "莉娅", "亚瑟", "无", "孔", "字",
	"请指导我", "指导我", "请帮帮我", "帮帮我",
	"立绘 %s(%s)", "遮罩 %s", "场景 %s",
	"假设「%s」解析失败: %s", "目标「%s」解析失败: %s", "解析失败: ",
	"空输入", "位置 %d 处有多余内容: %s", "位置 %d 处缺少公式", "位置 %d 处缺少右括号", "位置 %d 处的记号无法识别: %s",
	"第%s纹", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
]


func _rows() -> Array:
	var importer: GDScript = load("res://tools/import_dialogue.gd")
	var rows: Array = importer.split_rows(FileAccess.get_file_as_string(UI_CSV))
	return rows


func _table() -> Dictionary:
	var out := {}
	var rows := _rows()
	for i in range(1, rows.size()):
		var r: Array = rows[i]
		if r.size() >= 3:
			out[String(r[0])] = String(r[2])
	return out


static func _has_han(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x4E00 and c <= 0x9FFF:
			return true
	return false


static func en_text_ok(s: String) -> bool:
	for i in s.length():
		if s.unicode_at(i) >= 128 and not EN_EXTRA.has(s[i]):
			return false
	return true


func test_ui_csv_well_formed() -> bool:
	var rows := _rows()
	var ok := check(rows.size() > 100 and rows[0].size() == 3 and rows[0][0] == "keys" and rows[0][1] == "zh" and rows[0][2] == "en",
			"表头 keys,zh,en(得 %s)" % str(rows[0] if not rows.is_empty() else []))
	var seen := {}
	for i in range(1, rows.size()):
		var r: Array = rows[i]
		if r.is_empty() or "".join(r).strip_edges() == "":
			continue
		ok = check(r.size() == 3, "第 %d 行三列(得 %d)" % [i + 1, r.size()]) and ok
		if r.size() < 3:
			continue
		var key := String(r[0])
		ok = check(key != "" and not seen.has(key), "第 %d 行键非空且唯一:%s" % [i + 1, key]) and ok
		seen[key] = true
		ok = check(String(r[1]) == key, "第 %d 行 zh 列 = 键(fallback 是 zh,zh 列缺了英文模式会漏成英文):%s" % [i + 1, key]) and ok
		var en := String(r[2])
		ok = check(en != "" and en != key, "第 %d 行 en 非空且已翻:%s" % [i + 1, key]) and ok
		ok = check(en_text_ok(en) and not _has_han(en), "第 %d 行 en 只用 ASCII + – — …(字体没有重音字母;弯引号是全角,用直引号):%s" % [i + 1, en]) and ok
		ok = check(key.count("%s") == en.count("%s") and key.count("%d") == en.count("%d"), "第 %d 行占位符个数一致:%s" % [i + 1, key]) and ok
	return ok


## 代码与关卡数据里每条含汉字的字面量都要么是翻译键、要么在 EXCLUDE(内部键);否则英文模式会漏出中文
func test_every_visible_chinese_literal_is_translated() -> bool:
	var table := _table()
	var re := RegEx.create_from_string("\"[^\"]*\"")
	var ok := true
	for dir in SCAN_DIRS:
		for fname in DirAccess.get_files_at(dir):
			if not fname.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir + "/" + fname)
			var lines := src.split("\n")
			for li in lines.size():
				var line := lines[li]
				var stripped := line.strip_edges()
				if stripped.begins_with("#") or stripped.begins_with("##"):
					continue
				var code := line.get_slice("#", 0)
				for skip in ["push_warning", "push_error", "assert(", "print(", "printerr(", "print_rich("]:
					if code.contains(skip):
						code = ""
				for m in re.search_all(code):
					var lit := m.get_string().substr(1, m.get_string().length() - 2).c_unescape()   # 源码里的 \n 是真换行
					if not _has_han(lit) or EXCLUDE.has(lit):
						continue
					ok = check(table.has(lit), "%s/%s:%d 中文字面量不在 locale/ui.csv:%s" % [dir, fname, li + 1, lit]) and ok
	# 关卡数据里的显示文本:章名 / 关名 / 发言人全名
	var cat := LevelCatalog.load_default()
	for ch in cat.chapters:
		ok = check(table.has(ch.title), "章名在表里:%s" % ch.title) and ok
	for lv in cat.all_levels():
		ok = check(table.has(lv.title), "关名在表里:%s" % lv.title) and ok
		for dlg: DialogueRes in [lv.intro_dialogue, lv.outro_dialogue]:
			if dlg == null:
				continue
			for line: DialogueLine in dlg.lines:
				ok = check(table.has(StoryArt.display_name(line.speaker)), "%s 发言人显示名在表里:%s" % [lv.id, line.speaker]) and ok
	for who: String in StoryArt.CHARACTERS:
		ok = check(table.has(StoryArt.CHARACTERS[who].full_name), "角色全名在表里:%s" % who) and ok
	for id: StringName in Rules.all_ids():
		ok = check(table.has(Rules.get_rule(id).cn_name), "仪器名在表里:%s" % id) and ok
	return ok


func test_locale_round_trip() -> bool:
	var table := _table()
	var ok := check(Loc.normalize("en") == "en" and Loc.normalize("zh") == "zh" and Loc.normalize("fr") == "zh" and Loc.normalize(null) == "zh", "normalize:只认 en,其余 zh")
	ok = check(Loc.next("zh") == "en" and Loc.next("en") == "zh" and Loc.next("xx") == "en", "next 来回切") and ok
	ok = check(Loc.chars_per_sec("zh") < Loc.chars_per_sec("en"), "英文打字机更快(字符数约两倍)") and ok
	Loc.apply("en")
	ok = check(TranslationServer.get_locale() == "en" and Loc.current() == "en" and Loc.is_en(), "apply(en)") and ok
	var n := 0
	for key: String in table:
		if TranslationServer.translate(key) != table[key]:
			ok = check(false, "en 查表:%s → %s(得 %s)" % [key, table[key], TranslationServer.translate(key)]) and ok
		n += 1
	ok = check(TranslationServer.translate("不在表里的串") == "不在表里的串", "缺译原样返回") and ok
	Loc.apply("zh")
	ok = check(TranslationServer.get_locale() == "zh" and not Loc.is_en(), "apply(zh)") and ok
	for key: String in table:
		if TranslationServer.translate(key) != key:
			ok = check(false, "zh 查表 = 键:%s(得 %s)" % [key, TranslationServer.translate(key)]) and ok
	ok = check(n > 100, "表里有 %d 条" % n) and ok
	ok = check(String(ProjectSettings.get_setting("internationalization/locale/fallback", "")) == "zh", "fallback 必须是 zh(Godot 默认 en:缺译会漏成英文)") and ok
	var line := DialogueLine.new()
	line.text = "中"
	ok = check(Loc.line_text(line, "en") == "中" and Loc.line_text(line, "zh") == "中", "没译文:英文模式仍显示中文") and ok
	line.text_en = "EN"
	ok = check(Loc.line_text(line, "en") == "EN" and Loc.line_text(line, "zh") == "中", "有译文按语言取") and ok
	return ok


## 按语言换图:translation_remaps 每条的原图与英文图都存在;assets/art 下每张 .en.png 都登记了
func test_art_remaps_consistent() -> bool:
	var remaps: Dictionary = ProjectSettings.get_setting(Loc.REMAPS_SETTING, {})
	var ok := true
	var listed := {}
	for src: String in remaps:
		ok = check(ResourceLoader.exists(src), "换图原图存在:%s" % src) and ok
		for alt in remaps[src]:
			var s := String(alt)
			ok = check(s.ends_with(":en") and s.get_slice(":en", 0) == src.get_basename() + ".en." + src.get_extension(),
					"备选命名 <原名>.en.<后缀>:en(得 %s)" % s) and ok
			var p := s.substr(0, s.rfind(":"))
			ok = check(ResourceLoader.exists(p), "英文图存在:%s" % p) and ok
			listed[p] = true
		ok = check(Loc.localized_path(src, "en") != src and Loc.localized_path(src, "zh") == src, "localized_path 按语言取:%s" % src) and ok
	for p in _files_under("res://assets/art"):
		if p.ends_with(".en.png"):
			ok = check(listed.has(p), "%s 要登记进 translation_remaps" % p) and ok
	return ok


## 台词英文列:一旦开始填就得全填(英文模式不能一半中文一半英文);英文只用允许的字符
func test_dialogue_english_lines() -> bool:
	var cat := LevelCatalog.load_default()
	var total := 0
	var filled := 0
	var ok := true
	for lv in cat.all_levels():
		for dlg: DialogueRes in [lv.intro_dialogue, lv.outro_dialogue]:
			if dlg == null:
				continue
			for line: DialogueLine in dlg.lines:
				total += 1
				if line.text_en != "":
					filled += 1
					ok = check(en_text_ok(line.text_en) and not _has_han(line.text_en), "%s 英文台词只用 ASCII + 排版符:%s" % [lv.id, line.text_en]) and ok
	ok = check(total > 100, "共 %d 句" % total) and ok
	if filled > 0:
		ok = check(filled == total, "英文台词要么全空要么全填(填了 %d / %d)" % [filled, total]) and ok
	return ok


static func _files_under(dir: String) -> Array[String]:
	var out: Array[String] = []
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files_under(dir + "/" + d))
	for f in DirAccess.get_files_at(dir):
		out.append(dir + "/" + f)
	return out
