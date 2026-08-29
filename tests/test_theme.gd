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
