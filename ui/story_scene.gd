class_name StoryScene
extends Control
## 全屏故事界面(美术参考图 information/art_spec_20260829/image 2.png、image 3.png):
## 固定底图 + 场景插图 + 左右立绘(主角诺拉恒右,左侧人物可空)+ 对话文字区。
## 两人同在时,没在说话的人叠一张 50% 透明遮罩(与立绘完全重合)。不显示场景/地点名。
## 进关前播 intro_dialogue,播完(或对话为空)切入棋盘;推进由 DialogueBox 在 _input 层截获左键/任意键。
## 结局(Game.ending_pending):改播 outro_dialogue,播完淡入纯黑 + 白色大字「感谢游玩」(剧情表注意事项②),
## 黑屏时小机修好(broken=false + calm),再由 Game.finish_ending 淡出到开发者信息页。
## 坐标为 3840×2160 逻辑像素,图片原尺寸;美术调位置改下面常量。

const BASE_PATH := "res://assets/art/story/base.png"
const BASE_POS := Vector2(2, 18)                     # 底图 3835×2123 左上角(居中)
const SCENE_RECT := Rect2(955, 89, 1942, 1251)       # 场景插图区(图 1942×1251 原尺寸)
const LEFT_FRAME := Rect2(79, 133, 834, 1879)        # 左立绘框(超出部分裁掉)
const RIGHT_FRAME := Rect2(2926, 133, 834, 1879)     # 右立绘框(诺拉)
# 立绘默认「框内水平居中、底边对齐框底」,这里按角色再微调(像素)
const PORTRAIT_NUDGE: Dictionary = {"诺拉": Vector2.ZERO, "莉娅": Vector2.ZERO, "亚瑟": Vector2.ZERO}
const NAME_POS := Vector2(1040, 1490)                # 发言人名字左上角
const TEXT_RECT := Rect2(1040, 1590, 1780, 420)      # 台词区
const MASK_ALPHA := 0.5
const THANKS_FADE_SEC := 0.8    # 感谢游玩黑屏淡入时长
const THANKS_HOLD_SEC := 1.6    # 黑屏停留(此刻小机修好),随后进开发者信息页
const THANKS_FONT_SIZE := 96    # 「稍微大一些的字号」:台词 48 的两倍

var _dialogue: DialogueBox
var _scene_pic: TextureRect
var _slots: Array[Control] = [null, null]            # [左, 右] 裁剪框
var _portraits: Array[TextureRect] = [null, null]
var _masks: Array[TextureRect] = [null, null]
var _leaving := false
var _outro := false


func _ready() -> void:
	var game := get_node_or_null("/root/Game")
	_outro = game != null and game.ending_pending
	var dlg: DialogueRes = null
	if game != null and game.current != null:
		dlg = game.current.outro_dialogue if _outro else game.current.intro_dialogue
	var bgm := get_node_or_null("/root/Bgm")
	if bgm != null:
		bgm.play(bgm.slot_for_chapter(game.current_chapter() if game != null else -1))
	_build_ui()
	if dlg == null or dlg.lines.is_empty():
		_on_dialogue_finished()
		return
	_dialogue.finished.connect(_on_dialogue_finished)
	if game != null:
		_dialogue.cue.connect(game.robot_cue)
	_dialogue.line_shown.connect(_on_line_shown)
	_dialogue.play(dlg)


## 测试/调试入口:一键播完并进棋盘
func finish() -> void:
	_dialogue._finish()


func _build_ui() -> void:
	var base := TextureRect.new()
	base.texture = load(BASE_PATH)
	base.position = BASE_POS
	base.size = base.texture.get_size()
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	_scene_pic = TextureRect.new()
	_scene_pic.position = SCENE_RECT.position
	_scene_pic.size = SCENE_RECT.size
	_scene_pic.stretch_mode = TextureRect.STRETCH_KEEP
	_scene_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_pic.visible = false
	add_child(_scene_pic)

	for side in 2:
		var frame := RIGHT_FRAME if side == 1 else LEFT_FRAME
		var slot := Control.new()
		slot.position = frame.position
		slot.size = frame.size
		slot.clip_contents = true
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.visible = false
		add_child(slot)
		var pic := TextureRect.new()
		pic.stretch_mode = TextureRect.STRETCH_KEEP
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(pic)
		var mask := TextureRect.new()
		mask.stretch_mode = TextureRect.STRETCH_KEEP
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mask.modulate.a = MASK_ALPHA
		mask.visible = false
		slot.add_child(mask)
		_slots[side] = slot
		_portraits[side] = pic
		_masks[side] = mask

	_dialogue = DialogueBox.new()
	_dialogue.layout(NAME_POS, TEXT_RECT)
	add_child(_dialogue)


func _on_line_shown(line: DialogueLine) -> void:
	if line.scene != "":
		var tex := StoryArt.scene(line.scene)
		if tex != null:   # 无效场景名/缺图:保持上一张,别把插图弄消失
			_scene_pic.texture = tex
			_scene_pic.visible = true
	_set_portrait(1, StoryArt.NORA, line.nora_expr)
	_set_portrait(0, line.left_char, line.left_expr)
	# 遮罩规则:发言人不是这幅立绘的人 → 压暗。第三方(画外音,如占位的阿梭/档案员)说话时两侧都压。
	var both := _slots[0].visible and _slots[1].visible
	var speaking := StoryArt.character_of(line.speaker)
	_masks[0].visible = both and speaking != line.left_char
	_masks[1].visible = both and not StoryArt.is_nora(line.speaker)


## 立绘原尺寸,框内水平居中、底边对齐框底,再加逐角色微调;遮罩与立绘同位同尺寸
func _set_portrait(side: int, char_name: String, expr: String) -> void:
	var slot := _slots[side]
	if char_name == "":
		slot.visible = false
		return
	var tex := StoryArt.portrait(char_name, expr)
	if tex == null and expr != "默认":
		tex = StoryArt.portrait(char_name, "默认")
	if tex == null:
		slot.visible = false
		return
	var pic := _portraits[side]
	pic.texture = tex
	pic.size = tex.get_size()
	pic.position = Vector2((slot.size.x - pic.size.x) * 0.5, slot.size.y - pic.size.y) + PORTRAIT_NUDGE.get(char_name, Vector2.ZERO)
	var mask := _masks[side]
	mask.texture = StoryArt.mask(char_name)
	mask.size = pic.size
	mask.position = pic.position
	slot.visible = true


func _on_dialogue_finished() -> void:
	if _outro:
		_play_thanks()
	else:
		_go_board()


## 结局收尾:黑幕 + 「感谢游玩」一起淡入 → 停一会儿(小机修好)→ 开发者信息页
func _play_thanks() -> void:
	if _leaving:
		return
	_leaving = true
	var overlay := ColorRect.new()
	overlay.color = Color.BLACK
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.modulate.a = 0.0
	add_child(overlay)
	var lbl := Label.new()
	lbl.text = "感谢游玩"
	lbl.add_theme_font_size_override("font_size", THANKS_FONT_SIZE)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_child(lbl)
	var robot := get_node_or_null("/root/Robot")
	if robot != null:
		robot.broken = false   # 剧情:结局里小织修好了
		robot.cue("calm")
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, THANKS_FADE_SEC)
	tw.tween_interval(THANKS_HOLD_SEC)
	tw.tween_callback(_finish_ending)


func _finish_ending() -> void:
	var game := get_node_or_null("/root/Game")
	if game != null:
		game.finish_ending()


func _go_board() -> void:
	if _leaving:
		return
	_leaving = true
	var game := get_node_or_null("/root/Game")
	if game != null:
		game.enter_board()
	else:
		push_warning("StoryScene: 没有 Game autoload,直接进默认关卡场景(调试路径)")
		get_tree().change_scene_to_file("res://ui/level_scene.tscn")
