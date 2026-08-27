class_name DialogueBox
extends CanvasLayer
## 入场对话框:打字机 + 点击推进(打字中点击=全显,播完再点=下一句/关闭)。
## robot_cue 逐行转发(cue 信号)。视觉为占位级;美术换装走 theme(见 docs/ART_INTERFACE.md)。

signal finished
signal cue(cue_name: String)
signal line_shown(line: DialogueLine)

const CHARS_PER_SEC := 40.0

var _lines: Array[DialogueLine] = []
var _idx := -1
var _panel: PanelContainer
var _speaker: Label
var _text: RichTextLabel
var _tween: Tween
var _click_catcher: Control


func _init() -> void:
	layer = 50
	_click_catcher = Control.new()
	_click_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_click_catcher.gui_input.connect(_on_click)
	add_child(_click_catcher)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -170
	_panel.offset_left = 60
	_panel.offset_right = -60
	_panel.offset_bottom = -24
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 18)
	top.add_child(_speaker)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	box.add_child(top)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_text)
	var tip := Label.new()
	tip.text = "点击继续"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tip.add_theme_font_size_override("font_size", 11)
	tip.modulate.a = 0.6
	box.add_child(tip)
	_panel.add_child(box)
	add_child(_panel)
	visible = false


func play(dlg: DialogueRes) -> void:
	if dlg == null or dlg.lines.is_empty():
		finished.emit()
		return
	_lines = dlg.lines
	_idx = -1
	visible = true
	_advance()


func _advance() -> void:
	_idx += 1
	if _idx >= _lines.size():
		_finish()
		return
	var line := _lines[_idx]
	_speaker.text = line.speaker
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if line.side_right else HORIZONTAL_ALIGNMENT_LEFT
	_text.text = line.text
	line_shown.emit(line)
	if line.robot_cue != "":
		cue.emit(line.robot_cue)
	_text.visible_characters = 0
	if _tween != null:
		_tween.kill()
	var total := _text.get_total_character_count()
	_tween = _text.create_tween()
	_tween.tween_property(_text, "visible_characters", total, total / CHARS_PER_SEC)


func _on_click(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _text.visible_characters < _text.get_total_character_count():
		if _tween != null:
			_tween.kill()
		# 不能设 -1:getter 也返回 -1,会让上面的"打字中"判断永真,点击就再也推进不了
		_text.visible_characters = _text.get_total_character_count()
	else:
		_advance()


func _finish() -> void:
	if _tween != null:
		_tween.kill()
	visible = false
	finished.emit()
