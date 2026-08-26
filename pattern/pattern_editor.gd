class_name PatternEditor
extends PopupPanel
## 挖孔式纹样编辑器(绑定封程机等的假设口)。
## 内部是一棵带"孔"(META 叶,渲染成未染纱)的临时 Formula 树:
## 选笔刷 → 点纹样上的任意叶子区域 → 该处替换成 原子色/分割(裂成两孔)/孔。
## 全部孔填满(is_ground)才允许确认;确认发 pattern_committed。
## 几何与 PatternView.layout 同一套切分规则,core 函数无 UI 依赖,headless 可测。

signal pattern_committed(f: Formula)
signal pattern_cleared   # "清除钉住"(unpin)

const HOLE_NAME := &"孔"

var tree: Formula = Formula.meta(HOLE_NAME)
var brush: String = ""        # "atom:A" / "and" / "or" / "imp" / "bot" / "erase"

var _preview: PatternView
var _brush_row: HFlowContainer
var _confirm: Button
var _clear_btn: Button
var _brush_lbl: Label


func _init() -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	add_child(box)
	var hint := Label.new()
	hint.text = "选笔刷,点纹样;斜纹处是未染的孔"
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	_preview = PatternView.new()
	_preview.min_size = Vector2(300, 190)
	_preview.gui_input.connect(_on_preview_input)
	box.add_child(_preview)
	_brush_lbl = Label.new()
	_brush_lbl.add_theme_font_size_override("font_size", 12)
	box.add_child(_brush_lbl)
	_brush_row = HFlowContainer.new()
	box.add_child(_brush_row)
	var actions := HBoxContainer.new()
	_clear_btn = Button.new()
	_clear_btn.text = "清除钉住"
	_clear_btn.pressed.connect(func() -> void:
		pattern_cleared.emit()
		hide())
	actions.add_child(_clear_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(sp)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(hide)
	actions.add_child(cancel)
	_confirm = Button.new()
	_confirm.text = "钉住"
	_confirm.pressed.connect(func() -> void:
		pattern_committed.emit(tree)
		hide())
	actions.add_child(_confirm)
	box.add_child(actions)


## atoms = 本关原子;initial = 已钉住的纹样(可再编辑);allow_bot = 焦纹章节后解锁
func open_for(atoms: Array[StringName], atom_colors: Dictionary,
		initial: Formula = null, allow_bot: bool = false, can_clear: bool = false) -> void:
	tree = initial if initial != null else Formula.meta(HOLE_NAME)
	_preview.atom_colors = atom_colors
	_clear_btn.visible = can_clear
	for c in _brush_row.get_children():
		c.queue_free()
	for a in atoms:
		var b := Button.new()
		b.text = String(a)
		b.add_theme_color_override("font_color", _preview.atom_color(a))
		b.pressed.connect(_set_brush.bind("atom:" + String(a)))
		_brush_row.add_child(b)
	for pair in [["并织 ∧", "and"], ["岔纹 ∨", "or"], ["迭层 →", "imp"], ["挖回孔", "erase"]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(_set_brush.bind(pair[1]))
		_brush_row.add_child(b)
	if allow_bot:
		var b := Button.new()
		b.text = "焦纹 ⊥"
		b.pressed.connect(_set_brush.bind("bot"))
		_brush_row.add_child(b)
	brush = ""
	_sync()
	popup_centered()


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
		"erase": return Formula.meta(HOLE_NAME)
	return null


func apply_brush_at(point: Vector2, rect: Rect2) -> void:
	var repl := brush_formula(brush)
	if repl == null:
		return
	tree = replace_at(tree, path_at(tree, rect, point), repl)
	_sync()


# ---- UI 胶水 ----

func _set_brush(b: String) -> void:
	brush = b
	_sync()


func _sync() -> void:
	_preview.formula = tree
	_confirm.disabled = not tree.is_ground()
	_brush_lbl.text = "当前笔刷:" + (brush if brush != "" else "(未选)")


func _on_preview_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		apply_brush_at(mb.position, Rect2(Vector2.ZERO, _preview.size))
