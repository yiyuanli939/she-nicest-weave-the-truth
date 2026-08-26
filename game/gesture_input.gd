class_name GestureInput
extends CanvasLayer
## 手势 → 虚拟光标层(由 Robot autoload 持有,全场景生效)。
## 吃 teleop 手部包:移动=合成 InputEventMouseMotion,捏合=左键按下/抬起,握拳=右键。
## 走 Input.parse_input_event 注入,现有全部 UI(GraphEdit/按钮/编辑器)免改可用。

const MARGIN := 0.08          # 画面边缘留白映射,手不用伸到摄像头边角
const SMOOTH := 0.45          # EMA 系数(包到达时应用,~20Hz)
const HIDE_AFTER_MS := 600    # 无手多久后隐藏光标并松开按键

var clicks := 0               # 调试/冒烟计数:注入过多少次左键按下

var _cursor: Control
var _pos := Vector2.ZERO
var _seen := false
var _seen_at := 0
var _pinch := false
var _fist := false


func _ready() -> void:
	layer = 100
	_cursor = _HandCursor.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.visible = false
	add_child(_cursor)


func on_hand(d: Dictionary) -> void:
	if not d.get("seen", false):
		_seen = false
		return
	var vp := _cursor.get_viewport_rect().size
	var nx: float = clampf((float(d.get("x", 0.5)) - MARGIN) / (1.0 - 2 * MARGIN), 0.0, 1.0)
	var ny: float = clampf((float(d.get("y", 0.5)) - MARGIN) / (1.0 - 2 * MARGIN), 0.0, 1.0)
	var target := Vector2(nx * vp.x, ny * vp.y)
	if not _seen:
		_pos = target   # 手重新出现:跳过去,别从旧位置飘
	_seen = true
	_seen_at = Time.get_ticks_msec()
	var old := _pos
	_pos = _pos.lerp(target, SMOOTH)
	_cursor.visible = true
	_cursor.position = _pos - _cursor.size * 0.5

	var motion := InputEventMouseMotion.new()
	motion.position = _pos
	motion.global_position = _pos
	motion.relative = _pos - old
	Input.parse_input_event(motion)

	_edge(bool(d.get("pinch", false)), MOUSE_BUTTON_LEFT)
	_edge_fist(bool(d.get("fist", false)))
	_cursor.set_state(_pinch, _fist)


func _edge(now_pressed: bool, _btn: int) -> void:
	if now_pressed == _pinch:
		return
	_pinch = now_pressed
	if now_pressed:
		clicks += 1
	_send_button(MOUSE_BUTTON_LEFT, now_pressed)


func _edge_fist(now_fist: bool) -> void:
	if now_fist == _fist:
		return
	_fist = now_fist
	_send_button(MOUSE_BUTTON_RIGHT, now_fist)


func _send_button(btn: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = pressed
	ev.position = _pos
	ev.global_position = _pos
	Input.parse_input_event(ev)


func _process(_delta: float) -> void:
	# 超时没有"看到手"的包(手离开或 teleop 进程已停)→ 收光标
	if _cursor.visible and Time.get_ticks_msec() - _seen_at > HIDE_AFTER_MS:
		# 手离开:先松开一切按住的键,避免"幽灵拖拽"
		if _pinch:
			_pinch = false
			_send_button(MOUSE_BUTTON_LEFT, false)
		if _fist:
			_fist = false
			_send_button(MOUSE_BUTTON_RIGHT, false)
		_cursor.visible = false


## 手形光标:圆环,捏合实心变金,握拳变红
class _HandCursor:
	extends Control
	var _pinch := false
	var _fist := false

	func _init() -> void:
		size = Vector2(36, 36)

	func set_state(p: bool, f: bool) -> void:
		if p != _pinch or f != _fist:
			_pinch = p
			_fist = f
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(0.9, 0.76, 0.28) if _pinch else \
				(Color(0.85, 0.3, 0.25) if _fist else Color(0.95, 0.92, 0.85))
		draw_arc(c, 13.0, 0, TAU, 32, col, 3.0, true)
		if _pinch:
			draw_circle(c, 7.0, col)
		else:
			draw_circle(c, 2.5, col)
