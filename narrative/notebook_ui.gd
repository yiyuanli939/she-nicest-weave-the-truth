class_name NotebookUI
extends CanvasLayer
## 织者笔记抽屉(美术参考图 information/art_spec_20260829/image 4.png 右缘、image 5.png 全页;
## 底图 assets/art/level/notebook_bg.png 原尺寸 3798×2065)。
## 平时收在屏幕右缘只露出黄铜夹子(「笔记」);点击向左划出(缓动),夹子文字变「继续工作」;再点向右收回。
## 「翻页」循环切换条目(七台仪器说明,先仅文字,全量常驻)。
## 坐标为抽屉内 / 3840×2160 逻辑像素;美术调位置改下面常量。

signal open_requested          # 玩家点了收起状态的「笔记」;宿主调 open()
signal slide_finished(opened: bool)

const BG_PATH := "res://assets/art/level/notebook_bg.png"
const DRAWER_Y := 48.0                                  # 抽屉纵向位置(底图 2065 高,居中)
const OPEN_X := 21.0                                    # 划出后的 x
const CLOSED_PEEK := 480.0                              # 收起时露出的宽度(夹子)
const SLIDE_SEC := 0.35
const HANDLE_RECT := Rect2(200, 820, 300, 440)          # 夹子上「笔记 / 继续工作」按钮(抽屉内坐标)
const FLIP_RECT := Rect2(3190, 1480, 240, 140)          # 右下角折角「翻页」
const CONTENT_RECT := Rect2(397, 237, 3040, 1500)       # 纸面
const CONTENT_MARGIN := 120
const HANDLE_FONT_SIZE := 52
const FLIP_FONT_SIZE := 52
const TITLE_FONT_SIZE := 64
const BODY_FONT_SIZE := 52
const TITLE_COLOR := Color(0.29, 0.184, 0.165)          # 深棕
const BODY_COLOR := Color(0.627, 0.275, 0.227)          # 红棕(参考图正文色)

var _drawer: Control
var _handle: Button
var _flip: Button
var _title: Label
var _body: RichTextLabel
var _entries: Array[NotebookEntry] = []
var _page := 0
var _open := false
var _tween: Tween


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

	_handle = _make_text_button(HANDLE_RECT, HANDLE_FONT_SIZE)
	_handle.pressed.connect(toggle)
	_drawer.add_child(_handle)
	_flip = _make_text_button(FLIP_RECT, FLIP_FONT_SIZE)
	_flip.text = "翻页"
	_flip.pressed.connect(_next_page)
	_drawer.add_child(_flip)

	var content := MarginContainer.new()
	content.position = CONTENT_RECT.position
	content.size = CONTENT_RECT.size
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		content.add_theme_constant_override("margin_" + side, CONTENT_MARGIN)
	_drawer.add_child(content)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 40)
	content.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", BODY_FONT_SIZE)
	_body.add_theme_color_override("default_color", BODY_COLOR)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_body)
	_set_handle_text(false)


func _ready() -> void:
	get_viewport().size_changed.connect(_snap)
	_snap()


## 纯文字按钮(无底、悬停变浅走 theme),竖排 CJK 用逐字换行
func _make_text_button(rect: Rect2, font_size: int) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.add_theme_font_size_override("font_size", font_size)
	return b


func _set_handle_text(opened: bool) -> void:
	var text := "继续工作" if opened else "笔记"
	var vertical := ""
	for i in text.length():
		vertical += text[i] + ("\n" if i < text.length() - 1 else "")
	_handle.text = vertical


func _viewport_width() -> float:
	if is_inside_tree():
		return get_viewport().get_visible_rect().size.x
	return 3840.0


func _target_x(opened: bool) -> float:
	return OPEN_X if opened else _viewport_width() - CLOSED_PEEK


func _snap() -> void:
	_drawer.position.x = _target_x(_open)


## unlocked 参数保留旧签名;笔记全量常驻,不看它
func open(nb: NotebookCatalog, _unlocked: Array = []) -> void:
	_entries.clear()
	_entries.assign(nb.entries)
	_page = 0
	_show_page()
	_slide(true)


func close() -> void:
	_slide(false)


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
		_title.text = "(还没有记下什么)"
		_body.text = ""
		_flip.visible = false
		return
	_flip.visible = _entries.size() > 1
	var e := _entries[_page]
	_title.text = e.title
	_body.text = e.body


## 翻到下一条,最后一条回到第一条(美术要求)
func _next_page() -> void:
	if _entries.is_empty():
		return
	_page = (_page + 1) % _entries.size()
	_show_page()
