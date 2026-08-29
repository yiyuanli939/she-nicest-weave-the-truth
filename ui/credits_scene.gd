class_name CreditsScene
extends Control
## 开发者信息页(美术:「和选关界面采用相同底图,上面只放文字」):作者、免费素材、参考作品,先写占位。
## 页面上没有按钮:Esc 或点击任意处回标题。

const BG_PATH := "res://assets/art/select/bg.png"
const TITLE_FONT_SIZE := 80
const TEXT_FONT_SIZE := 52
const TITLE_COLOR := Color(0.627, 0.275, 0.227)
const LINE_GAP := 28

# 占位文案:改这里即可
const LINES: Array[String] = [
	"[占位] 作者:She Nicest 团队",
	"[占位] 美术:待补充",
	"字体:站酷小薇体(ZCOOL XiaoWei,免费商用授权)",
	"引擎:Godot 4.7",
	"参考作品:The Incredible Proof Machine(incredible.pm)",
	"[占位] 感谢:待补充",
]


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = load(BG_PATH)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", LINE_GAP)
	center.add_child(box)
	var title := Label.new()
	title.text = "开发者信息"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(Control.new())
	for line in LINES:
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(lbl)


func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if event.is_action_pressed("ui_cancel") or (mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		get_node("/root/Game").goto_menu()
