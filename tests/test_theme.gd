extends TestBase
## 美术规范:全部文字用站酷小薇体;UI 源码里的字面量不得含该字体没有的符号(否则会掉到系统字体)。
## 例外:「·」(人名分隔点,美术自己的写法)允许走系统兜底。

const MISSING_IN_FONT := ["☠", "◌", "✂", "📌", "▶", "✓", "🔒", "∧", "∨", "→", "⊥", "←", "↑", "↓", "①", "②", "③"]
const SCAN_DIRS := ["res://ui", "res://board", "res://pattern", "res://narrative", "res://game"]


func test_theme_uses_art_font() -> bool:
	var theme: Theme = load("res://theme/main_theme.tres")
	var ok := check(theme != null and theme.default_font != null, "主题有默认字体")
	if not ok:
		return false
	var f := theme.default_font
	var base: Font = f.base_font if f is FontVariation else f
	return check(base != null and base.resource_path.contains("ZCOOLXiaoWei"), "默认字体 = 站酷小薇体,得 %s" % (base.resource_path if base else "null")) \
		and check(not f.fallbacks.is_empty(), "有系统字体兜底") \
		and check(theme.default_font_size == 48, "默认字号 48(4K 逻辑视口)")


## 跨平台保证:所有玩家可见文字(UI 源码字面量 + 关卡/笔记/介绍卡 .tres)的每个字符
## 都必须在打包字体里 —— 否则掉到系统兜底字体(mac 苹方 / Windows 雅黑),两端观感不一致,
## 兜底也缺时就是方块。
## ALLOWED_FALLBACK = 故意走系统兜底的字符(两端系统字体都有):
##   「·」人名分隔点;「回」站酷小薇体的该字形是实心块坏字形,已用 tools/fix_font_glyphs.py 剥离。
const ALLOWED_FALLBACK := ["·", "回"]


func test_all_visible_text_in_bundled_font() -> bool:
	var font: FontFile = load("res://assets/fonts/ZCOOLXiaoWei-Regular.ttf")
	if not check(font != null, "打包字体能加载"):
		return false
	var chars: Dictionary = {}   # 字符 -> 首个出处
	var re := RegEx.create_from_string("\"[^\"]*\"")
	for dir in SCAN_DIRS:
		for fname in DirAccess.get_files_at(dir):
			if not fname.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir + "/" + fname)
			for line in src.split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				for m in re.search_all(line.get_slice("#", 0)):
					_collect_chars(m.get_string(), dir + "/" + fname, chars)
	for dir in ["res://levels/data", "res://narrative/data"]:
		for fname in DirAccess.get_files_at(dir):
			if fname.ends_with(".tres"):
				_collect_chars(FileAccess.get_file_as_string(dir + "/" + fname), dir + "/" + fname, chars)
	var ok := true
	for c: String in chars:
		if c.unicode_at(0) < 128 or ALLOWED_FALLBACK.has(c):
			continue
		ok = check(font.has_char(c.unicode_at(0)),
				"打包字体缺「%s」(U+%04X),首见于 %s" % [c, c.unicode_at(0), chars[c]]) and ok
	# 坏字形剥离必须生效:回 不许再由打包字体渲染(它的字形是实心块)
	ok = check(not font.has_char("回".unicode_at(0)), "「回」应已从打包字体剥离(走系统兜底)") and ok
	return ok


func _collect_chars(text: String, src: String, chars: Dictionary) -> void:
	for i in text.length():
		if not chars.has(text[i]):
			chars[text[i]] = src


## 只查字符串字面量(注释里的箭头等不会显示给玩家)
func test_ui_sources_avoid_glyphs_missing_from_font() -> bool:
	var ok := true
	var re := RegEx.create_from_string("\"[^\"]*\"")
	for dir in SCAN_DIRS:
		for fname in DirAccess.get_files_at(dir):
			if not fname.ends_with(".gd"):
				continue
			var src := FileAccess.get_file_as_string(dir + "/" + fname)
			for line in src.split("\n"):
				var code := line.get_slice("#", 0) if not line.strip_edges().begins_with("#") else ""
				for m in re.search_all(code):
					for sym in MISSING_IN_FONT:
						ok = check(not m.get_string().contains(sym), "%s/%s 字面量含字体没有的符号 %s:%s" % [dir, fname, sym, m.get_string()]) and ok
	return ok
