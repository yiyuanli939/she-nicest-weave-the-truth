class_name SettingsPanel
extends VBoxContainer
## 标题页的设置模块(2026-09-02 用户要求;美术文档没有 → 先纯文字,字号/间距常量留给美术,位置在 ui/main_menu.gd SETTINGS_*):
## 放在四个选项正下方、同一列居中:「设置」→ 音乐音量(滑条)→ 全屏 开/关 → 小机联动 开/关 → 小机维护(联动开着才显示)。
## 设置落 SaveManager.settings(「重置进度」不清):music_volume(0..1)、fullscreen(bool);robot_enabled 由 Robot.set_enabled 写。
## 音量当场生效(Bgm.set_user_volume,启动时 Bgm._ready 自己读);全屏当场切窗口模式,下次启动 Game._apply_window_settings 恢复;
## 小机联动 = 无机器人模式开关(与维护面板「机器人:已启用 / 无机器人模式」同一个开关),Web 版没有机器人,这两行不显示。
## 文字按钮沿用主题(无底、悬停变浅);滑条按美术色板自画(乳黄轨 / 黄铜已填段 / 棕红圆钮),文字须全在站酷小薇体里。

const TITLE_FONT_SIZE := 52
const FONT_SIZE := 42
const ROW_GAP := 6             # 行与行之间的空隙(主题 Button 自带上下 12 内边距,行距主要靠它)
const TITLE_GAP := 12          # 「设置」与第一行之间额外的空隙
const SLIDER_W := 180.0
const SLIDER_GAP := 12.0       # 「音乐音量」/ 滑条 / 百分数 之间
const TRACK_H := 12.0          # 滑轨厚度
const KNOB_D := 36             # 圆钮直径
const TRACK_BG := Color("E6D9BC")
const TRACK_FILL := Color("C9A24E")
const KNOB_COLOR := Color(0.42, 0.23, 0.2)
const VOLUME_STEP := 0.05
const VOLUME_DEFAULT := 1.0

var _game: Node
var _robot: Node
var _bgm: Node
var _maint: RobotMaintUI
var _volume: HSlider
var _volume_lbl: Label
var _fullscreen_btn: Button
var _robot_btn: Button
var _maint_btn: Button
var _dragging := false


func _init() -> void:
	add_theme_constant_override("separation", ROW_GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := MarginContainer.new()   # 「设置」下面比普通行多留 TITLE_GAP
	head.add_theme_constant_override("margin_bottom", TITLE_GAP)
	head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_label("设置", TITLE_FONT_SIZE))
	add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(SLIDER_GAP))
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	add_child(row)

	_fullscreen_btn = _button(_on_toggle_fullscreen)
	add_child(_fullscreen_btn)
	_robot_btn = _button(_on_toggle_robot)
	add_child(_robot_btn)
	_maint_btn = _button(_on_open_maint)
	_maint_btn.text = "小机维护"
	add_child(_maint_btn)


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
	if not _dragging:   # 点轨道 / 键盘:当场落盘;拖动中等松手
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
