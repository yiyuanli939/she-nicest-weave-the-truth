class_name LevelSelect
extends Control
## 选关页(美术参考图 information/art_spec_20260829/image 1.png):
## 底图 + 每章「第N章 X」标题 + 章内关卡按钮(已解锁 / 未解锁两张图 + 「第N纹」文字)。
## 全部章节关卡初始可见,线性解锁(Game.is_unlocked)。参考图没有返回按钮:Esc 回标题。
## 坐标为 3840×2160 逻辑像素;美术调间距改下面常量。

const BG_PATH := "res://assets/art/select/bg.png"
const BTN_UNLOCKED := "res://assets/art/select/level_unlocked.png"
const BTN_LOCKED := "res://assets/art/select/level_locked.png"
const CHAPTER_FONT_SIZE := 80
const LEVEL_FONT_SIZE := 48
const CHAPTER_GAP := 70      # 章与章之间
const TITLE_GAP := 24        # 章标题与按钮行之间
const ROW_GAP := 60          # 同一行按钮之间
const CHAPTER_COLOR := Color(0.627, 0.275, 0.227)   # 红棕
const LEVEL_COLOR := Color(0.627, 0.275, 0.227)
const LOCKED_TEXT_COLOR := Color(0.36, 0.3, 0.3, 0.6)

var _game: Node


func _ready() -> void:
	_game = get_node("/root/Game")
	var bg := TextureRect.new()
	bg.texture = load(BG_PATH)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var chapters := VBoxContainer.new()
	chapters.add_theme_constant_override("separation", CHAPTER_GAP)
	center.add_child(chapters)

	var idx := 0
	for ch: ChapterDef in _game.catalog.chapters:
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", TITLE_GAP)
		var ch_lbl := Label.new()
		ch_lbl.text = ch.title
		ch_lbl.add_theme_font_size_override("font_size", CHAPTER_FONT_SIZE)
		ch_lbl.add_theme_color_override("font_color", CHAPTER_COLOR)
		ch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		block.add_child(ch_lbl)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", ROW_GAP)
		for lv: LevelDef in ch.levels:
			row.add_child(_make_level_button(lv, _game.is_unlocked(idx)))
			idx += 1
		block.add_child(row)
		chapters.add_child(block)


## 关卡按钮 = 美术的牌子图(原尺寸)+ 关名文字;未解锁换灰牌并禁用
func _make_level_button(lv: LevelDef, unlocked: bool) -> Button:
	var tex: Texture2D = load(BTN_UNLOCKED if unlocked else BTN_LOCKED)
	var b := Button.new()
	b.text = lv.title
	b.custom_minimum_size = tex.get_size()
	b.disabled = not unlocked
	b.add_theme_font_size_override("font_size", LEVEL_FONT_SIZE)
	b.add_theme_color_override("font_color", LEVEL_COLOR)
	b.add_theme_color_override("font_disabled_color", LOCKED_TEXT_COLOR)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		if state == "hover":
			sb.modulate_color = Color(1.08, 1.08, 1.08)
		elif state == "pressed":
			sb.modulate_color = Color(0.92, 0.92, 0.92)
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(_game.start_level.bind(lv))
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_game.goto_menu()
