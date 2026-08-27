class_name NotebookUI
extends CanvasLayer
## 织者笔记(占位级):整页翻书式。左缘「继续工作」标签关闭、右缘「翻页」按钮翻条目。
## 布局参考 information/ui_笔记页面_翻书.png。全屏铺满,不用居中弹窗(绕开 PRESET_CENTER 溢出)。

const TAB_COLOR := Color(0.66, 0.53, 0.53)   # 藕粉竖条标签(取自原型图)
const PAGE_COLOR := Color(0.93, 0.90, 0.83)  # 中间书页:米白羊皮纸
const TAB_W := 76.0

var _title: Label
var _body: RichTextLabel
var _demo: PatternView
var _page_lbl: Label
var _flip_btn: Button
var _entries: Array[NotebookEntry] = []
var _page := 0


func _init() -> void:
	layer = 60
	visible = false

	var page := ColorRect.new()   # 书页底,铺满
	page.color = PAGE_COLOR
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(page)

	# 左缘竖排「继续工作」标签 —— 关闭回到底下的场景
	var back := _make_tab("继续工作", true)
	back.pressed.connect(close)
	add_child(back)

	# 右缘竖排「翻页」按钮
	_flip_btn = _make_tab("翻页", false)
	_flip_btn.pressed.connect(_next_page)
	add_child(_flip_btn)

	# 中间书页内容:标题 + 正文 + 纹样示例 + 页码,居中留出两侧标签宽。
	# 铺满全屏但不吃鼠标,否则会盖住两侧标签的点击(标签在它下层)。
	var content := MarginContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", int(TAB_W) + 60)
	content.add_theme_constant_override("margin_right", int(TAB_W) + 60)
	content.add_theme_constant_override("margin_top", 48)
	content.add_theme_constant_override("margin_bottom", 48)
	add_child(content)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	content.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_body)
	_demo = PatternView.new()
	_demo.min_size = Vector2(220, 130)
	_demo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_demo)
	_page_lbl = Label.new()
	_page_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_lbl.modulate.a = 0.6
	box.add_child(_page_lbl)


## 竖排 CJK 标签:方块字换行即竖排,比旋转 Label 稳(热区/对齐都正常)
func _make_tab(text: String, left: bool) -> Button:
	var b := Button.new()
	var vertical := ""
	for i in text.length():
		vertical += text[i] + ("\n" if i < text.length() - 1 else "")
	b.text = vertical
	b.add_theme_font_size_override("font_size", 22)
	b.set_anchors_preset(Control.PRESET_LEFT_WIDE if left else Control.PRESET_RIGHT_WIDE)
	if left:
		b.offset_right = TAB_W
	else:
		b.offset_left = -TAB_W
	var sb := StyleBoxFlat.new()
	sb.bg_color = TAB_COLOR
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := StyleBoxFlat.new()
	sb_h.bg_color = TAB_COLOR.lightened(0.12)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)
	b.add_theme_color_override("font_color", Color.WHITE)
	return b


## unlocked = 已解锁条目 id(String/StringName 皆可)
func open(nb: NotebookCatalog, unlocked: Array) -> void:
	_entries.clear()
	for e in nb.entries:
		if unlocked.has(String(e.id)) or unlocked.has(e.id):
			_entries.append(e)
	_page = 0
	visible = true
	_show_page()


func _show_page() -> void:
	if _entries.is_empty():
		_title.text = "(还没有记下什么)"
		_body.text = "[占位] 通关后,同构的秘密会被记在这里。"
		_demo.formula = null
		_page_lbl.text = ""
		_flip_btn.visible = false
		return
	_flip_btn.visible = _entries.size() > 1
	var e := _entries[_page]
	_title.text = e.title
	_body.text = e.body
	_demo.formula = FormulaParser.parse(e.demo_formula) if e.demo_formula != "" else null
	_page_lbl.text = "%d / %d" % [_page + 1, _entries.size()]


func _next_page() -> void:
	if _entries.is_empty():
		return
	_page = (_page + 1) % _entries.size()
	_show_page()


func close() -> void:
	visible = false
