class_name RobotCalUI
extends CanvasLayer
## 小机"看电脑方向"校准界面(占位级 UI)。
## 自动:小机左右张望,正对屏幕时朝它挥手(或按它的 BOOT 键)锁定;
## 手动:方向键微调云台,再"保存为屏幕方向"。

var _status: Label
var _robot: Node


func _init() -> void:
	layer = 60
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	# 用 CenterContainer 包 panel 才是真居中(裸 PRESET_CENTER 只设锚点不设 offset,会向右下溢出)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	var title := Label.new()
	title.text = "校准小机:看电脑方向"
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)
	var help := Label.new()
	help.text = "自动:点开始后小机会左右张望,\n当它正对电脑屏幕时,朝它挥挥手(或按它的 BOOT 键)。\n手动:用方向键微调,再保存。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	_status = Label.new()
	_status.text = ""
	box.add_child(_status)

	var auto_btn := Button.new()
	auto_btn.text = "开始自动校准(挥手锁定)"
	auto_btn.pressed.connect(_on_auto)
	box.add_child(auto_btn)

	var manual := HBoxContainer.new()
	manual.alignment = BoxContainer.ALIGNMENT_CENTER
	for spec in [["左", -6, 0], ["右", 6, 0], ["上", 0, -6], ["下", 0, 6]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(110, 90)
		b.pressed.connect(func() -> void: _robot.nudge(spec[1], spec[2]))
		manual.add_child(b)
	var save := Button.new()
	save.text = "保存为屏幕方向"
	save.pressed.connect(func() -> void:
		_robot.save_look_here()
		_status.text = "已请求保存…")
	manual.add_child(save)
	box.add_child(manual)

	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func() -> void: visible = false)
	box.add_child(close)
	panel.add_child(box)
	center.add_child(panel)


func open(robot: Node) -> void:
	_robot = robot
	if not robot.robot_event.is_connected(_on_event):
		robot.robot_event.connect(_on_event)
	_status.text = "小机在线" if robot.connected else "小机离线(先跑桥接:hardware/bridge)"
	visible = true


func _on_auto() -> void:
	_robot.calibrate_look()
	_status.text = "小机张望中…正对屏幕时朝它挥手!"


func _on_event(d: Dictionary) -> void:
	match d.get("evt", ""):
		"cal_done":
			_status.text = "已锁定屏幕方向 pan=%s tilt=%s" % [d.get("pan"), d.get("tilt")]
		"cal_timeout":
			_status.text = "超时了,再试一次?"
