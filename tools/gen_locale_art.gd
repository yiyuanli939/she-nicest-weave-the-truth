extends SceneTree
## 英文占位美术图(2026-09-03 用户选定「程序生成英文占位图」):11 张烧了中文的美术图,把中文墨迹擦掉、用站酷小薇体把英文画上去,
## 出 <名字>.en.png(+ 复制原 .import 保住 mipmap),游戏按 project.godot translation_remaps 在英文模式换图。
## 美术以后交英文图:直接覆盖 <名字>.en.png 即可(尺寸须与原图一致,tests/test_locale_art.gd 盯)。
##   perl -e 'alarm 180; exec @ARGV' "$GODOT" --path . --script res://tools/gen_locale_art.gd [-- --measure] [-- 名字…]
## **必须带窗口跑**(--headless 是 dummy 渲染器,SubViewport 出不了图);先 --check-only 过语法。
##   -- --measure   只打印每张图探测到的中文墨迹框(与 JOBS 里的擦除框对照),不写文件
##   -- title win   只做这几张(JOBS 的 tag)
## 做法:Image API 擦(fill_rect / 透明页清 alpha;imp_intro 批注压着机器底边,擦完用左半边镜像补回),
## 英文用 Label 放进透明 3840×2160 SubViewport 离屏渲染(同 tools/shot_4k.gd,与游戏同一栅格器),按墨迹包围盒贴到量好的位置;
## 每张先探测中文墨迹框,不在擦除框内就报错停下(美术换了图再跑会自己发现)。
## 笔记页英文文案在 locale/notebook_en.gd;其余英文与 locale/ui.csv 一致(Woven! / Rack / Click to continue)。

const FONT_PATH := "res://assets/fonts/ZCOOLXiaoWei-Regular.ttf"
const VP_SIZE := Vector2i(3840, 2160)
const CLEAR := Color(0, 0, 0, 0)
const PLAQUE := Color("7F5E5E")            # 仪器架 / 通关弹窗牌子的平底色
const GOLD_RACK := Color("C89A2F")
const GOLD_WIN := Color("D1A94D")
const INK_BASE := Color("654238")
const NB_TITLE := Color("644545")          # 笔记标题 / 批注色
const NB_BODY := Color("A3472E")           # 笔记正文色
const NB_TITLE_CENTER := Vector2(1911, 507)   # 中文标题墨迹中心(行 463–551)
const NB_TITLE_SIZE := 116
const NB_BODY_LEFT := 660
const NB_BODY_TOP := 640
const NB_BODY_WRAP := 2660
const NB_BODY_SIZES := [64, 60, 56, 52]   # 字号阶梯:正文底部离插图顶 ≥ 16 px
const NB_NOTE_SIZE := 56
## 每张图:src / erase(擦除框 + 颜色)/ detect(探测:search 框 + 判色)/ patch / texts;笔记页由 _notebook_job 生成
const JOBS: Array = [
	{tag = "title", src = "res://assets/art/title/title.png",
		erase = [[Rect2i(0, 0, 2682, 172), CLEAR]],
		detect = {search = Rect2i(0, 0, 2682, 186), kind = "alpha"}, texts = []},
	{tag = "palette", src = "res://assets/art/level/palette_bg.png",
		erase = [[Rect2i(240, 58, 197, 67), PLAQUE]],
		detect = {search = Rect2i(238, 56, 201, 71), kind = "gold"},
		texts = [{text = "Rack", size = 60, color = GOLD_RACK, anchor = "center", at = Vector2(337, 92)}]},
	{tag = "win", src = "res://assets/art/level/win_popup.png",
		erase = [[Rect2i(348, 274, 521, 145), PLAQUE]],
		detect = {search = Rect2i(346, 272, 525, 149), kind = "gold"},
		texts = [{text = "Woven!", size = 176, color = GOLD_WIN, anchor = "center", at = Vector2(607, 346)}]},
	{tag = "base", src = "res://assets/art/story/base.png",
		erase = [[Rect2i(3440, 2045, 361, 64), Color.WHITE]],
		detect = {search = Rect2i(3438, 2043, 365, 68), kind = "dark"},
		texts = [{text = "Click to continue", size = 60, color = INK_BASE, anchor = "topright", at = Vector2(3788, 2053)}]},
]
## 笔记页:插图顶(标题 + 正文带擦到它上面 6 px)与批注擦除框
const NOTEBOOK: Dictionary = {
	&"and_intro": {illus_top = 835, note = []},
	&"and_elim": {illus_top = 904, note = []},
	&"imp_intro": {illus_top = 921, note = [Rect2i(1935, 1334, 396, 112), Rect2i(1990, 1234, 56, 66), Rect2i(1935, 1300, 341, 34)],
		mirror = [Rect2i(1642, 1300, 341, 34), Vector2i(1935, 1300)], note_at = Vector2(1990, 1350)},
	&"imp_elim": {illus_top = 835, note = []},
	&"or_intro": {illus_top = 904, note = []},
	&"or_elim": {illus_top = 858, note = []},
	&"false_elim": {illus_top = 908, note = [Rect2i(2140, 1392, 591, 154), Rect2i(2490, 1350, 241, 42)], note_at = Vector2(2160, 1400)},
}

var _sv: SubViewport
var _font: Font
var _fails := 0


func _initialize() -> void:
	await process_frame
	OS.low_processor_usage_mode = false
	var args := OS.get_cmdline_user_args()
	var measure := args.has("--measure")
	var only: Array = Array(args).filter(func(a: String) -> bool: return not a.begins_with("--"))
	_font = load(FONT_PATH)
	var jobs: Array = JOBS.duplicate()
	for id: StringName in NOTEBOOK:
		jobs.append(_notebook_job(id))
	for job in jobs:
		if not only.is_empty() and not only.has(job.tag):
			continue
		await _run_job(job, measure)
	print("gen_locale_art: %s(%d 处失败)" % ["measure" if measure else "done", _fails])
	quit(_fails)


func _notebook_job(id: StringName) -> Dictionary:
	var spec: Dictionary = NOTEBOOK[id]
	var en: Dictionary = NotebookEn.PAGES[id]
	var band := Rect2i(600, 440, 2760, int(spec.illus_top) - 6 - 440)
	var erase := [[band, CLEAR]]
	for r: Rect2i in spec.note:
		erase.append([r, CLEAR])
	var texts := [
		{text = en.title, size = NB_TITLE_SIZE, color = NB_TITLE, anchor = "center", at = NB_TITLE_CENTER},
		{text = en.body, sizes = NB_BODY_SIZES, color = NB_BODY, anchor = "topleft", at = Vector2(NB_BODY_LEFT, NB_BODY_TOP),
			wrap = NB_BODY_WRAP, max_bottom = int(spec.illus_top) - 16},
	]
	if String(en.note) != "":
		texts.append({text = en.note, size = NB_NOTE_SIZE, color = NB_TITLE, anchor = "topleft", at = spec.note_at})
	return {tag = String(id), src = "res://assets/art/level/notebook/%s.png" % id, erase = erase,
		detect = {search = Rect2i(600, 440, 2760, int(spec.illus_top) - 8 - 440), kind = "alpha"},
		mirror = spec.get("mirror", []), texts = texts}


func _run_job(job: Dictionary, measure: bool) -> void:
	var img := _png(job.src)
	if img == null:
		_fail("%s: 读不了 %s" % [job.tag, job.src])
		return
	img.convert(Image.FORMAT_RGBA8)
	# 探测中文墨迹框:必须落在擦除框(并集)里,否则美术换过图、常量作废
	var d: Dictionary = job.detect
	var found := _bbox(img, d.search, d.kind)
	var covered := found.size.x > 0
	for e in job.erase:
		if not (e[0] as Rect2i).encloses(found):
			covered = covered and _union_encloses(job.erase, found)
	print("  %s: 探测 %s 墨迹 %s %s" % [job.tag, d.kind, found, "(在擦除框内)" if covered else "!! 不在擦除框内"])
	if not covered:
		_fail("%s: 中文墨迹 %s 不在擦除框内(图变了?)" % [job.tag, found])
		return
	if measure:
		return
	for e in job.erase:
		img.fill_rect(e[0], e[1])
	var mirror: Array = job.get("mirror", [])
	if not mirror.is_empty():   # 批注压着机器底边:用左半边镜像补回被擦掉的一段边
		var strip := img.get_region(mirror[0])
		strip.flip_x()
		img.blit_rect(strip, Rect2i(Vector2i.ZERO, strip.get_size()), mirror[1])
	for t in job.texts:
		var ok := await _draw_text(img, t)
		if not ok:
			_fail("%s: 文字放不下:%s" % [job.tag, t.text])
	var out: String = job.src.get_basename() + ".en.png"
	var err := img.save_png(out)
	if err != OK:
		_fail("%s: 写不了 %s(%d)" % [job.tag, out, err])
		return
	_write_import(job.src, out)
	print("  %s → %s %s" % [job.tag, out, img.get_size()])


## 渲一段英文,按锚点贴到 img 上;有 sizes 阶梯就从大到小试到底部不超过 max_bottom
func _draw_text(img: Image, t: Dictionary) -> bool:
	var sizes: Array = t.get("sizes", [t.get("size", 48)])
	for size in sizes:
		var r := await _render(String(t.text), int(size), t.color, int(t.get("wrap", 0)))
		var ink: Image = r.image
		var used: Rect2i = r.used
		var at: Vector2 = t.at
		var pos: Vector2i
		match String(t.anchor):
			"center":
				pos = Vector2i((at - Vector2(used.size) * 0.5).round())
			"topright":
				pos = Vector2i(int(at.x) - used.size.x, int(at.y))
			_:
				pos = Vector2i(at)
		if t.has("max_bottom") and pos.y + used.size.y > int(t.max_bottom):
			continue
		img.blend_rect(ink, used, pos)
		return true
	return false


## Label 进透明离屏视口渲一次,返回 {image, used}(used = 墨迹包围盒)
func _render(text: String, size: int, color: Color, wrap_w: int) -> Dictionary:
	_sv = SubViewport.new()
	_sv.size = VP_SIZE
	_sv.transparent_bg = true
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.gui_disable_input = true
	if "oversampling_override" in _sv:
		_sv.oversampling_override = 1.0
	root.add_child(_sv)
	var lbl := Label.new()
	lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	lbl.text = text
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 0)
	lbl.add_theme_constant_override("shadow_offset_x", 0)
	lbl.add_theme_constant_override("shadow_offset_y", 0)
	if wrap_w > 0:
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_constant_override("line_spacing", roundi(size * 1.3 - _font.get_height(size)))
		lbl.size = Vector2(wrap_w, VP_SIZE.y)
	lbl.position = Vector2(8, 8)
	_sv.add_child(lbl)
	await create_timer(0.05).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _sv.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var used := image.get_used_rect()
	_sv.queue_free()
	_sv = null
	return {image = image, used = used}


## 在 search 框里按判色找墨迹包围盒(没有 → size 0)
static func _bbox(img: Image, search: Rect2i, kind: String) -> Rect2i:
	var minx := 1 << 30
	var miny := 1 << 30
	var maxx := -1
	var maxy := -1
	for y in range(search.position.y, search.end.y):
		for x in range(search.position.x, search.end.x):
			var c := img.get_pixel(x, y)
			var hit := false
			match kind:
				"alpha":
					hit = c.a > 0.04
				"gold":
					hit = c.a > 0.8 and c.r > 0.55 and c.r - c.b > 0.2
				"dark":
					hit = c.a > 0.8 and (c.r + c.g + c.b) / 3.0 < 0.55
			if hit:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
	if maxx < 0:
		return Rect2i()
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)


## 墨迹框是否被擦除框并集盖住(逐点查框内的墨迹点是否落在某个擦除框里 —— 框不多,直接按角点判足够:
## 擦除框都是轴对齐矩形,这里只要求 found 的每个像素行/列都被覆盖,用四角 + 中心近似)
static func _union_encloses(erase: Array, found: Rect2i) -> bool:
	for p in [found.position, found.end - Vector2i.ONE, Vector2i(found.end.x - 1, found.position.y), Vector2i(found.position.x, found.end.y - 1), found.get_center()]:
		var inside := false
		for e in erase:
			if (e[0] as Rect2i).has_point(p):
				inside = true
		if not inside:
			return false
	return true


static func _png(path: String) -> Image:
	var img := Image.new()
	return img if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK else null


## 复制原图的 .import(保住 mipmaps/generate=true 等参数),改 source/dest/uid;.ctex 由随后的 --import 生成
static func _write_import(src: String, out: String) -> void:
	var t := FileAccess.get_file_as_string(src + ".import")
	var ctex := "res://.godot/imported/%s-%s.ctex" % [out.get_file(), out.md5_text()]
	var re := RegEx.create_from_string("res://\\.godot/imported/[^\"\\]]+\\.ctex")
	t = re.sub(t, ctex, true)
	t = t.replace("source_file=\"%s\"" % src, "source_file=\"%s\"" % out)
	var re_uid := RegEx.create_from_string("uid=\"uid://[^\"]+\"")
	t = re_uid.sub(t, "uid=\"%s\"" % ResourceUID.id_to_text(ResourceUID.create_id()), false)
	var f := FileAccess.open(out + ".import", FileAccess.WRITE)
	f.store_string(t)
	f.close()


func _fail(msg: String) -> void:
	_fails += 1
	printerr("!! " + msg)
