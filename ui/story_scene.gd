class_name StoryScene
extends Control
## 进关前的全屏开场对话场景:底图 + 背景插图 + 地点铭牌 + 左右立绘 + 对话框。
## 美术全为占位:DialogueRes.background / DialogueLine.portrait 为 null 时
## 用程序化色块/剪影回退(槽位约定见 docs/ART_INTERFACE.md)。
## 播完(或对话为空)切入棋盘;点击任意处推进由 DialogueBox 的全屏捕捉层负责。

const BASE_COLOR := Color(0.16, 0.13, 0.10)        # 底图:深羊皮纸
const CANVAS_COLOR := Color(0.82, 0.74, 0.58)      # 插图占位:亮羊皮纸
const CANVAS_BORDER := Color(0.45, 0.36, 0.22)
const DIM := Color(0.45, 0.45, 0.45, 0.7)          # 非当前说话侧的立绘压暗

var _dialogue: DialogueBox
var _bg_slot: Panel
var _portraits: Array[Control] = [null, null]      # [左, 右]
var _leaving := false


func _ready() -> void:
	var game := get_node_or_null("/root/Game")
	var dlg: DialogueRes = game.current.intro_dialogue if game != null and game.current != null else null
	_build_ui(game, dlg)
	if dlg == null or dlg.lines.is_empty():
		_go_board()
		return
	_dialogue.finished.connect(_go_board)
	if game != null:
		_dialogue.cue.connect(game.robot_cue)
	_dialogue.line_shown.connect(_on_line_shown)
	_dialogue.play(dlg)


## 测试/调试入口:一键播完并进棋盘
func finish() -> void:
	_dialogue._finish()


func _build_ui(game: Node, dlg: DialogueRes) -> void:
	var base := ColorRect.new()
	base.color = BASE_COLOR
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(base)

	_bg_slot = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CANVAS_COLOR
	sb.border_color = CANVAS_BORDER
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(8)
	_bg_slot.add_theme_stylebox_override("panel", sb)
	_bg_slot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_slot.offset_left = 90
	_bg_slot.offset_right = -90
	_bg_slot.offset_top = 70
	_bg_slot.offset_bottom = -210
	add_child(_bg_slot)
	if dlg != null and dlg.background != null:
		var tex := TextureRect.new()
		tex.texture = dlg.background
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		_bg_slot.add_child(tex)

	var title := ""
	if dlg != null and dlg.location_title != "":
		title = dlg.location_title
	elif game != null and game.current != null:
		title = game.current.title
	var plate := PanelContainer.new()
	plate.position = Vector2(24, 20)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 20)
	plate.add_child(lbl)
	add_child(plate)

	for right in [false, true]:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(200, 300)
		slot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT if right else Control.PRESET_BOTTOM_LEFT)
		slot.offset_bottom = -190
		slot.offset_top = -490
		if right:
			slot.offset_right = -70
			slot.offset_left = -270
		else:
			slot.offset_left = 70
			slot.offset_right = 270
		slot.visible = false
		add_child(slot)
		_portraits[1 if right else 0] = slot

	_dialogue = DialogueBox.new()
	add_child(_dialogue)


func _on_line_shown(line: DialogueLine) -> void:
	var idx := 1 if line.side_right else 0
	_fill_portrait(_portraits[idx], line)
	_portraits[idx].visible = true
	_portraits[idx].modulate = Color.WHITE
	var other := _portraits[1 - idx]
	if other.visible:
		other.modulate = DIM


func _fill_portrait(slot: Control, line: DialogueLine) -> void:
	for c in slot.get_children():
		c.queue_free()
	if line.portrait != null:
		var tex := TextureRect.new()
		tex.texture = line.portrait
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(tex)
		return
	# 剪影占位:按 speaker 哈希着色的圆头 + 圆肩躯干
	var tint := Color.from_hsv(float(absi(hash(line.speaker)) % 360) / 360.0, 0.35, 0.72)
	var head := Panel.new()
	var head_sb := StyleBoxFlat.new()
	head_sb.bg_color = tint
	head_sb.set_corner_radius_all(45)
	head.add_theme_stylebox_override("panel", head_sb)
	head.position = Vector2(55, 20)
	head.size = Vector2(90, 90)
	slot.add_child(head)
	var body := Panel.new()
	var body_sb := StyleBoxFlat.new()
	body_sb.bg_color = tint
	body_sb.corner_radius_top_left = 60
	body_sb.corner_radius_top_right = 60
	body.add_theme_stylebox_override("panel", body_sb)
	body.position = Vector2(20, 118)
	body.size = Vector2(160, 182)
	slot.add_child(body)


func _go_board() -> void:
	if _leaving:
		return
	_leaving = true
	var game := get_node_or_null("/root/Game")
	if game != null:
		game.enter_board()
