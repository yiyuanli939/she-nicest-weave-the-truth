class_name MainMenu
extends Control
## 标题页(美术参考图 information/art_spec_20260829/image.png):
## 整张背景图 + 标题图(表面流光 shader)+ 右侧四个纯文字选项(悬停变浅走 theme)。
## 「开始游戏 / 继续游戏」都进选关页,不直接进关;「重置进度」点击即清档。
## 第五个选项「设置」(用户要求,美术文档只有四项)在「退出游戏」下面同列同间距,点开 SettingsPanel 弹窗
## (音乐音量 / 全屏 / 小机联动 / 小机维护),标题页本身不放任何控件。
## 坐标为 3840×2160 逻辑像素;美术调位置改下面常量。F9 仍直接打开小机维护面板(所有构建;Web 版设置里没有小机两行,
## 面板照旧打得开但切不了)。

const BG_PATH := "res://assets/art/title/bg.png"
const TITLE_PATH := "res://assets/art/title/title.png"
const SHEEN_PATH := "res://assets/shaders/title_sheen.gdshader"
const TITLE_POS := Vector2(630, 1551)     # 标题图左上角(预览图 bg 三锚点匹配实测;原 (619,1560) 偏左下约 10 px)
const MENU_CENTER_X := 3580.0             # 四个选项的水平中心(预览墨迹实测 3576–3582)
const MENU_Y0 := 940.0                    # 第一个选项的垂直中心(预览实测)
const MENU_PITCH := 197.0                 # 选项间距(预览四行中心 940/1138/1334/1530)
const MENU_FONT_SIZE := 78                # 预览墨高 65–67 = 站酷小薇 78 号(原 64 + 字距 12 只凑到了宽度,字形小 20%)
const MENU_GLYPH_SPACING := 0             # 预览「开始游戏」墨宽 306 = 78 号字距 0 时的 306;留常量给美术调

var _cal_ui: RobotMaintUI
var _settings: SettingsPanel
var _start_btn: Button
var _game: Node


func _ready() -> void:
	_game = get_node("/root/Game")
	var bgm := get_node_or_null("/root/Bgm")
	if bgm != null:
		bgm.play(&"title")
	var bg := TextureRect.new()
	bg.texture = load(BG_PATH)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := TextureRect.new()
	title.texture = load(TITLE_PATH)
	title.position = TITLE_POS
	title.size = title.texture.get_size()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(SHEEN_PATH)
	title.material = mat
	add_child(title)

	_cal_ui = RobotMaintUI.new()
	add_child(_cal_ui)
	_settings = SettingsPanel.new()
	add_child(_settings)
	_settings.setup(_game, get_node_or_null("/root/Robot"), bgm, _cal_ui)
	_cal_ui.visibility_changed.connect(_settings.refresh)   # 面板里切了无机器人模式,关面板时同步「小机联动」文字

	var progressed: bool = not _game.save.solved.is_empty()
	_start_btn = _add_option(0, "继续游戏" if progressed else "开始游戏", _game.goto_select)
	_add_option(1, "重置进度", _on_reset)
	_add_option(2, "开发者信息", _game.goto_credits)
	_add_option(3, "退出游戏", func() -> void:
		var robot := get_node_or_null("/root/Robot")
		if robot != null and bool(robot.enabled):
			robot.cue("sleep")   # 小机道晚安
			await get_tree().create_timer(0.2).timeout
		get_tree().quit())
	_add_option(4, "设置", _settings.open)

	if not _game.menu_greeted:
		_game.menu_greeted = true
		# 稍等 WebSocket 连上桥接再问候(连不上则静默;无机器人模式不挂)
		var robot := get_node_or_null("/root/Robot")
		if robot != null and bool(robot.enabled):
			get_tree().create_timer(1.2).timeout.connect(func() -> void:
				_game.robot_cue("greet"))


## 纯文字选项:无底、悬停变浅(theme),以 (MENU_CENTER_X, MENU_Y0 + i*PITCH) 为中心摆放
func _add_option(i: int, label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", MENU_FONT_SIZE)
	var fv := FontVariation.new()
	fv.base_font = get_theme_default_font()
	fv.spacing_glyph = MENU_GLYPH_SPACING
	b.add_theme_font_override("font", fv)
	b.pressed.connect(cb)
	add_child(b)
	b.reset_size()
	b.position = Vector2(MENU_CENTER_X, MENU_Y0 + i * MENU_PITCH) - b.size * 0.5
	return b


## 美术:「重置进度:点击后重置玩家进度」—— 点击即清档,第一项随之变回「开始游戏」
func _on_reset() -> void:
	_game.save.wipe()
	_game.current = null
	_start_btn.text = "开始游戏"
	_start_btn.reset_size()
	_start_btn.position = Vector2(MENU_CENTER_X, MENU_Y0) - _start_btn.size * 0.5


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F9:
		_cal_ui.open(get_node("/root/Robot"))
		get_viewport().set_input_as_handled()
