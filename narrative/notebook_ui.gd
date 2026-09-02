class_name NotebookUI
extends CanvasLayer
## 诺拉的笔记抽屉(美术参考图 笔记本页面补充/位置参考.png 全页、information/art_spec_20260829/image 4.png 右缘;
## 底图 assets/art/level/notebook_bg.png 原尺寸 3798×2065)。
## 平时收在屏幕右缘只露出黄铜夹子(「笔记」);点击向左划出(缓动),夹子文字变「继续工作」;再点向右收回。
## 「翻页」循环切换条目(只显示本关已上架仪器的页)。
## 条目内容 = 整页 PNG(NotebookEntry.image,3840×2160 全屏导出、透明底,标题/正文全画在图里):
## 抽屉划出到位时图与屏幕对齐 → 在抽屉内摆在 PAGE_OFFSET(负的抽屉开位)、原尺寸不缩放;引擎不再渲染条目文字。
## 下面的位置/字号常量全部来自对参考图的模板匹配与墨迹量测(不是拍脑袋居中):
## tests/test_art_alignment.gd 盯着抽屉开位与参考图一致;tools/shot_4k.gd 出 1:1 截图给美术对照。
## 坐标为抽屉内 / 3840×2160 逻辑像素;美术调位置改下面常量。

signal open_requested          # 玩家点了收起状态的「笔记」;宿主调 open()
signal slide_finished(opened: bool)

const BG_PATH := "res://assets/art/level/notebook_bg.png"
const DRAWER_Y := 27.0                                  # 抽屉纵向位置:位置参考.png 里底图左上角实测 = (17, 27)(不是居中的 (21, 47.5))
const OPEN_X := 17.0                                    # 划出后的 x(同上)
const CLOSED_PEEK := 350.0                              # 收起时露出的宽度(夹子):关内预览图夹子匹配实测 ≈350
const SLIDE_SEC := 0.35
const HANDLE_SIZE := Vector2(300, 440)                  # 夹子「笔记 / 继续工作」按钮热区尺寸(抽屉内坐标,按下面的中心摆)
const HANDLE_CENTER_OPEN := Vector2(346, 1019)          # 划出后「继续 / 工作」两行的整体中心(抽屉内 = 参考屏幕 (363.5,1046) − 开位)
const HANDLE_CENTER_CLOSED := Vector2(254, 1021)        # 收起时「笔 / 记」两行的整体中心(抽屉内;关内预览夹子上的字 ≈ 屏幕 (3744,1084))
const HANDLE_FONT_SIZE := 78                            # 夹子文字字号:参考「继续工作」墨高 64–65 = 站酷小薇 78 号
const HANDLE_LINE_PITCH := 92.0                         # 夹子两行的行距(参考实测;Button 按字形自然行距只有 79,用 _pitched_font 垫到 92)
const FLIP_FONT_SIZE := 82                              # 「翻页」字号:参考墨迹 152×66 = 82 号
const FLIP_RECT := Rect2(3172, 1532, 220, 144)          # 右下角折角「翻页」:中心抽屉内 (3282,1604) = 参考屏幕 (3299.5,1631.5);
														# 尺寸 = Button 最小尺寸(字宽 168 / 单行按字体全高 120,各 + 内边距 24×2),
														# 小于它 Button 会自己撑大、中心跑偏
														# 折角三角形(抽屉内):直角 (3195,1540),斜边 (3460,1540)→(3195,1788)
const CONTENT_RECT := Rect2(642, 436, 2661, 1262)       # 七张整页图内容包围盒(抽屉内;屏幕 659..3319 × 463..1724 实测),仅作参考
const PAGE_OFFSET := Vector2(-OPEN_X, -DRAWER_Y)        # 整页图按全屏导出:抽屉开位时正好与屏幕对齐

var _drawer: Control
var _handle: Button
var _flip: Button
var _page_pic: TextureRect
var _entries: Array[NotebookEntry] = []
var _page := 0
var _open := false
var _tween: Tween
var _page_cache: Dictionary = {}          # 整页图路径 → Texture2D:进关时逐帧读完本关的页,翻页不再同步解码 3840×2160 PNG


func _init() -> void:
	layer = 60
	_drawer = Control.new()   # STOP:划出后挡住底下棋盘
	var bg := TextureRect.new()
	bg.texture = load(BG_PATH)
	bg.size = bg.texture.get_size()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.add_child(bg)
	_drawer.size = bg.size
	_drawer.position = Vector2(3840.0 - CLOSED_PEEK, DRAWER_Y)
	add_child(_drawer)

	_handle = _make_text_button(Rect2(Vector2.ZERO, HANDLE_SIZE), HANDLE_FONT_SIZE)
	_handle.add_theme_font_override("font", _pitched_font(HANDLE_FONT_SIZE, HANDLE_LINE_PITCH))
	_handle.set_meta(SoundFx.META, &"")   # 抽屉滑出 / 收起各有音
	_handle.pressed.connect(toggle)
	_drawer.add_child(_handle)
	_flip = _make_text_button(FLIP_RECT, FLIP_FONT_SIZE)
	_flip.text = "翻页"
	_flip.set_meta(SoundFx.META, &"")     # 翻页音在 _next_page
	_flip.pressed.connect(_next_page)
	_drawer.add_child(_flip)

	_page_pic = TextureRect.new()
	_page_pic.position = PAGE_OFFSET
	_page_pic.stretch_mode = TextureRect.STRETCH_KEEP   # 原尺寸:不缩放、不改长宽比(美术要求)
	_page_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.add_child(_page_pic)
	_set_handle_text(false)


func _ready() -> void:
	get_viewport().size_changed.connect(_snap)
	_snap()


## 纯文字按钮(无底、悬停变浅走 theme)
func _make_text_button(rect: Rect2, font_size: int) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", font_size)
	return b


## 主题字体的变体,把多行行距垫到 pitch:Button 多行按字形实际 ascent+descent 排行(站酷小薇 78 号 = 79),
## 参考图夹子两行是 92;FontVariation 的 spacing_top/bottom 会算进每行的 ascent/descent,上下各补一半,块中心不动。
static func _pitched_font(size: int, pitch: float) -> Font:
	var theme := ThemeDB.get_project_theme()
	var base: Font = theme.default_font if theme != null and theme.default_font != null else ThemeDB.fallback_font
	var line := TextLine.new()
	line.add_string("字", base, size)
	var extra := maxi(roundi(pitch - line.get_size().y), 0)
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_top = extra / 2
	fv.spacing_bottom = extra - extra / 2
	return fv


## 夹子文字:收起「笔 / 记」竖排两行,划出「继续 / 工作」两行两字(参考图的排版);按钮整体挪到对应的中心
func _set_handle_text(opened: bool) -> void:
	_handle.text = "继续\n工作" if opened else "笔\n记"
	var center := HANDLE_CENTER_OPEN if opened else HANDLE_CENTER_CLOSED
	_handle.position = (center - HANDLE_SIZE * 0.5).round()


func _viewport_width() -> float:
	if is_inside_tree():
		return get_viewport().get_visible_rect().size.x
	return 3840.0


func _target_x(opened: bool) -> float:
	return OPEN_X if opened else _viewport_width() - CLOSED_PEEK


func _snap() -> void:
	_drawer.position.x = _target_x(_open)


## 把本关允许的整页图读进缓存(LevelScene 进关时调;open() 也兜底调):一张 3840×2160 同步解码约 20 ms,
## 攒在翻页那一下会卡一帧(Web 更慢),挪到进关时做、在树里时一帧一张摊开。缓存持有引用,ResourceCache 不会中途释放。
func preload_pages(nb: NotebookCatalog, unlocked: Array = []) -> void:
	for e in nb.entries:
		if not unlocked.has(e.id) or e.image == "" or _page_cache.has(e.image) or not ResourceLoader.exists(e.image):
			continue
		_page_cache[e.image] = load(e.image)
		if is_inside_tree():
			await get_tree().process_frame


## 只显示 unlocked(本关 allowed_rules,条目 id = rule_id)对应的条目;
## 顺序 = 目录顺序 = 仪器架顺序。严格过滤:传空就一条不显示,没有"空=全量"兜底。
func open(nb: NotebookCatalog, unlocked: Array = []) -> void:
	preload_pages(nb, unlocked)   # 没预热过就顺手预热(第一张同步读,其余逐帧);_show_page 有同步兜底
	_entries.clear()
	for e in nb.entries:
		if unlocked.has(e.id):
			_entries.append(e)
	_page = 0
	_show_page()
	_slide(true)
	SoundFx.hit(self, &"drawer_open")


## 同 open(),但翻到 rule_id 对应的条目(v1.1 §5:进关时本关首次上架的仪器自动弹出它的页);找不到就第一页
func open_at(nb: NotebookCatalog, unlocked: Array, rule_id: StringName) -> void:
	open(nb, unlocked)
	for i in _entries.size():
		if _entries[i].id == rule_id:
			_page = i
			_show_page()
			return


func close() -> void:
	_slide(false)
	SoundFx.hit(self, &"drawer_close")


func toggle() -> void:
	if _open:
		close()
	else:
		open_requested.emit()


func is_open() -> bool:
	return _open


func _slide(opened: bool) -> void:
	_open = opened
	_set_handle_text(opened)
	if _tween != null:
		_tween.kill()
	if not is_inside_tree():
		_snap()
		slide_finished.emit(opened)
		return
	_tween = _drawer.create_tween()
	_tween.tween_property(_drawer, "position:x", _target_x(opened), SLIDE_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(func() -> void: slide_finished.emit(opened))


func _show_page() -> void:
	if _entries.is_empty():
		_page_pic.visible = false   # 空 = 白纸(占位文字已按要求全部删除)
		_flip.visible = false
		return
	_flip.visible = _entries.size() > 1
	var e := _entries[_page]
	var tex: Texture2D = _page_cache.get(e.image)
	if tex == null and e.image != "" and ResourceLoader.exists(e.image):
		tex = load(e.image)
		_page_cache[e.image] = tex
	if tex == null:
		push_warning("NotebookUI: 缺整页图 " + e.image)
	_page_pic.texture = tex
	_page_pic.visible = tex != null


## 翻到下一条,最后一条回到第一条(美术要求)
func _next_page() -> void:
	if _entries.is_empty():
		return
	_page = (_page + 1) % _entries.size()
	_show_page()
	SoundFx.hit(self, &"page")
