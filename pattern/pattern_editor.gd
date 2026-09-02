class_name PatternEditor
extends PopupPanel
## 「纹样绘制」弹窗(v1.1 §4.6,照 image 13):标题带 → 预览 → 「点选笔刷进行绘制:」→ 笔刷行
## (原子色块 + 并织/迭层/岔纹线描图标 [+ 焦纹图样])→ [清空] … [取消] [确认]。
## 内部是一棵带"孔"(META 叶,渲染成未染纱)的临时 Formula 树:
## 选笔刷 → 点纹样上的任意叶子区域 → 该处替换成 原子色/分割(裂成两孔)。
## 「清空」把画布擦回一个孔(不关窗);「确认」在全部孔填满(is_ground)时钉住(pattern_committed),
## 画布整幅还是一个孔时 = 取消钉住(pattern_cleared);部分未染时不可按。
## 界面上不出现任何原子字母/逻辑符号/文字笔刷:原子笔刷是色块,结构笔刷是线描图标,焦纹笔刷是焦纹图样(v1.2)。
## 几何与 PatternView.layout 同一套切分规则,core 函数无 UI 依赖,headless 可测。

signal pattern_committed(f: Formula)
signal pattern_cleared   # 空画布「确认」= 取消钉住(unpin)

const HOLE_NAME := &"孔"
## 下面的尺寸全部从 image 13 按预览宽 433 → 720 折算(×1.663),见 docs/ART_INTERFACE.md §3.6
const PREVIEW_SIZE := Vector2(720, 420)
const SWATCH_SIZE := Vector2(110, 76)
const FONT_SIZE := 36                       # 清空/取消/确认
const BUTTON_MARGIN_H := 24.0
const BUTTON_MARGIN_V := 4.0
const TITLE_FONT_SIZE := 74                 # 标题墨高 38 → 63
const TITLE_BAND_PAD := 33.0                # 标题带上下内边距(带高 178 含 3 px 下边线)
const TITLE_INDENT := 37.0
const HINT_FONT_SIZE := 33
const TITLE_TEXT := "纹样绘制"
const HINT_TEXT := "点选笔刷进行绘制："   # 全角冒号照 image 13(站酷字库有,test_theme 盯)
## 结构笔刷:[笔刷 id, 图标线型],顺序照 image 13(竖分 / 横分 / 对角)
const STRUCT_BRUSHES: Array = [["and", "vertical"], ["imp", "horizontal"], ["or", "diagonal"]]
const ICON_LINE_W := 4.0
const ICON_COLOR := Color("3B2E1F")
const ICON_BG := Color(1, 0.98, 0.94)
const BUTTON_BG := Color("F0E4C8")          # 清空/取消/确认 底色(image 13)
const TITLE_BG := Color(0.941, 0.894, 0.784)
const FRAME_COLOR := Color(0.42, 0.23, 0.2)
const FRAME_W := 4
const FRAME_RADIUS := 6
const BAND_LINE_W := 3
const CONTENT_MARGIN := 20.0                # 预览/笔刷/按钮距外框(image 13:左 18 右 22)
const GAP_PREVIEW_HINT := 58.0
const GAP_HINT_BRUSH := 17.0
const GAP_BRUSH_BUTTONS := 76.0
const BOTTOM_PAD := 48.0
const BRUSH_GAP := 15

var tree: Formula = Formula.meta(HOLE_NAME)
var brush: String = ""        # "atom:A" / "and" / "or" / "imp" / "bot"

var _preview: PatternView
var _brush_row: HBoxContainer
var _confirm: Button
var _clear_btn: Button
var _group := ButtonGroup.new()
var _confirming := false      # 这次关闭是「确认」引起的(结果音归 LevelScene,不响 close)


## 结构笔刷的线描图标(竖线 / 横线 / 对角线,与 PatternView 的分割方向一致)
class BrushIcon extends Control:
	var style := "vertical"

	func _draw() -> void:
		var w := size.x
		var h := size.y
		match style:
			"vertical":
				draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, h), ICON_COLOR, ICON_LINE_W)
			"horizontal":
				draw_line(Vector2(0, h * 0.5), Vector2(w, h * 0.5), ICON_COLOR, ICON_LINE_W)
			"diagonal":
				draw_line(Vector2(w, 0), Vector2(0, h), ICON_COLOR, ICON_LINE_W)


func _init() -> void:
	popup_hide.connect(_on_hidden)   # 取消 / Esc / 点弹窗外面 → close 音统一在这里响
	# 弹窗外框:乳黄底 + 棕红描边;内容边距只留描边宽,标题带才能贴满上缘、预览紧贴标题带下边线
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.957, 0.925, 0.847)
	frame.set_border_width_all(FRAME_W)
	frame.border_color = FRAME_COLOR
	frame.set_corner_radius_all(FRAME_RADIUS)
	frame.set_content_margin_all(FRAME_W)
	add_theme_stylebox_override("panel", frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	add_child(box)

	var title_panel := PanelContainer.new()
	var band := StyleBoxFlat.new()
	band.bg_color = TITLE_BG
	band.border_width_bottom = BAND_LINE_W
	band.border_color = FRAME_COLOR
	band.corner_radius_top_left = FRAME_RADIUS
	band.corner_radius_top_right = FRAME_RADIUS
	band.content_margin_left = TITLE_INDENT
	band.content_margin_right = TITLE_INDENT
	band.content_margin_top = TITLE_BAND_PAD
	band.content_margin_bottom = TITLE_BAND_PAD
	title_panel.add_theme_stylebox_override("panel", band)
	var title := Label.new()
	title.text = TITLE_TEXT
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title_panel.add_child(title)
	box.add_child(title_panel)

	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", int(CONTENT_MARGIN))
	body.add_theme_constant_override("margin_right", int(CONTENT_MARGIN))
	body.add_theme_constant_override("margin_top", 0)
	body.add_theme_constant_override("margin_bottom", int(BOTTOM_PAD))
	box.add_child(body)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	body.add_child(col)

	_preview = PatternView.new()
	_preview.min_size = PREVIEW_SIZE
	_preview.gui_input.connect(_on_preview_input)
	col.add_child(_preview)
	col.add_child(_gap(GAP_PREVIEW_HINT))

	var hint := Label.new()
	hint.text = HINT_TEXT
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	col.add_child(hint)
	col.add_child(_gap(GAP_HINT_BRUSH))

	_brush_row = HBoxContainer.new()
	_brush_row.add_theme_constant_override("separation", BRUSH_GAP)
	col.add_child(_brush_row)
	col.add_child(_gap(GAP_BRUSH_BUTTONS))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", BRUSH_GAP)
	_clear_btn = _make_action_button("清空", _clear_canvas)
	_clear_btn.set_meta(SoundFx.META, &"clear")
	actions.add_child(_clear_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(sp)
	var cancel := _make_action_button("取消", hide)
	cancel.set_meta(SoundFx.META, &"")   # 关闭音统一在 _on_hidden 里响(取消 / Esc / 点弹窗外面都走 popup_hide)
	actions.add_child(cancel)
	_confirm = _make_action_button("确认", _on_confirm)
	_confirm.set_meta(SoundFx.META, &"")   # 结果音由 LevelScene 按钉成功 / 拒绝 / 取消钉住分别响
	actions.add_child(_confirm)
	col.add_child(actions)


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## atoms = 本关原子;initial = 已钉住的纹样(可再编辑);allow_bot = 焦纹章节后解锁
func open_for(atoms: Array[StringName], atom_colors: Dictionary,
		initial: Formula = null, allow_bot: bool = false) -> void:
	tree = initial if initial != null else Formula.meta(HOLE_NAME)
	_preview.atom_colors = atom_colors
	for c in _brush_row.get_children():
		_brush_row.remove_child(c)   # 先摘下来:queue_free 帧末才生效,旧笔刷会把窗口最小尺寸撑大
		c.queue_free()
	for a in atoms:
		_brush_row.add_child(_make_swatch(a))
	for pair in STRUCT_BRUSHES:
		_brush_row.add_child(_make_struct_button(pair[0], pair[1]))
	if allow_bot:
		_brush_row.add_child(_make_bot_button())
	brush = ""
	_sync()
	# 旧笔刷已 remove_child,最小尺寸立即正确;reset_size 让 Window 收缩(它只涨不缩),
	# 随后同步居中。不能 call_deferred:提交流程"打开→确认→hide"会被迟到的弹出又顶开。
	reset_size()
	_confirming = false
	popup_centered()
	SoundFx.hit(self, &"open")


func _make_action_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	UiStyles.fill_button(b, BUTTON_BG, BUTTON_MARGIN_H, BUTTON_MARGIN_V)
	b.pressed.connect(cb)
	return b


## 原子笔刷 = 该原子颜色的色块(不写字母);选中态描深边
func _make_swatch(a: StringName) -> Button:
	var b := Button.new()
	b.custom_minimum_size = SWATCH_SIZE
	b.toggle_mode = true
	b.button_group = _group
	b.tooltip_text = "染这一色"
	var col := _preview.atom_color(a)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.10) if state == "hover" else col   # 原子色已亮,悬停用变暗反馈
		sb.set_corner_radius_all(10)
		if state == "pressed":
			sb.set_border_width_all(6)
			sb.border_color = PatternView.SPLIT_COLOR
		b.add_theme_stylebox_override(state, sb)
	b.set_meta(SoundFx.META, &"brush")
	b.pressed.connect(_set_brush.bind("atom:" + String(a)))
	return b


## 结构笔刷 = 线描图标(白底黑框 + 分割线);选中态描深边
func _make_struct_button(id: String, style: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = SWATCH_SIZE
	b.toggle_mode = true
	b.button_group = _group
	b.tooltip_text = {"and": "并织:分成左右两半", "imp": "迭层:分成上下两层", "or": "岔纹:分成两支"}[id]
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = ICON_BG.darkened(0.05) if state == "hover" else ICON_BG
		sb.set_border_width_all(6 if state == "pressed" else int(ICON_LINE_W))
		sb.border_color = PatternView.SPLIT_COLOR if state == "pressed" else ICON_COLOR
		b.add_theme_stylebox_override(state, sb)
	var icon := BrushIcon.new()
	icon.style = style
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(icon)
	b.set_meta(SoundFx.META, &"brush")
	b.pressed.connect(_set_brush.bind(id))
	return b


## 焦纹笔刷 = 焦纹图样(与棋盘上的 ⊥ 同一画法:焦黑 + 破洞,PatternView 画),不写字(v1.2);
## 外框/选中态同结构笔刷,图样向内缩一圈让按钮自己的描边露出来
func _make_bot_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = SWATCH_SIZE
	b.toggle_mode = true
	b.button_group = _group
	b.tooltip_text = "焦纹"
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = ICON_BG.darkened(0.05) if state == "hover" else ICON_BG
		sb.set_border_width_all(6 if state == "pressed" else int(ICON_LINE_W))
		sb.border_color = PatternView.SPLIT_COLOR if state == "pressed" else ICON_COLOR
		b.add_theme_stylebox_override(state, sb)
	var pv := PatternView.new()
	pv.formula = Formula.bot()
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.set_anchors_preset(Control.PRESET_FULL_RECT)
	pv.offset_left = 6
	pv.offset_top = 6
	pv.offset_right = -6
	pv.offset_bottom = -6
	b.add_child(pv)
	b.set_meta(SoundFx.META, &"brush")
	b.pressed.connect(_set_brush.bind("bot"))
	return b


# ---- core(无 UI 依赖,headless 可测) ----

## 点 point 落在 rect 内哪个叶子:返回 0/1 左右孩子路径(与 PatternView.layout 同规则)
static func path_at(f: Formula, rect: Rect2, point: Vector2) -> Array[int]:
	if f == null or not f.is_binary():
		return []
	var local := point - rect.position
	var side: int
	var sub: Rect2
	match f.kind:
		Formula.Kind.AND:
			side = 0 if local.x < rect.size.x * 0.5 else 1
			sub = Rect2(rect.position + Vector2(side * rect.size.x * 0.5, 0), Vector2(rect.size.x * 0.5, rect.size.y))
		Formula.Kind.IMP:
			side = 0 if local.y < rect.size.y * 0.5 else 1
			sub = Rect2(rect.position + Vector2(0, side * rect.size.y * 0.5), Vector2(rect.size.x, rect.size.y * 0.5))
		Formula.Kind.OR:
			side = 0 if local.x / rect.size.x + local.y / rect.size.y <= 1.0 else 1
			# OR 的子式画在三角内接矩形里,继续细分时沿用同一内接几何
			sub = Rect2(rect.position, rect.size * 0.48) if side == 0 \
					else Rect2(rect.end - rect.size * 0.48, rect.size * 0.48)
		_:
			return []
	var rest := path_at(f.left if side == 0 else f.right, sub, point)
	var out: Array[int] = [side]
	out.append_array(rest)
	return out


## 把 path 指向的子树换成 repl,返回新树(Formula 不可变,整条路径重建)
static func replace_at(f: Formula, path: Array[int], repl: Formula) -> Formula:
	if path.is_empty():
		return repl
	var rest := path.slice(1)
	var l := f.left
	var r := f.right
	if path[0] == 0:
		l = replace_at(l, rest, repl)
	else:
		r = replace_at(r, rest, repl)
	match f.kind:
		Formula.Kind.AND: return Formula.conj(l, r)
		Formula.Kind.OR: return Formula.disj(l, r)
		Formula.Kind.IMP: return Formula.imp(l, r)
	return f


static func brush_formula(b: String) -> Formula:
	if b.begins_with("atom:"):
		return Formula.atom(StringName(b.substr(5)))
	match b:
		"and": return Formula.conj(Formula.meta(HOLE_NAME), Formula.meta(HOLE_NAME))
		"or": return Formula.disj(Formula.meta(HOLE_NAME), Formula.meta(HOLE_NAME))
		"imp": return Formula.imp(Formula.meta(HOLE_NAME), Formula.meta(HOLE_NAME))
		"bot": return Formula.bot()
	return null


func apply_brush_at(point: Vector2, rect: Rect2) -> void:
	var repl := brush_formula(brush)
	if repl == null:
		return
	tree = replace_at(tree, path_at(tree, rect, point), repl)
	_sync()
	SoundFx.hit(self, &"paint")


## 画布整幅还是一个孔(还没落任何笔刷 / 刚清空)
func is_canvas_empty() -> bool:
	return tree != null and tree.kind == Formula.Kind.META


## 「清空」:画布擦回一个孔,窗不关
func clear_canvas() -> void:
	tree = Formula.meta(HOLE_NAME)
	_sync()


# ---- UI 胶水 ----

func _clear_canvas() -> void:
	clear_canvas()


func _on_confirm() -> void:
	_confirming = visible   # 结果音由 LevelScene 按钉成功 / 拒绝 / 取消钉住分别响,这次关闭不响 close(本来就没开着的不留标记)
	if is_canvas_empty():
		pattern_cleared.emit()
	else:
		pattern_committed.emit(tree)
	hide()


## 任何方式关掉弹窗(取消按钮 / Esc / 点弹窗外面)都响一声 close;「确认」关掉的不响
func _on_hidden() -> void:
	if _confirming:
		_confirming = false
		return
	SoundFx.hit(self, &"close")


func _set_brush(b: String) -> void:
	brush = b
	_sync()


func _sync() -> void:
	_preview.formula = tree
	_confirm.disabled = not (tree.is_ground() or is_canvas_empty())


func _on_preview_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		apply_brush_at(mb.position, Rect2(Vector2.ZERO, _preview.size))
