class_name PalettePanel
extends Control
## 仪器架(美术参考图 information/art_spec_20260829/image 4.png 左栏):底图 + 固定 7 个仪器按钮,
## 顺序与按钮图的分配严格按图(合取类 = 并织/拆股,蕴含类 = 封程/引渡,析取类 = 岔纹/汇路,矛盾类 = 溃散)。
## 本关未上架的仪器(不在 allowed_rules)不显示,可见按钮按图顺序紧凑排列;点击请求放置。只发信号,不碰 GraphEdit。
## 坐标为架内 / 3840×2160 逻辑像素,图片原尺寸;美术调位置改下面常量。

signal machine_requested(rule_id: StringName)

const BG_PATH := "res://assets/art/level/palette_bg.png"      # 687×2117
const SLOT_ORDER: Array[StringName] = [&"and_intro", &"and_elim", &"imp_intro", &"imp_elim", &"or_intro", &"or_elim", &"false_elim"]
const SLOT_IMAGE: Dictionary = {
	&"and_intro": "res://assets/art/level/machine_and.png", &"and_elim": "res://assets/art/level/machine_and.png",
	&"imp_intro": "res://assets/art/level/machine_imp.png", &"imp_elim": "res://assets/art/level/machine_imp.png",
	&"or_intro": "res://assets/art/level/machine_or.png", &"or_elim": "res://assets/art/level/machine_or.png",
	&"false_elim": "res://assets/art/level/machine_bot.png",
}
const SLOT_X := 80.0          # 按钮左上角 x(架内)
const SLOT_Y0 := 262.0        # 第一个按钮的 y(架内)
const SLOT_PITCH := 210.0     # 按钮间距(按钮图 526×182)
const NAME_FONT_SIZE := 56
const NAME_COLOR := Color(0.29, 0.184, 0.165)

var _buttons: Dictionary = {}   # rule_id -> Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := TextureRect.new()
	bg.texture = load(BG_PATH)
	bg.size = bg.texture.get_size()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	custom_minimum_size = bg.size
	for i in SLOT_ORDER.size():
		var rule_id := SLOT_ORDER[i]
		var info := ProofSession.describe_rule(rule_id)
		var tex: Texture2D = load(SLOT_IMAGE[rule_id])
		var btn := Button.new()
		btn.text = info.cn_name if info != null else String(rule_id)
		btn.position = Vector2(SLOT_X, SLOT_Y0 + i * SLOT_PITCH)
		btn.size = tex.get_size()
		btn.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
		btn.add_theme_color_override("font_color", NAME_COLOR)
		for state in ["normal", "hover", "pressed", "disabled"]:
			var sb := StyleBoxTexture.new()
			sb.texture = tex
			match state:
				"hover": sb.modulate_color = Color(1.08, 1.08, 1.08)
				"pressed": sb.modulate_color = Color(0.92, 0.92, 0.92)
				"disabled": sb.modulate_color = Color(0.62, 0.6, 0.58)
			btn.add_theme_stylebox_override(state, sb)
		btn.disabled = true
		btn.visible = false   # set_rules 之前不闪 7 台
		btn.pressed.connect(machine_requested.emit.bind(rule_id))
		add_child(btn)
		_buttons[rule_id] = btn


## 只显示本关上架的仪器,位置按可见顺序紧凑重排(未上架的不显示,不留空槽)
func set_rules(ids: Array[StringName]) -> void:
	var k := 0
	for rule_id in SLOT_ORDER:
		var btn := _buttons[rule_id] as Button
		btn.visible = ids.has(rule_id)
		btn.disabled = not btn.visible
		if btn.visible:
			btn.position.y = SLOT_Y0 + k * SLOT_PITCH
			k += 1


func button_of(rule_id: StringName) -> Button:
	return _buttons.get(rule_id)
