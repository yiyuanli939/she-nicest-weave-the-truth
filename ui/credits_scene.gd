class_name CreditsScene
extends Control
## 开发者信息页(美术:「和选关界面采用相同底图,上面只放文字」):作者、免费素材、参考作品,先写占位。
## 底部纯文字按钮「小机维护」(接入小机 / 刷固件 / 校准 / 回头方向),左上角「返回主界面」(BackButton);
## 其余 Esc 或点击任意处回标题。

const BG_PATH := "res://assets/art/select/bg.png"
const TITLE_FONT_SIZE := 80
const TEXT_FONT_SIZE := 52
const TITLE_COLOR := Color(0.627, 0.275, 0.227)
const LINE_GAP := 28
const MAINT_FONT_SIZE := 48
const ENDING_FADE_SEC := 0.8   # 结局进来时从纯黑淡入(「淡出到开发者信息界面」)

var _maint: RobotMaintUI
var _maint_btn: Button
var _back_btn: Button

# 署名文案:改这里即可(文字须全部在站酷小薇体里,test_theme 会扫)
const LINES: Array[String] = [
	"美术与策划:焰陶",
	"音乐与硬件:lyy(李熠远)",
	"程序:LLM 与 焰陶、lyy 合作完成",
	"字体:站酷小薇体(ZCOOL XiaoWei,免费商用授权);个别字形回退 Noto Sans SC(OFL)",
	"标题音乐:舒伯特 A 大调钢琴奏鸣曲 D.664 第二乐章 Andante,演奏 Paul Pitman,公有领域(CC PD)",
	"关内音乐:李熠远 与 ChatGPT 共同生成",
	"引擎:Godot 4.7",
	"参考作品:The Incredible Proof Machine(incredible.pm)、陶哲轩 Q.E.D.",
]


func _ready() -> void:
	var bgm := get_node_or_null("/root/Bgm")
	if bgm != null:
		bgm.play(&"title")
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
	box.add_child(Control.new())
	_maint_btn = Button.new()
	_maint_btn.text = "小机维护"
	_maint_btn.add_theme_font_size_override("font_size", MAINT_FONT_SIZE)
	_maint_btn.pressed.connect(func() -> void: _maint.open(get_node("/root/Robot")))
	box.add_child(_maint_btn)
	_maint = RobotMaintUI.new()
	add_child(_maint)
	_back_btn = BackButton.make(get_node("/root/Game").goto_menu)
	add_child(_back_btn)
	var game := get_node_or_null("/root/Game")
	if game != null and game.credits_fade_pending:
		game.credits_fade_pending = false
		var fade := ColorRect.new()
		fade.color = Color.BLACK
		fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fade)
		var tw := create_tween()
		tw.tween_property(fade, "modulate:a", 0.0, ENDING_FADE_SEC)
		tw.tween_callback(fade.queue_free)


func _input(event: InputEvent) -> void:
	if _maint != null and _maint.visible:
		return   # 维护面板开着:交给面板
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		for btn: Button in [_maint_btn, _back_btn]:
			if btn != null and btn.get_global_rect().has_point(mb.position):
				return   # 点的是页内按钮,交给按钮自己处理
	if event.is_action_pressed("ui_cancel") or (mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		get_node("/root/Game").goto_menu()
