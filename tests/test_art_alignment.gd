extends TestBase
## 美术对齐回归:把「引擎常量 vs 美术参考图」的量测固化成测试,常量被改回「居中」或美术换图尺寸不一致时立刻红。
## 参考基准(全分辨率、可信):
##   ① assets/art/story/base.png 自己画出来的框线 —— 场景插图开口、左右立绘区、地板线(扫暗线,阈值灰度 <140);
##   ② 笔记本页面补充/位置参考.png —— 笔记底图在屏幕上的位置(把 notebook_bg 不透明像素抽样比对,找最小均差);
##   ③ 立绘与遮罩的尺寸关系(引擎按遮罩画布定位,立绘只许等宽、不高于遮罩)。
## PNG 一律直读文件字节(Image.load_png_from_buffer),不走导入器,参考图目录将来加 .gdignore 也不影响。
## 量测方法与全部实测数字见 docs/ART_INTERFACE.md「参考基准与实测值」。

const TOL := 2   # 手绘框线本身有 1–2 px 抖动


func test_story_scene_rect_sits_in_painted_frame() -> bool:
	var base := _png("res://assets/art/story/base.png")
	if not check(base != null and base.get_width() == 3835 and base.get_height() == 2123, "读到 base.png 3835×2123"):
		return false
	var bp := StoryScene.BASE_POS
	var tops: Array[int] = []
	var bottoms: Array[int] = []
	var lefts: Array[int] = []
	var rights: Array[int] = []
	for x in [1200, 1500, 1926, 2300, 2600]:
		var runs := _dark_runs_col(base, x - int(bp.x), 60 - int(bp.y), 140 - int(bp.y))
		if not runs.is_empty():
			tops.append(runs[-1][1] + int(bp.y) + 1)     # 最后一段暗线的下沿 + 1 = 开口顶
		runs = _dark_runs_col(base, x - int(bp.x), 1300 - int(bp.y), 1360 - int(bp.y))
		if not runs.is_empty():
			bottoms.append(runs[0][0] + int(bp.y) - 1)    # 第一段暗线的上沿 − 1 = 开口底
	for y in [200, 500, 700, 1000, 1250]:
		var runs := _dark_runs_row(base, y - int(bp.y), 880 - int(bp.x), 1000 - int(bp.x))
		if not runs.is_empty():
			lefts.append(runs[-1][1] + int(bp.x) + 1)
		runs = _dark_runs_row(base, y - int(bp.y), 2860 - int(bp.x), 2960 - int(bp.x))
		if not runs.is_empty():
			rights.append(runs[0][0] + int(bp.x) - 1)
	var ok := check(tops.size() >= 3 and bottoms.size() >= 3 and lefts.size() >= 3 and rights.size() >= 3, "在 base.png 上找到场景框四边的框线")
	if not ok:
		return false
	var opening := Rect2i(_median(lefts), _median(tops), 0, 0)
	opening.end = Vector2i(_median(rights) + 1, _median(bottoms) + 1)
	var r := StoryScene.SCENE_RECT
	ok = check(absi(int(r.position.x) - opening.position.x) <= TOL, "场景插图左边贴框内沿(引擎 %d,框 %d)" % [int(r.position.x), opening.position.x]) and ok
	ok = check(absi(int(r.position.y) - opening.position.y) <= TOL, "场景插图上边贴框内沿(引擎 %d,框 %d)" % [int(r.position.y), opening.position.y]) and ok
	ok = check(absi(int(r.end.x) - opening.end.x) <= TOL, "场景插图右边贴框内沿(引擎 %d,框 %d)" % [int(r.end.x), opening.end.x]) and ok
	return check(absi(int(r.end.y) - opening.end.y) <= TOL, "场景插图下边贴框内沿(引擎 %d,框 %d)" % [int(r.end.y), opening.end.y]) and ok


func test_portrait_frames_inside_painted_area() -> bool:
	var base := _png("res://assets/art/story/base.png")
	if base == null:
		return check(false, "读到 base.png")
	var bp := StoryScene.BASE_POS
	var ok := true
	for side in 2:
		var frame: Rect2 = StoryScene.RIGHT_FRAME if side == 1 else StoryScene.LEFT_FRAME
		var lefts: Array[int] = []
		var rights: Array[int] = []
		var floors: Array[int] = []
		for y in [400, 1000, 1600, 1900]:
			# 左区:左内沿是屏幕 x 30..100 里最后一段暗线,右界是场景框外沿(880..1000 第一段);右区镜像
			var l_runs := _dark_runs_row(base, y - int(bp.y), (2860 if side == 1 else 30) - int(bp.x), (2960 if side == 1 else 100) - int(bp.x))
			var r_runs := _dark_runs_row(base, y - int(bp.y), (3730 if side == 1 else 880) - int(bp.x), (3800 if side == 1 else 1000) - int(bp.x))
			if not l_runs.is_empty():
				lefts.append(l_runs[-1][1] + int(bp.x) + 1)
			if not r_runs.is_empty():
				rights.append(r_runs[0][0] + int(bp.x) - 1)
		for x in ([3000, 3300, 3600] if side == 1 else [200, 400, 600, 800]):
			var runs := _dark_runs_col(base, x - int(bp.x), 1960 - int(bp.y), 2060 - int(bp.y))
			if not runs.is_empty():
				floors.append(runs[0][0] + int(bp.y) - 1)   # 地板线上沿 − 1 = 脚底最低可到的行
		var name := "右" if side == 1 else "左"
		if not check(lefts.size() >= 3 and rights.size() >= 3 and floors.size() >= 3, "%s立绘区框线找到" % name):
			ok = false
			continue
		var left := _median(lefts)
		var right := _median(rights)
		var floor_y := _median(floors)
		ok = check(int(frame.position.x) >= left - 1 and int(frame.end.x) - 1 <= right + 1,
				"%s立绘框在框线内沿之间(框 %d..%d,内沿 %d..%d)" % [name, int(frame.position.x), int(frame.end.x) - 1, left, right]) and ok
		ok = check(int(frame.end.y) - 1 <= floor_y and int(frame.end.y) - 1 >= floor_y - 40,
				"%s立绘脚底不压地板线、也不悬空太多(脚底 %d,地板 %d)" % [name, int(frame.end.y) - 1, floor_y]) and ok
	return ok


func test_notebook_open_position_matches_reference() -> bool:
	var ref := _png("res://笔记本页面补充/位置参考.png")
	var nb := _png(NotebookUI.BG_PATH)
	if not check(ref != null and nb != null and ref.get_size() == Vector2i(3840, 2160), "读到 位置参考.png 与 notebook_bg.png"):
		return false
	var want := Vector2i(int(NotebookUI.OPEN_X), int(NotebookUI.DRAWER_Y))
	var best := Vector2i.ZERO
	var best_d := 1e9
	var second_d := 1e9
	for dy in range(want.y - 3, want.y + 4):
		for dx in range(want.x - 3, want.x + 4):
			var sum := 0.0
			var n := 0
			for y in range(0, nb.get_height(), 8):
				for x in range(0, nb.get_width(), 8):
					var p := nb.get_pixel(x, y)
					if p.a < 0.98:
						continue
					var q := ref.get_pixel(x + dx, y + dy)
					sum += absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
					n += 1
			var d := sum / maxf(n, 1)
			if d < best_d:
				second_d = best_d
				best_d = d
				best = Vector2i(dx, dy)
			elif d < second_d:
				second_d = d
	var ok := check(best == want, "笔记底图划出位 (OPEN_X, DRAWER_Y) = 位置参考.png 里的位置(引擎 %s,参考 %s)" % [str(want), str(best)])
	return check(second_d > best_d * 1.1, "最小均差是尖锐的唯一极小(最优 %.4f,次优 %.4f)" % [best_d, second_d]) and ok


func test_portraits_match_mask_canvas() -> bool:
	var ok := true
	var n := 0
	for char_name: String in StoryArt.CHARACTERS:
		var mask := _png(StoryArt.mask_path(char_name))
		if not check(mask != null, "%s 有遮罩" % char_name):
			ok = false
			continue
		for expr: String in StoryArt.EXPRESSIONS:
			var path := StoryArt.portrait_path(char_name, expr)
			if not FileAccess.file_exists(path):
				continue
			var pic := _png(path)
			n += 1
			ok = check(pic != null and pic.get_width() == mask.get_width(), "%s(%s)与遮罩等宽" % [char_name, expr]) and ok
			ok = check(pic != null and pic.get_height() <= mask.get_height() and pic.get_height() >= mask.get_height() - 16,
					"%s(%s)高度 ≤ 遮罩且不差太多(立绘 %d,遮罩 %d;引擎按遮罩画布定位,只容许美术裁短)" % [char_name, expr, pic.get_height() if pic else -1, mask.get_height()]) and ok
	return check(n >= 7, "扫到 7+ 张立绘(得 %d)" % n) and ok


func test_notebook_pages_stay_offscreen_when_closed() -> bool:
	# 收起时抽屉 x = 3840 − CLOSED_PEEK,整页图原点再左移 OPEN_X:整页图里 x < CLOSED_PEEK + OPEN_X 的内容会露在夹子上
	var limit := int(NotebookUI.CLOSED_PEEK + NotebookUI.OPEN_X)
	var nb := NotebookCatalog.load_default()
	var ok := true
	var n := 0
	for e in nb.entries:
		if e.image == "":
			continue
		var img := _png(e.image)
		if not check(img != null and img.get_size() == Vector2i(3840, 2160), "%s 是 3840×2160 整页图" % e.image):
			ok = false
			continue
		n += 1
		var min_x := 99999
		for y in range(0, img.get_height(), 4):
			for x in range(0, limit, 2):
				if img.get_pixel(x, y).a > 0.04:
					min_x = mini(min_x, x)
					break
		ok = check(min_x >= limit, "%s 内容最左 x=%s ≥ %d,收起时不会露在夹子上" % [e.image.get_file(), ("无" if min_x == 99999 else str(min_x)), limit]) and ok
	return check(n >= 7, "扫到 7 张整页图(得 %d)" % n) and ok


# ---- helpers ----

static func _png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return img


static func _is_dark(c: Color) -> bool:
	return (c.r + c.g + c.b) / 3.0 < 140.0 / 255.0


## 一列上 y0..y1(含)内的暗线段 [[起, 止], ...](图内坐标)
static func _dark_runs_col(img: Image, x: int, y0: int, y1: int) -> Array:
	var runs: Array = []
	var inb := false
	var start := 0
	for y in range(maxi(y0, 0), mini(y1, img.get_height() - 1) + 1):
		var d := _is_dark(img.get_pixel(x, y))
		if d and not inb:
			inb = true
			start = y
		elif not d and inb:
			inb = false
			runs.append([start, y - 1])
	if inb:
		runs.append([start, y1])
	return runs


static func _dark_runs_row(img: Image, y: int, x0: int, x1: int) -> Array:
	var runs: Array = []
	var inb := false
	var start := 0
	for x in range(maxi(x0, 0), mini(x1, img.get_width() - 1) + 1):
		var d := _is_dark(img.get_pixel(x, y))
		if d and not inb:
			inb = true
			start = x
		elif not d and inb:
			inb = false
			runs.append([start, x - 1])
	if inb:
		runs.append([start, x1])
	return runs


static func _median(v: Array[int]) -> int:
	var s := v.duplicate()
	s.sort()
	return s[s.size() / 2]
