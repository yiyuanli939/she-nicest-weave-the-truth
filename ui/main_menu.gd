class_name MainMenu
extends Control
## 主菜单(占位级 UI,换装走 theme)。

var _notebook_ui: NotebookUI
var _cal_ui: RobotCalUI


func _ready() -> void:
	var game := get_node("/root/Game")
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "She Nicest · 织机证明"
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "[占位] 用丝线织出无可辩驳的纹样"
	sub.modulate.a = 0.7
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(Control.new())

	var progressed: bool = not game.save.solved.is_empty()
	_add_btn(box, "继续织造" if progressed else "开始织造", func() -> void:
		game.start_level(game.first_unsolved()))
	_add_btn(box, "选关", game.goto_select)
	_add_btn(box, "织者笔记", func() -> void:
		_notebook_ui.open(game.notebook, game.save.notebook))
	_add_btn(box, "校准小机", func() -> void:
		_cal_ui.open(get_node("/root/Robot")))
	_add_btn(box, "退出", func() -> void:
		get_node("/root/Robot").cue("sleep")   # 小机道晚安
		await get_tree().create_timer(0.2).timeout
		get_tree().quit())

	_notebook_ui = NotebookUI.new()
	add_child(_notebook_ui)
	_cal_ui = RobotCalUI.new()
	add_child(_cal_ui)

	if not game.menu_greeted:
		game.menu_greeted = true
		# 稍等 WebSocket 连上桥接再问候(连不上则静默)
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			game.robot_cue("greet"))


func _add_btn(box: VBoxContainer, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(240, 42)
	b.pressed.connect(cb)
	box.add_child(b)
