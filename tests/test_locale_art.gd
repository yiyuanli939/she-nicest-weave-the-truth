extends TestBase
## 英文占位美术图(tools/gen_locale_art.gd 出的 <名字>.en.png,按 project.godot translation_remaps 换图):
## 每张与原图同尺寸;笔记页收起时不许露出(x < CLOSED_PEEK + OPEN_X 无 alpha,同 test_art_alignment);
## 擦除框之外与原图逐点相同(工具没有伤到别处)、框内确有改动;.import 开 mipmap。
## 还没生成时(remaps 为空)这里全部跳过 —— 让引擎侧先落地。

## 原图 → 工具擦/写的区域(原图坐标;与 tools/gen_locale_art.gd JOBS 一致,外扩 8 px)
const REGIONS: Dictionary = {
	"res://assets/art/title/title.png": [Rect2i(0, 0, 2682, 180)],
	"res://assets/art/level/palette_bg.png": [Rect2i(232, 50, 212, 82)],
	"res://assets/art/level/win_popup.png": [Rect2i(340, 266, 536, 160)],
	"res://assets/art/story/base.png": [Rect2i(3340, 2037, 468, 79)],   # 英文 "Click to continue" 比中文宽,墨迹从 x 3361 起
}
const NOTEBOOK_REGIONS: Array = [Rect2i(600, 440, 2760, 500), Rect2i(1900, 1220, 850, 340)]   # 标题+正文带、批注区(imp_intro / false_elim)


static func _png(path: String) -> Image:
	var img := Image.new()
	return img if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK else null


func _pairs() -> Array:
	var out := []
	var remaps: Dictionary = ProjectSettings.get_setting(Loc.REMAPS_SETTING, {})
	for src: String in remaps:
		for alt in remaps[src]:
			var s := String(alt)
			out.append([src, s.substr(0, s.rfind(":"))])
	return out


func test_en_variants_same_size_and_mipmaps() -> bool:
	var ok := true
	for pr in _pairs():
		var a := _png(pr[0])
		var b := _png(pr[1])
		ok = check(a != null and b != null, "能读 %s / %s" % [pr[0], pr[1]]) and ok
		if a == null or b == null:
			continue
		ok = check(a.get_size() == b.get_size(), "%s 与原图同尺寸(%s vs %s)" % [pr[1], b.get_size(), a.get_size()]) and ok
		var imp := FileAccess.get_file_as_string(pr[1] + ".import")
		ok = check(imp.contains("mipmaps/generate=true"), "%s.import 开 mipmap" % pr[1]) and ok
	return ok


func test_notebook_en_pages_clear_left_of_peek() -> bool:
	var ok := true
	var limit := int(NotebookUI.CLOSED_PEEK + NotebookUI.OPEN_X)
	for pr in _pairs():
		if not String(pr[1]).contains("/notebook/"):
			continue
		var img := _png(pr[1])
		if img == null:
			continue
		ok = check(img.get_width() == 3840 and img.get_height() == 2160, "%s 3840×2160" % pr[1]) and ok
		var leak := false
		for y in range(0, img.get_height(), 4):
			for x in range(0, limit, 4):
				if img.get_pixel(x, y).a > 0.04:
					leak = true
					break
			if leak:
				break
		ok = check(not leak, "%s 收起时不露出(x < %d 无 alpha)" % [pr[1], limit]) and ok
	return ok


## 擦除框之外每 4 像素抽样必须与原图相同;框内至少有一处不同(证明工具确实跑过)
func test_en_variants_differ_only_inside_regions() -> bool:
	var ok := true
	for pr in _pairs():
		var a := _png(pr[0])
		var b := _png(pr[1])
		if a == null or b == null or a.get_size() != b.get_size():
			continue
		var regions: Array = REGIONS.get(pr[0], NOTEBOOK_REGIONS)
		var outside_diff := 0
		var inside_diff := 0
		for y in range(0, a.get_height(), 4):
			for x in range(0, a.get_width(), 4):
				if a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
					continue
				var inside := false
				for r: Rect2i in regions:
					if r.has_point(Vector2i(x, y)):
						inside = true
						break
				if inside:
					inside_diff += 1
				else:
					outside_diff += 1
		ok = check(outside_diff == 0, "%s 擦除框外与原图相同(框外差异 %d 点)" % [pr[1], outside_diff]) and ok
		ok = check(inside_diff > 0, "%s 擦除框内有改动" % pr[1]) and ok
	return ok
