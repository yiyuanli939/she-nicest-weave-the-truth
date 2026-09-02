class_name WireOverlay
extends Control
## 连线视觉叠加层(GraphEdit 的普通 Control 子节点,不吃鼠标,盖在节点之上):
##   * 出错的线在中点挂一枚错误徽章(正常线无浮层)。v1.1 §3:64 号字 + 白描边;会自动断开的三种错线
##     (冲突/成环/逃逸)的徽章停 BADGE_HOLD_SEC 后淡出,ProofBoard 断线前调 detach_chip 把徽章冻结在原位由淡出收尾;
##     「欠定」不是接错,徽章常驻等玩家钉。
##   * 拖线时在鼠标处画插头(尖角圆,v1.1 §1):begin_plug/end_plug 之间只在 _input 收到鼠标移动时重绘,事件驱动。
## 有活徽章时才开 _process 跟随节点(rebuild 时缓存两端 MachineNode 引用,每帧零分配、零查树;
## 没徽章不跑 —— 低功耗模式下静止棋盘不重绘)。
## 徽章是纯文字(只用美术指定字体,不带符号);颜色在 BADGE_COLOR。

const BADGE: Dictionary = {
	ProofSession.WireState.CONFLICT: "冲突",
	ProofSession.WireState.UNDERSPEC: "欠定",
	ProofSession.WireState.CYCLE: "成环",
	ProofSession.WireState.ESCAPED_HYP: "逃逸",
}
const BADGE_COLOR: Dictionary = {
	ProofSession.WireState.CONFLICT: Color(0.85, 0.2, 0.2),
	ProofSession.WireState.UNDERSPEC: Color(0.55, 0.5, 0.4),
	ProofSession.WireState.CYCLE: Color(0.8, 0.45, 0.1),
	ProofSession.WireState.ESCAPED_HYP: Color(0.85, 0.2, 0.2),
}
const BADGE_FONT_SIZE := 64                 # 原 32,策划要求至少放大一倍
const BADGE_OUTLINE := 8
const BADGE_OUTLINE_COLOR := Color.WHITE
const BADGE_HOLD_SEC := 1.0                 # 错线徽章从出现到开始淡出
const BADGE_FADE_SEC := 0.3
## 会自动断开的错线状态(ProofBoard 也用):接错就断;「欠定」保留
const AUTO_BREAK: Array = [ProofSession.WireState.CONFLICT, ProofSession.WireState.CYCLE, ProofSession.WireState.ESCAPED_HYP]

var board: GraphEdit
var session: ProofSession

## {key: Vector4i 边, ctrl: Control, wire: WireInfo, state: int, detached: bool, from_node: MachineNode, to_node: MachineNode}
var _chips: Array[Dictionary] = []
var _plug_on := false
var _plug_pos := Vector2.ZERO
var _plug_color := MachineNode.PORT_COLOR


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	set_process_input(false)


## board_updated 后重建徽章:同一条线、同一状态的旧徽章沿用(不重启淡出计时),其它非冻结徽章释放;
## OK 的线不建浮层;两端节点引用一并缓存,_process 只在有活徽章时跑
func rebuild() -> void:
	var reuse: Dictionary = {}
	var kept: Array[Dictionary] = []
	for c in _chips:
		if c.detached:
			kept.append(c)
		else:
			reuse[c.key] = c
	_chips = kept
	if session != null and board != null:
		for w in session.get_wires():
			if not BADGE.has(w.state):
				continue
			var key := Vector4i(w.from_id, w.from_port, w.to_id, w.to_port)
			var c: Dictionary = reuse.get(key, {})
			if not c.is_empty() and c.state == w.state:
				reuse.erase(key)
			else:
				var chip := _make_chip(w)
				add_child(chip)
				c = {key = key, ctrl = chip, state = w.state, detached = false}
				SoundFx.hit(self, &"error" if AUTO_BREAK.has(w.state) else &"warn")   # 新徽章才响,沿用的不响
				if AUTO_BREAK.has(w.state):
					_start_fade(c)
			c.wire = w
			c.from_node = board.get_node_or_null("n%d" % w.from_id)
			c.to_node = board.get_node_or_null("n%d" % w.to_id)
			_chips.append(c)
	for c in reuse.values():
		(c.ctrl as Control).queue_free()
	set_process(_has_live())


## 这条线要被断开了:徽章留在原位、不再跟随,由淡出收尾(rebuild 不再碰它)
func detach_chip(key: Vector4i) -> void:
	for c in _chips:
		if c.key == key:
			c.detached = true
	set_process(_has_live())


func _has_live() -> bool:
	for c in _chips:
		if not c.detached:
			return true
	return false


func _make_chip(w: ProofSession.WireInfo) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Label.new()
	b.text = BADGE[w.state]
	b.add_theme_font_size_override("font_size", BADGE_FONT_SIZE)
	b.add_theme_color_override("font_color", BADGE_COLOR[w.state])
	b.add_theme_color_override("font_outline_color", BADGE_OUTLINE_COLOR)
	b.add_theme_constant_override("outline_size", BADGE_OUTLINE)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(b)
	return box


func _start_fade(c: Dictionary) -> void:
	var ctrl := c.ctrl as Control
	if not ctrl.is_inside_tree():
		return
	var tw := ctrl.create_tween()
	tw.tween_interval(BADGE_HOLD_SEC)
	tw.tween_property(ctrl, "modulate:a", 0.0, BADGE_FADE_SEC)
	tw.tween_callback(_drop.bind(ctrl))


func _drop(ctrl: Control) -> void:
	for i in range(_chips.size() - 1, -1, -1):
		if _chips[i].ctrl == ctrl:
			_chips.remove_at(i)
	ctrl.queue_free()
	set_process(_has_live())


func _process(_delta: float) -> void:
	for c in _chips:
		if c.detached:
			continue
		var w: ProofSession.WireInfo = c.wire
		var fn := c.from_node as MachineNode
		var tn := c.to_node as MachineNode
		var ctrl := c.ctrl as Control
		if not (is_instance_valid(fn) and is_instance_valid(tn) and fn.is_inside_tree() and tn.is_inside_tree()):
			ctrl.visible = false   # 节点已重建/释放:等下一次 rebuild 重新缓存
			continue
		ctrl.visible = true
		var a: Vector2 = fn.position + fn.port_pos(false, fn.graph_out_port(w.from_port)) * board.zoom
		var b: Vector2 = tn.position + tn.port_pos(true, w.to_port) * board.zoom
		ctrl.position = (a + b) * 0.5 - ctrl.size * 0.5


# ---- 拖线中的插头 ----

func begin_plug(color: Color) -> void:
	_plug_on = true
	_plug_color = color
	_plug_pos = get_local_mouse_position()
	set_process_input(true)
	queue_redraw()


func end_plug() -> void:
	_plug_on = false
	set_process_input(false)
	queue_redraw()


func _input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if _plug_on and mm != null:
		_plug_pos = get_global_transform_with_canvas().affine_inverse() * mm.position
		queue_redraw()


func _draw() -> void:
	if _plug_on:
		MachineNode.draw_plug(self, _plug_pos, _plug_color, board.zoom if board != null else 1.0)
