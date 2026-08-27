class_name MachineGuidePanel
extends PanelContainer
## 点选某台仪器时弹出的介绍卡(名字 + 一句话 + 详解 + 示例纹样)。
## 数据来自 narrative/data/rule_guide.tres(RuleGuideCatalog),改文案不碰代码;
## 本控件只认 rule_id,和棋盘/求解解耦 —— 未来 UI 改版可整体换皮或挪位置,只要还调 show_for/clear。

var _title: Label
var _summary: Label
var _body: RichTextLabel
var _demo: PatternView
var _catalog: RuleGuideCatalog
var _atom_colors: Dictionary = {}


func _init() -> void:
	visible = false
	custom_minimum_size = Vector2(320, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 纯展示覆盖层,不挡底下棋盘的点击
	_catalog = RuleGuideCatalog.load_default()
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_title)
	_summary = Label.new()
	_summary.modulate.a = 0.8
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_summary)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.custom_minimum_size.y = 60
	box.add_child(_body)
	_demo = PatternView.new()
	_demo.min_size = Vector2(120, 66)
	_demo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_demo)
	for c in [_title, _summary, _body, _demo]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_atom_colors(colors: Dictionary) -> void:
	_atom_colors = colors
	_demo.atom_colors = colors


## 显示某仪器的介绍;catalog 里没有该 id 时回退到中文机名(fallback_name)
func show_for(rule_id: StringName, fallback_name: String) -> void:
	var g := _catalog.guide(rule_id) if _catalog != null else null
	if g == null:
		_title.text = fallback_name
		_summary.text = ""
		_body.text = "[占位] 这台仪器还没有介绍。"
		_demo.formula = null
	else:
		_title.text = g.title if g.title != "" else fallback_name
		_summary.text = g.summary
		_body.text = g.body
		_demo.formula = FormulaParser.parse(g.demo_formula) if g.demo_formula != "" else null
	visible = true


func clear() -> void:
	visible = false
