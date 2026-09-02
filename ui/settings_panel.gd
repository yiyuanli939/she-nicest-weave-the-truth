class_name SettingsPanel
extends CanvasLayer
## 标题页「设置」弹窗(2026-09-02 用户要求:设置是标题页第五个选项,点进去在弹窗里改,标题页本身不放控件;
## 美术文档没有 → 先纯文字 + 常量留位)。半透明遮罩 + 居中乳黄面板(主题 PanelContainer 样式):
## 「设置」→ 音乐音量(滑条)→ 全屏 开/关 → 小机联动 开/关 → 小机维护(联动开着才显示)→ 关闭(Esc 也关)。
## 设置落 SaveManager.settings(「重置进度」不清):music_volume(0..1)、fullscreen(bool);robot_enabled 由 Robot.set_enabled 写。
## 音量当场生效(Bgm.set_user_volume,启动时 Bgm._ready 自己读);全屏当场切窗口模式,下次启动 Game._apply_window_settings 恢复;
## 小机联动 = 无机器人模式开关(与维护面板「机器人:已启用 / 无机器人模式」同一个开关),Web 版没有机器人,这两行不显示。
## 文字按钮沿用主题(无底、悬停变浅);滑条按美术色板自画(乳黄轨 / 黄铜已填段 / 棕红圆钮),文字须全在站酷小薇体里。

const LAYER := 50              # 小机维护面板是 60:从这里打开时压在上面
const PANEL_MIN_W := 1200.0
const PAD := 40                # 面板内容边距(主题 panel_cream 自带 28/24 之外再加)
const TITLE_FONT_SIZE := 64
const FONT_SIZE := 48
const ROW_GAP := 20            # 行与行之间的空隙(主题 Button 自带上下 12 内边距)
const TITLE_GAP := 16          # 「设置」与第一行之间额外的空隙
const SLIDER_W := 560.0
const SLIDER_GAP := 24.0       # 「音乐音量」/ 滑条 / 百分数 之间
const TRACK_H := 14.0          # 滑轨厚度
const KNOB_D := 44             # 圆钮直径
const TRACK_BG := Color("E6D9BC")
const TRACK_FILL := Color("C9A24E")
const KNOB_COLOR := Color(0.42, 0.23, 0.2)
const DIM_COLOR := Color(0, 0, 0, 0.45)
const VOLUME_STEP := 0.05
const VOLUME_DEFAULT := 1.0

var _game: Node
var _robot: Node
var _bgm: Node
var _maint: RobotMaintUI
var _panel: PanelContainer
var _volume: HSlider
var _volume_lbl: Label
var _fullscreen_btn: Button
var _robot_btn: Button
var _maint_btn: Button
var _close_btn: Button
var _dragging := false


func _init() -> void:
	layer = LAYER
	visible = false
	var dim := ColorRect.new()   # 默认 mouse_filter = STOP:挡住后面的标题页
	dim.color = DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()   # 用 CenterContainer 包 panel 才是真居中(见 RobotMaintUI)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_MIN_W, 0)
	center.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, PAD)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ROW_GAP)
	margin.add_child(box)

	var head := MarginContainer.new()   # 「设置」下面比普通行多留 TITLE_GAP
	head.add_theme_constant_override("margin_bottom", TITLE_GAP)
	head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head.add_child(_label("设置", TITLE_FONT_SIZE))
	box.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(SLIDER_GAP))
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(_label("音乐音量", FONT_SIZE))
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = VOLUME_STEP
	_volume.value = VOLUME_DEFAULT
	_volume.custom_minimum_size = Vector2(SLIDER_W, KNOB_D)
	_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume.focus_mode = Control.FOCUS_NONE
	_volume.add_theme_stylebox_override("slider", _track(TRACK_BG))
	_volume.add_theme_stylebox_override("grabber_area", _track(TRACK_FILL))
	_volume.add_theme_stylebox_override("grabber_area_highlight", _track(TRACK_FILL))
	var knob := _knob()
	for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
		_volume.add_theme_icon_override(icon, knob)
	_volume.value_changed.connect(_on_volume_changed)
	_volume.drag_started.connect(func() -> void: _dragging = true)
	_volume.drag_ended.connect(_on_drag_ended)
	row.add_child(_volume)
	_volume_lbl = _label(volume_text(1.0), FONT_SIZE)
	_volume_lbl.custom_minimum_size.x = _volume_lbl.get_combined_minimum_size().x   # 按「100%」预留宽度,拖动时整行不挪
	_volume_lbl.text = volume_text(VOLUME_DEFAULT)
	row.add_child(_volume_lbl)
	box.add_child(row)

	_fullscreen_btn = _button(_on_toggle_fullscreen)
	box.add_child(_fullscreen_btn)
	_robot_btn = _button(_on_toggle_robot)
	box.add_child(_robot_btn)
	_maint_btn = _button(_on_open_maint)
	_maint_btn.text = "小机维护"
	box.add_child(_maint_btn)
	_close_btn = _button(close)
	_close_btn.text = "关闭"
	box.add_child(_close_btn)


## 挂到标题页后调:传入 Game / Robot / Bgm autoload(可为 null:对应行隐藏或不生效)和维护面板
func setup(game: Node, robot: Node, bgm: Node, maint: RobotMaintUI) -> void:
	_game = game
	_robot = robot
	_bgm = bgm
	_maint = maint
	var v := VOLUME_DEFAULT
	if _game != null and _game.save != null:
		v = clamp_volume(float(_game.save.settings.get("music_volume", VOLUME_DEFAULT)))
	_volume.set_value_no_signal(v)
	_volume_lbl.text = volume_text(v)
	refresh()


func open() -> void:
	refresh()
	visible = true


func close() -> void:
	visible = false


## Esc 关闭(维护面板压在上面时不管,交给面板)
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not (_maint != null and _maint.visible):
		close()
		get_viewport().set_input_as_handled()


## 按当前真实状态刷新文字/显隐(维护面板里切了无机器人模式、OS 快捷键切了全屏,都以此为准)
func refresh() -> void:
	_fullscreen_btn.text = "全屏:" + ("开" if is_fullscreen_mode(DisplayServer.window_get_mode()) else "关")
	var possible: bool = _robot != null and bool(_robot.robot_possible())
	_robot_btn.visible = possible
	_maint_btn.visible = possible and bool(_robot.enabled)
	if possible:
		_robot_btn.text = "小机联动:" + ("开" if bool(_robot.enabled) else "关")


# ---- 纯函数(测试盯) ----

static func clamp_volume(v: float) -> float:
	return clampf(v, 0.0, 1.0)


static func volume_text(v: float) -> String:
	return "%d%%" % roundi(clamp_volume(v) * 100.0)


static func is_fullscreen_mode(mode: int) -> bool:
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## 全屏开 = 全屏;关 = 回工程默认的最大化窗口(project.godot window/size/mode=2)
static func window_mode_for(fullscreen: bool) -> DisplayServer.WindowMode:
	return DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_MAXIMIZED


# ---- 音量 ----

func _on_volume_changed(v: float) -> void:
	_volume_lbl.text = volume_text(v)
	if _bgm != null:
		_bgm.set_user_volume(v)
	if not _dragging:   # 点轨道 / 滚轮:当场落盘;拖动中等松手
		_persist_volume()


func _on_drag_ended(changed: bool) -> void:
	_dragging = false
	if changed:
		_persist_volume()


func _persist_volume() -> void:
	if _game != null and _game.save != null:
		_game.save.settings["music_volume"] = snappedf(_volume.value, VOLUME_STEP)
		_game.save.save()


# ---- 全屏 ----

func _on_toggle_fullscreen() -> void:
	var on := not is_fullscreen_mode(DisplayServer.window_get_mode())
	DisplayServer.window_set_mode(window_mode_for(on))
	if _game != null and _game.save != null:
		_game.save.settings["fullscreen"] = on
		_game.save.save()
	refresh()


# ---- 小机 ----

func _on_toggle_robot() -> void:
	if _robot != null:
		_robot.set_enabled(not bool(_robot.enabled))   # 存 settings.robot_enabled
	refresh()


func _on_open_maint() -> void:
	if _maint != null and _robot != null:
		_maint.open(_robot)


# ---- 控件 ----

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(cb: Callable) -> Button:
	var b := Button.new()
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	return b


static func _track(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(TRACK_H / 2.0))
	sb.content_margin_top = TRACK_H / 2.0
	sb.content_margin_bottom = TRACK_H / 2.0
	return sb


## 圆钮:径向渐变纹理画实心圆,边缘最后 12% 渐隐当抗锯齿
static func _knob() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.88, 1.0])
	g.colors = PackedColorArray([KNOB_COLOR, KNOB_COLOR, Color(KNOB_COLOR, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = KNOB_D
	t.height = KNOB_D
	return t
