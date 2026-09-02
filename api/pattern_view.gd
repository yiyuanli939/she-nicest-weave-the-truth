class_name PatternView
extends Control
## 纹样哑控件:给什么 Formula 画什么,不懂逻辑、不发请求。
##
## 纹样约定(plan.md §5.1):
##   ATOM 纯色 · META 未染纱(亚麻底+斜纹) · BOT 焦纹(焦黑+破洞)
##   AND 竖分(左 left 右 right) · IMP 横分(上前件下后件) · OR 对角分(左上/右下三角)
##   null → 空白亚麻底;formula_text 解析失败 → 错纹(品红叉)并 push_warning。
##
## 几何全部出自 static layout()(纯函数,headless 测试与 _draw 共用);
## 深度 > MAX_DEPTH 画省略织纹止损。
## 美术接口:atom_colors 由关卡注入;缺失原子回退 hash→HSV。

const MAX_DEPTH := 6
const BASE_LINE_W := 8.0
const LINEN := Color(0.91, 0.87, 0.78)      # 亚麻底
const CHAR_BLACK := Color(0.12, 0.10, 0.09) # 焦黑
const SPLIT_COLOR := Color(0.23, 0.18, 0.12)
const REGION_BORDER_W := 3.0   # 按子命题着色的区域边框线宽(v1.1 §4.2)

const GHOST_ALPHA := 0.5   # 原子色降饱和提亮后,0.4 的幽灵态在乳黄节点底上会糊

## 关卡注入的原子调色板 {StringName: Color};缺失回退 hash→HSV
@export var atom_colors: Dictionary = {}
@export var min_size := Vector2(48, 48)

## 幽灵态:半透明画"推导出的期望值"(未连线端口),与实际连入的实纹样区分
@export var ghost := false:
	set(v):
		ghost = v
		self_modulate.a = GHOST_ALPHA if v else 1.0

## Inspector 预览入口:直接写公式文本(如 "A & B")
@export var formula_text: String = "":
	set(v):
		formula_text = v
		_parse_failed = false
		if v.strip_edges().is_empty():
			_formula = null
		else:
			var f := FormulaParser.parse(v)
			if f == null:
				_parse_failed = true
				push_warning("PatternView: 公式解析失败 \"%s\" — %s" % [v, FormulaParser.last_error])
			_formula = f
		queue_redraw()

## 区域边框(v1.1 §4.2):[{path: Array[int], color: Color}],path 是子式路径(0 左/上,1 右/下,[] 整幅)。
## 非空时按 spec 描每个区域的轮廓、不再画整体深色外框;空(线轴/目标)时照旧画深色外框。
## 由 MachineNode 按仪器模板结构算好注入;实际纹样与模板同构,路径一定落在对应区域上。
var region_borders: Array[Dictionary] = []:
	set(v):
		region_borders = v
		queue_redraw()

var _formula: Formula = null
var _parse_failed := false

## 代码主路径:直接喂 Formula(把它当不透明纹样值)
var formula: Formula:
	get:
		return _formula
	set(f):
		_formula = f
		_parse_failed = false
		queue_redraw()


func _get_minimum_size() -> Vector2:
	return min_size


## 纯几何布局:把 f 在 rect 内递归切分,返回绘制条目列表(与 _draw 共用,headless 可断言)。
## 条目结构:
##   {shape:"rect", rect:Rect2, kind:int, name:StringName, depth:int}   叶子矩形(kind=-1 空白)
##   {shape:"tri",  points:PackedVector2Array, kind:int, name:StringName, depth:int} OR 叶子三角
##   {shape:"line", from:Vector2, to:Vector2, width:float, depth:int}   分割线
##   {shape:"deep", rect:Rect2, depth:int}                              超深省略织纹
static func layout(f: Formula, rect: Rect2, depth: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if f == null:
		out.append({shape = "rect", rect = rect, kind = -1, name = &"", depth = depth})
		return out
	if depth > MAX_DEPTH:
		out.append({shape = "deep", rect = rect, depth = depth})
		return out
	match f.kind:
		Formula.Kind.ATOM, Formula.Kind.META, Formula.Kind.BOT:
			out.append({shape = "rect", rect = rect, kind = f.kind, name = f.name, depth = depth})
		Formula.Kind.AND:
			var mid_x := rect.position.x + rect.size.x * 0.5
			out.append_array(layout(f.left, Rect2(rect.position, Vector2(rect.size.x * 0.5, rect.size.y)), depth + 1))
			out.append_array(layout(f.right, Rect2(Vector2(mid_x, rect.position.y), Vector2(rect.size.x * 0.5, rect.size.y)), depth + 1))
			out.append({shape = "line", from = Vector2(mid_x, rect.position.y), to = Vector2(mid_x, rect.end.y), width = split_width(depth), depth = depth})
		Formula.Kind.IMP:
			var mid_y := rect.position.y + rect.size.y * 0.5
			out.append_array(layout(f.left, Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.5)), depth + 1))
			out.append_array(layout(f.right, Rect2(Vector2(rect.position.x, mid_y), Vector2(rect.size.x, rect.size.y * 0.5)), depth + 1))
			out.append({shape = "line", from = Vector2(rect.position.x, mid_y), to = Vector2(rect.end.x, mid_y), width = split_width(depth), depth = depth})
		Formula.Kind.OR:
			var tl := rect.position
			var tr := Vector2(rect.end.x, rect.position.y)
			var bl := Vector2(rect.position.x, rect.end.y)
			var br := rect.end
			out.append_array(_layout_or_child(f.left, PackedVector2Array([tl, tr, bl]), Rect2(tl, rect.size * 0.48), depth))
			out.append_array(_layout_or_child(f.right, PackedVector2Array([tr, br, bl]), Rect2(br - rect.size * 0.48, rect.size * 0.48), depth))
			out.append({shape = "line", from = tr, to = bl, width = split_width(depth), depth = depth})
	return out


## OR 的子式:叶子直接填满三角;复合式退回三角内接矩形里递归(占位级,几何简单可测)
static func _layout_or_child(f: Formula, tri: PackedVector2Array, inner: Rect2, depth: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if f != null and f.is_binary() and depth < MAX_DEPTH:
		out.append({shape = "tri", points = tri, kind = -1, name = &"", depth = depth + 1})
		out.append_array(layout(f, inner, depth + 1))
	else:
		var kind := -1
		var nm := &""
		if f != null:
			kind = f.kind
			nm = f.name
		out.append({shape = "tri", points = tri, kind = kind, name = nm, depth = depth + 1})
	return out


static func split_width(depth: int) -> float:
	return maxf(2.0, BASE_LINE_W * pow(0.62, depth))


## path 指向的子式在 rect 里占的区域(与 layout 同一套切分):
## {shape:"rect", rect:Rect2} 或(OR 的直接子式){shape:"tri", points:PackedVector2Array};
## path 越过叶子 / 形状不符 → 空字典。[] = 整幅。
static func region_of_path(f: Formula, rect: Rect2, path: Array[int]) -> Dictionary:
	if path.is_empty():
		return {shape = "rect", rect = rect}
	if f == null or not f.is_binary():
		return {}
	var side: int = path[0]
	var rest: Array[int] = path.slice(1)
	var child := f.left if side == 0 else f.right
	match f.kind:
		Formula.Kind.AND:
			var half := Vector2(rect.size.x * 0.5, rect.size.y)
			return region_of_path(child, Rect2(rect.position + Vector2(side * half.x, 0), half), rest)
		Formula.Kind.IMP:
			var half := Vector2(rect.size.x, rect.size.y * 0.5)
			return region_of_path(child, Rect2(rect.position + Vector2(0, side * half.y), half), rest)
		Formula.Kind.OR:
			var tl := rect.position
			var tr := Vector2(rect.end.x, rect.position.y)
			var bl := Vector2(rect.position.x, rect.end.y)
			var br := rect.end
			if rest.is_empty():
				return {shape = "tri", points = PackedVector2Array([tl, tr, bl]) if side == 0 else PackedVector2Array([tr, br, bl])}
			var inner := Rect2(tl, rect.size * 0.48) if side == 0 else Rect2(br - rect.size * 0.48, rect.size * 0.48)
			return region_of_path(child, inner, rest)
	return {}


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if _parse_failed:
		draw_rect(rect, LINEN)
		draw_line(rect.position, rect.end, Color.MAGENTA, 2.0)
		draw_line(Vector2(rect.end.x, 0), Vector2(0, rect.end.y), Color.MAGENTA, 2.0)
		return
	# 先填色,再描区域边框,最后画分割线:与分割线重合的边框段被分割线盖住(参考图里分割处只有灰条)
	var entries := layout(_formula, rect)
	for e: Dictionary in entries:
		match e.shape:
			"rect":
				_fill_rect_leaf(e)
			"tri":
				_fill_tri_leaf(e)
			"deep":
				draw_rect(e.rect, LINEN.darkened(0.15))
				var c: Vector2 = e.rect.get_center()
				for i in 3:
					draw_circle(c + Vector2((i - 1) * 10.0, 0), 3.0, SPLIT_COLOR)
	for spec: Dictionary in region_borders:
		var reg := region_of_path(_formula, rect, spec.path)
		if reg.is_empty():
			continue
		if reg.shape == "rect":
			draw_rect(reg.rect, spec.color, false, REGION_BORDER_W)
		else:
			var pts: PackedVector2Array = reg.points
			pts.append(pts[0])
			draw_polyline(pts, spec.color, REGION_BORDER_W)
	for e: Dictionary in entries:
		if e.shape == "line":
			draw_line(e.from, e.to, SPLIT_COLOR, e.width)
	if region_borders.is_empty():
		draw_rect(rect, SPLIT_COLOR, false, 2.0)


func _fill_rect_leaf(e: Dictionary) -> void:
	var r: Rect2 = e.rect
	match int(e.kind):
		-1:
			draw_rect(r, LINEN)
		Formula.Kind.ATOM:
			draw_rect(r, atom_color(e.name))
		Formula.Kind.META:
			draw_rect(r, LINEN)
			_draw_hatch(r)
		Formula.Kind.BOT:
			draw_rect(r, CHAR_BLACK)
			_draw_holes(r)


func _fill_tri_leaf(e: Dictionary) -> void:
	var pts: PackedVector2Array = e.points
	match int(e.kind):
		-1:
			draw_colored_polygon(pts, LINEN)
		Formula.Kind.ATOM:
			draw_colored_polygon(pts, atom_color(e.name))
		Formula.Kind.META:
			draw_colored_polygon(pts, LINEN.darkened(0.08))
		Formula.Kind.BOT:
			draw_colored_polygon(pts, CHAR_BLACK)


## 未染纱斜纹:左上→右下平行织线
func _draw_hatch(r: Rect2) -> void:
	var step := 12.0
	var hatch := LINEN.darkened(0.25)
	var d := r.size.x + r.size.y
	var t := step
	while t < d:
		var a := Vector2(r.position.x + minf(t, r.size.x), r.position.y + maxf(0.0, t - r.size.x))
		var b := Vector2(r.position.x + maxf(0.0, t - r.size.y), r.position.y + minf(t, r.size.y))
		draw_line(a, b, hatch, 2.0)
		t += step


## 焦纹破洞:固定伪随机点位(不真随机,重绘稳定)
func _draw_holes(r: Rect2) -> void:
	const SPOTS: Array[Vector2] = [Vector2(0.3, 0.25), Vector2(0.7, 0.6), Vector2(0.45, 0.8), Vector2(0.8, 0.2)]
	for s in SPOTS:
		var p := r.position + s * r.size
		draw_circle(p, maxf(3.0, minf(r.size.x, r.size.y) * 0.07), LINEN.darkened(0.45))


func atom_color(n: StringName) -> Color:
	if atom_colors.has(n):
		return atom_colors[n]
	var h := fmod(absf(float(hash(String(n)))) * 0.618033, 1.0)
	return Color.from_hsv(h, 0.38, 0.86)   # 与 LevelDef.DEFAULT_COLORS 同档的低饱和高明度
