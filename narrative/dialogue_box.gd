class_name DialogueBox
extends Control
## 对话文字区:名字 + 台词打字机 + 推进(打字中 点击/按键 = 整句显示;显示完再点 = 下一句;最后一句后再点 = 关闭)。
## 显示期间是模态的:左键与任意键在 _input 层截获(点面板、点台词、点任意处都推进),
## 不用全屏捕捉 Control —— 那样面板本身会先吃掉点击,点在台词上就不推进。
## 只管文字,没有自己的底(底图/立绘由 StoryScene 摆,底图右下角已印「按任意键继续」);
## 位置由宿主调 layout()。robot_cue 逐行转发(cue 信号)。

signal finished
signal cue(cue_name: String)
signal line_shown(line: DialogueLine)

const CHARS_PER_SEC := 40.0
const NAME_FONT_SIZE := 56
const TEXT_FONT_SIZE := 48
const NAME_COLOR := Color(0.627, 0.275, 0.227)   # 红棕(参考图里名字的颜色)
const TEXT_COLOR := Color(0.29, 0.184, 0.165)    # 深棕

var _lines: Array[DialogueLine] = []
var _idx := -1
var _speaker: Label
var _text: RichTextLabel
var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_speaker.add_theme_color_override("font_color", NAME_COLOR)
	_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_speaker)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.add_theme_font_size_override("normal_font_size", TEXT_FONT_SIZE)
	_text.add_theme_color_override("default_color", TEXT_COLOR)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	visible = false


## 名字左上角与台词矩形(逻辑像素);宿主按自己的底图定
func layout(name_pos: Vector2, text_rect: Rect2) -> void:
	_speaker.position = name_pos
	_text.position = text_rect.position
	_text.size = text_rect.size


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
	_speaker.text = StoryArt.display_name(line.speaker)
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


## 模态截获:左键(按下与抬起都不放给下层)与任意键(按下)都推进
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		get_viewport().set_input_as_handled()
		if mb.pressed:
			_step()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		# 纯修饰键(切输入法/截屏/Cmd+Tab 都会先按下修饰键)不算"任意键";
		# Esc 留给将来的退出/暂停(否则想退出的玩家反而被推进关),功能键留给调试(F9)。
		if key.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_ESCAPE] \
				or (key.keycode >= KEY_F1 and key.keycode <= KEY_F12):
			return
		get_viewport().set_input_as_handled()
		_step()


func _step() -> void:
	if _text.visible_characters < _text.get_total_character_count():
		if _tween != null:
			_tween.kill()
		# 不能设 -1:getter 也返回 -1,会让上面的"打字中"判断永真,点击就再也推进不了
		_text.visible_characters = _text.get_total_character_count()
	else:
		_advance()


## 幂等:已经关掉的对话再调不会重复发 finished
func _finish() -> void:
	if not visible:
		return
	if _tween != null:
		_tween.kill()
	visible = false
	finished.emit()
