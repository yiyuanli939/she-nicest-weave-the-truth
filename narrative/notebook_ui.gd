class_name NotebookUI
extends CanvasLayer
## 笔记本(占位级):左列已解锁条目,右侧正文 + 纹样示例。

var _list: ItemList
var _title: Label
var _body: RichTextLabel
var _demo: PatternView
var _entries: Array[NotebookEntry] = []


func _init() -> void:
	layer = 60
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed:
			close())
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(680, 420)
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	var t := Label.new()
	t.text = "织者笔记"
	t.add_theme_font_size_override("font_size", 20)
	top.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var x := Button.new()
	x.text = "合上"
	x.pressed.connect(close)
	top.add_child(x)
	box.add_child(top)

	var body_row := HBoxContainer.new()
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(200, 0)
	_list.item_selected.connect(_on_selected)
	body_row.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	right.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_body)
	_demo = PatternView.new()
	_demo.min_size = Vector2(180, 100)
	_demo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right.add_child(_demo)
	body_row.add_child(right)
	box.add_child(body_row)
	panel.add_child(box)
	add_child(panel)
	visible = false


## unlocked = 已解锁条目 id(String/StringName 皆可)
func open(nb: NotebookCatalog, unlocked: Array) -> void:
	_entries.clear()
	_list.clear()
	for e in nb.entries:
		if unlocked.has(String(e.id)) or unlocked.has(e.id):
			_entries.append(e)
			_list.add_item(e.title)
	visible = true
	if _entries.is_empty():
		_title.text = "(还没有记下什么)"
		_body.text = "[占位] 通关后,同构的秘密会被记在这里。"
		_demo.formula = null
	else:
		_list.select(0)
		_on_selected(0)


func _on_selected(idx: int) -> void:
	var e := _entries[idx]
	_title.text = e.title
	_body.text = e.body
	_demo.formula = FormulaParser.parse(e.demo_formula) if e.demo_formula != "" else null


func close() -> void:
	visible = false
