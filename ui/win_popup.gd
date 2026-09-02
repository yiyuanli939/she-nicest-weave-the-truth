class_name WinPopup
extends CanvasLayer
## 通关弹窗「织成了」(v1.2 策划说明 `v1.2背景/`):过关时居中弹出美术图(原尺寸 1174×816,不缩放不改长宽),
## 图的中下一个纯文字「继续」按钮 —— 有下一关进下一关,末关进结局(由 LevelScene 接 continue_pressed 决定)。
## 只有「继续」一个出口:不吃 Esc、没有关闭键(说明只写了这一个按钮)。
## 骨架同 SettingsPanel:遮罩 ColorRect(默认 STOP,挡住后面的棋盘)+ CenterContainer 真居中。
## 美术文档没写的部分先按常量留位(遮罩色 / 按钮位置 / 字号 / 字色),要改只动下面的常量:
##   「继续」中心 (587, 640) 取自实测:标题下花纹到 y 508、底框从 y 748 起,中间 512–744 是空白带,
##   64 号字加主题上下 12 内边距约 88 高 → 596–684,不压花纹不压框;字色取图内标题金(主题棕字在紫褐底上看不清)。

signal continue_pressed

const IMAGE_PATH := "res://assets/art/level/win_popup.png"
const LAYER := 70                                  # 压过笔记抽屉(NotebookUI 60):通关瞬间抽屉可能开着
const DIM_COLOR := Color(0, 0, 0, 0.45)            # 与标题页「设置」弹窗同值
const CONTINUE_CENTER := Vector2(587, 640)         # 「继续」中心(图内坐标,图 1174×816)
const CONTINUE_FONT_SIZE := 64
const CONTINUE_COLOR := Color("D1A94D")            # 图内「织成了!」的金
const CONTINUE_HOVER_COLOR := Color("EBD08A")      # 悬停更浅(主题文字按钮的「悬停变浅」惯例)

var _panel: TextureRect
var _continue_btn: Button


func _init() -> void:
	layer = LAYER
	visible = false
	var dim := ColorRect.new()   # 默认 mouse_filter = STOP:挡住后面的棋盘
	dim.color = DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()   # 用 CenterContainer 包才是真居中(裸 PRESET_CENTER 只设锚点不设 offset)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	# 图本身就是弹窗面板:默认 EXPAND_KEEP_SIZE 下最小尺寸 = 纹理尺寸,容器给它原尺寸;STRETCH_KEEP 兜底不缩放
	_panel = TextureRect.new()
	_panel.texture = load(IMAGE_PATH)
	_panel.stretch_mode = TextureRect.STRETCH_KEEP
	center.add_child(_panel)
	# 「继续」用锚点钉在图内坐标上,不用量尺寸(GROW_DIRECTION_BOTH 让它以锚点为中心向两边长)
	_continue_btn = Button.new()
	_continue_btn.text = "继续"
	_continue_btn.focus_mode = Control.FOCUS_NONE
	_continue_btn.add_theme_font_size_override("font_size", CONTINUE_FONT_SIZE)
	for name in ["font_color", "font_pressed_color", "font_focus_color"]:
		_continue_btn.add_theme_color_override(name, CONTINUE_COLOR)
	for name in ["font_hover_color", "font_hover_pressed_color"]:
		_continue_btn.add_theme_color_override(name, CONTINUE_HOVER_COLOR)
	var img_size: Vector2 = _panel.texture.get_size()
	var ax := CONTINUE_CENTER.x / img_size.x
	var ay := CONTINUE_CENTER.y / img_size.y
	_continue_btn.anchor_left = ax
	_continue_btn.anchor_right = ax
	_continue_btn.anchor_top = ay
	_continue_btn.anchor_bottom = ay
	_continue_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_continue_btn.grow_vertical = Control.GROW_DIRECTION_BOTH
	_continue_btn.set_meta(SoundFx.META, &"confirm")
	_continue_btn.pressed.connect(func() -> void: continue_pressed.emit())
	_panel.add_child(_continue_btn)


## 弹出。先放掉键盘焦点:GraphEdit 保有焦点时 Delete/Backspace 会删掉弹窗后面的节点(遮罩只挡鼠标)
func open() -> void:
	if is_inside_tree():
		get_viewport().gui_release_focus()
	visible = true


func close() -> void:
	visible = false
