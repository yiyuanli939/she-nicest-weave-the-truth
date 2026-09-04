class_name RobotMaintUI
extends CanvasLayer
## 小机维护面板(开发者信息页「小机维护」按钮 / 标题页 F9,所有构建可用):
## 「机器人:已启用 / 无机器人模式」开关(Robot.set_enabled,存 settings;无机器人模式下接入/刷入/生成语音/摄像头按钮置灰)·
## 状态(桥接 / 串口 / 语音助手)· 接入小机(拉起桥接 + 语音助手)· 刷入固件与语音(mpremote,日志实时显示)·
## 「请指导我」回头方向 · 「小机动作:照常/保持不动」(不动模式:云台/动画/校准一律不发,表情语音照常)·
## 小机声音(中文音色 / 英文音色 / 音量 / 五句台词各中英一行,保存并生成语音,可本机试听)·
## 「看电脑方向」校准(自动挥手锁定 / 手动微调 / 保存)。
## 全部走 Robot autoload(game/robot_link.gd);脚本在 hardware/*.sh;台词配置 hardware/firmware/sounds/lines.json
## (voice / lines = 中文,voice_en / lines_en = 英文 → <cue>_en.wav,英文模式下 Robot 改发 <cue>_en)。
## 语言:按钮 / 标签文字是翻译键(auto_translate);拼出来的状态行、日志、校准提示用 tr() 逐段翻后关掉 auto_translate 直接显示;
## 音色下拉与台词行的标签是拼的,open() 时按当前语言重填。

const REFRESH_SEC := 0.5
const LOG_LINES := 6
const FONT_SIZE := 40
const TITLE_FONT_SIZE := 56
const PANEL_W := 3000
## 微软中文神经语音(edge-tts);第一项是小智同款
const VOICES: Array = [
	["zh-CN-XiaoyiNeural", "小艺(小智同款)"], ["zh-CN-XiaoxiaoNeural", "晓晓"], ["zh-CN-XiaoshuangNeural", "晓双(童声)"],
	["zh-CN-YunxiNeural", "云希(男)"], ["zh-CN-YunyangNeural", "云扬(男)"],
]
## 微软英文(英式,合维多利亚伦敦的设定)神经语音;第一项默认
const VOICES_EN: Array = [
	["en-GB-SoniaNeural", "索尼娅(英)"], ["en-GB-MaisieNeural", "梅茜(英,童声)"], ["en-GB-LibbyNeural", "莉比(英)"], ["en-GB-RyanNeural", "瑞安(英,男)"],
]
## 五句台词的触发点说明(顺序即面板顺序);故障(第三章)没有台词,只放 make_sfx.py 合成的坏掉音效
const LINE_HINTS: Dictionary = {
	"greet": "进关问候", "win": "通关庆祝", "encourage": "接错线鼓励", "hint": "发呆提示", "calm": "修好(第四章)",
}

var _robot: Node
var _mode_btn: Button
var _status: Label
var _log: RichTextLabel
var _connect_btn: Button
var _flash_btn: Button
var _cam_btn: Button
var _dir_btn: Button
var _still_btn: Button
var _cal_status: Label
var _voice_opt: OptionButton
var _voice_en_opt: OptionButton
var _gain: HSlider
var _gain_lbl: Label
var _line_edits: Dictionary = {}      # cue -> LineEdit(中文)
var _line_edits_en: Dictionary = {}   # cue -> LineEdit(英文)
var _hint_labels: Dictionary = {}     # cue -> Label("cue(说明)",按语言重填)
var _voices_btn: Button
var _player: AudioStreamPlayer
var _cfg: Dictionary = {}
var _timer := 0.0
var _busy_log := ""                # 正在跟踪的脚本日志路径("" = 空闲)


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
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	center.add_child(panel)
	_player = AudioStreamPlayer.new()
	add_child(_player)

	box.add_child(_label("小机维护", TITLE_FONT_SIZE))
	_mode_btn = _button("", _on_toggle_enabled)
	box.add_child(_mode_btn)
	_status = _label("", FONT_SIZE)
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # 各段已 tr() 过再拼
	box.add_child(_status)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 40)
	_connect_btn = _button("接入小机(拉起桥接与语音助手)", _on_connect)
	row1.add_child(_connect_btn)
	_flash_btn = _button("刷入固件与语音", _on_flash)
	row1.add_child(_flash_btn)
	_dir_btn = _button("", _on_toggle_dir)
	row1.add_child(_dir_btn)
	row1.add_child(_button("试转一下", _on_try_turn))
	_still_btn = _button("", _on_toggle_still)
	row1.add_child(_still_btn)
	_cam_btn = _button("摄像头验证云台", _on_cam_check)
	row1.add_child(_cam_btn)
	box.add_child(row1)

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 230)
	_log.scroll_following = true
	_log.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # 脚本日志原文 / 已 tr() 的消息
	_log.add_theme_font_size_override("normal_font_size", 34)
	box.add_child(_log)

	# ---- 小机声音 ----
	box.add_child(_label("小机声音:改音色 / 音量 / 台词(中文一行、英文一行),先「保存并生成语音」(需联网),再「刷入固件与语音」送进小机", FONT_SIZE))
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 30)
	vrow.add_child(_label("音色", FONT_SIZE, false))
	_voice_opt = _voice_option()
	vrow.add_child(_voice_opt)
	vrow.add_child(_label("英文音色", FONT_SIZE, false))
	_voice_en_opt = _voice_option()
	vrow.add_child(_voice_en_opt)
	vrow.add_child(_label("音量", FONT_SIZE, false))
	_gain = HSlider.new()
	_gain.min_value = 0.2
	_gain.max_value = 1.0
	_gain.step = 0.05
	_gain.custom_minimum_size = Vector2(500, 0)
	_gain.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gain.value_changed.connect(func(v: float) -> void: _gain_lbl.text = "%d%%" % roundi(v * 100))
	vrow.add_child(_gain)
	_gain_lbl = _label("90%", FONT_SIZE, false)
	_gain_lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	vrow.add_child(_gain_lbl)
	box.add_child(vrow)
	for cue: String in LINE_HINTS:
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 24)
		var name_lbl := _label("", FONT_SIZE, false)
		name_lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		name_lbl.custom_minimum_size = Vector2(520, 0)
		lrow.add_child(name_lbl)
		_hint_labels[cue] = name_lbl
		_line_edits[cue] = _line_edit(lrow)
		var preview_btn := _button("试听", _on_preview.bind(cue))
		preview_btn.set_meta(SoundFx.META, &"")   # 别在试听的语音上叠一声点击
		lrow.add_child(preview_btn)
		lrow.add_child(_label("英文", FONT_SIZE, false))
		_line_edits_en[cue] = _line_edit(lrow)
		var preview_en := _button("试听", _on_preview.bind(cue + "_en"))
		preview_en.set_meta(SoundFx.META, &"")
		lrow.add_child(preview_en)
		box.add_child(lrow)
	_voices_btn = _button("保存并生成语音", _on_make_voices)
	box.add_child(_voices_btn)

	# ---- 校准 ----
	box.add_child(_label("校准「看电脑方向」:自动 = 小机左右张望,正对屏幕时朝它挥手(或按它的 BOOT 键);手动 = 微调后保存。", FONT_SIZE))
	_cal_status = _label("", FONT_SIZE)
	_cal_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(_cal_status)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 30)
	row3.add_child(_button("开始自动校准(挥手锁定)", _on_auto))
	for spec in [["左", -6, 0], ["右", 6, 0], ["上", 0, -6], ["下", 0, 6]]:
		row3.add_child(_button(spec[0], func() -> void: _robot.nudge(spec[1], spec[2])))
	row3.add_child(_button("保存为屏幕方向", func() -> void:
		_robot.save_look_here()
		_cal_status.text = tr("已请求保存…")))
	var close_btn := _button("关闭", func() -> void: visible = false)
	close_btn.set_meta(SoundFx.META, &"close")
	row3.add_child(close_btn)
	box.add_child(row3)
	# 只在面板打开时刷新状态(低功耗模式下关着的面板不该占每帧)
	set_process(false)
	visibility_changed.connect(func() -> void: set_process(visible))


## wrap = false 的是 HBox 里的短标签:自动换行的 Label 在 HBox 里最小宽度是 0,会被挤成一列竖字把整行撑高(面板曾因此超出屏幕)
func _label(text: String, size: int, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.pressed.connect(cb)
	return b


func _line_edit(row: HBoxContainer) -> LineEdit:
	var edit := LineEdit.new()
	edit.add_theme_font_size_override("font_size", FONT_SIZE)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func _voice_option() -> OptionButton:
	var opt := OptionButton.new()
	opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # 项文字是「名字  id」拼的,_fill_voices 按语言填
	opt.add_theme_font_size_override("font_size", FONT_SIZE)
	return opt


## 音色下拉与台词行标签按当前语言重填(open() 时;切语言在标题页设置弹窗,面板总是之后才打开)
func _refresh_texts() -> void:
	_fill_voices(_voice_opt, VOICES)
	_fill_voices(_voice_en_opt, VOICES_EN)
	for cue: String in _hint_labels:
		(_hint_labels[cue] as Label).text = "%s(%s)" % [cue, tr(LINE_HINTS[cue])]


func _fill_voices(opt: OptionButton, voices: Array) -> void:
	var sel := maxi(opt.selected, 0)
	opt.clear()
	for v in voices:
		opt.add_item("%s  %s" % [tr(v[1]), v[0]])
	opt.selected = mini(sel, voices.size() - 1)


func open(robot: Node) -> void:
	_robot = robot
	if not robot.robot_event.is_connected(_on_event):
		robot.robot_event.connect(_on_event)
	_cal_status.text = ""
	_refresh_texts()
	_load_voice_config()
	_refresh()
	visible = true
	SoundFx.hit(self, &"open")


func _process(delta: float) -> void:
	if not visible or _robot == null:
		return
	_timer += delta
	if _timer < REFRESH_SEC:
		return
	_timer = 0.0
	_refresh()
	if _busy_log != "":
		_poll_log()


func _refresh() -> void:
	_mode_btn.text = "机器人:已启用(点击切换)" if _robot.enabled else "机器人:无机器人模式(点击切换)"
	var lines: Array[String] = []
	if not _robot.enabled:
		lines.append(tr("无机器人模式:不连桥接也不发命令,关内不显示求助提示,开发者信息页不显示「小机维护」"))
	else:
		lines.append(tr("桥接:已连") if _robot.connected else tr("桥接:未连(点「接入小机」,或手动 bash hardware/run_robot.sh)"))
		lines.append(tr("串口 / 小机:在线") if _robot.serial_open else tr("串口 / 小机:离线(没插 USB,或桥接还没找到 /dev/cu.usbmodem*)"))
		if _robot.speech_online:
			lines.append(tr("语音助手:在线(%s),说「请指导我」或「请帮帮我」/ please guide me") % ", ".join(PackedStringArray(_robot.speech_langs)))
		else:
			lines.append(tr("语音助手:离线(需要 hardware/speech/model,第一次要允许麦克风)"))
		if _robot.serial_open:
			lines.append(tr("固件外设:屏幕 %s / 功放 %s") % [tr("正常") if _robot.oled_ok else tr("故障(会自动重试)"), tr("正常") if _robot.audio_ok else tr("故障(静音)")])
	_status.text = "\n".join(lines)
	_dir_btn.text = "回头方向:右(点击切换)" if _robot.turn_dir == "right" else "回头方向:左(点击切换)"
	_still_btn.text = "小机动作:保持不动(点击切换)" if _robot.stationary else "小机动作:照常(点击切换)"
	_set_busy(_busy_log != "")


# ---- 接入 / 刷入 ----

func _on_connect() -> void:
	var pid: int = _robot.launch("run")
	_log.text = tr("已拉起 hardware/run_robot.sh(pid %d),几秒后看上面状态。") % pid if pid > 0 else tr("找不到 hardware/ 目录或脚本,请手动:bash hardware/run_robot.sh")


func _on_flash() -> void:
	_run_script("flash", _robot.flash_log_path(), tr("刷写中(会先停桥接,完成后自动重新接入)…"))


## 用电脑摄像头抓帧比对,判定两根轴是否真的转了(hardware/cam_check.py;截图在 hardware/.run/cam/)
func _on_cam_check() -> void:
	_run_script("cam", ProjectSettings.globalize_path("user://robot_cam.log"), tr("摄像头验证中:先确认小机在画面里(第一次要允许摄像头),然后转 pan / tilt 各两次…"))


## 跑一个会写进度日志的脚本,面板跟踪日志直到 DONE / FAIL
func _run_script(which: String, log_path: String, start_msg: String) -> void:
	var f := FileAccess.open(log_path, FileAccess.WRITE)
	if f != null:
		f.store_string("")
		f.close()
	var pid: int = _robot.launch(which, [log_path])
	if pid <= 0:
		_log.text = tr("找不到 hardware/ 目录或脚本,请手动跑 hardware/%s") % _robot.SCRIPTS.get(which, "")
		return
	_busy_log = log_path
	_set_busy(true)
	_log.text = start_msg


## 跑脚本期间、以及无机器人模式下,拉进程的四个按钮置灰
func _set_busy(busy: bool) -> void:
	var off: bool = busy or not bool(_robot.enabled)
	_flash_btn.disabled = off
	_connect_btn.disabled = off
	_voices_btn.disabled = off
	_cam_btn.disabled = off


func _poll_log() -> void:
	var text := FileAccess.get_file_as_string(_busy_log)
	if text == "":
		return
	var lines := text.strip_edges().split("\n")
	var tail := lines.slice(maxi(0, lines.size() - LOG_LINES))
	_log.text = "\n".join(tail)
	var last := lines[-1].strip_edges()
	if last == "DONE" or last.begins_with("FAIL"):
		if last == "DONE" and _busy_log == _robot.voices_log_path():
			_log.text += "\n" + tr("语音生成完毕:点「刷入固件与语音」送进小机。")
		elif _busy_log.ends_with("robot_cam.log"):
			_log.text += "\n" + tr("截图在 hardware/.run/cam/cam_report.png")
		_busy_log = ""
		_set_busy(false)


# ---- 无机器人模式 ----

## 存 settings(「重置进度」不清);关内提示 / 开发者信息页入口在下次进入场景时生效
func _on_toggle_enabled() -> void:
	_robot.set_enabled(not _robot.enabled)
	_refresh()


# ---- 回头方向 ----

func _on_toggle_dir() -> void:
	_robot.set_turn_dir("left" if _robot.turn_dir == "right" else "right")
	_refresh()


## 「小机不动」模式:云台/动画/自动校准一律不发,表情语音照常(舵机坏了/展示怕动静时用)
func _on_toggle_still() -> void:
	_robot.set_stationary(not _robot.stationary)
	_refresh()


func _on_try_turn() -> void:
	_robot.try_turn()   # 等待在 Robot autoload 上,面板随场景释放也会回中


# ---- 小机声音 ----

func _load_voice_config() -> void:
	_cfg = {}
	var path: String = _robot.voice_config_path()
	if path != "" and FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_cfg = parsed
	_select_voice(_voice_opt, VOICES, String(_cfg.get("voice", VOICES[0][0])))
	_select_voice(_voice_en_opt, VOICES_EN, String(_cfg.get("voice_en", VOICES_EN[0][0])))
	_gain.value = float(_cfg.get("gain", 0.9))
	var lines: Dictionary = _cfg.get("lines", {})
	var lines_en: Dictionary = _cfg.get("lines_en", {})
	for cue: String in _line_edits:
		(_line_edits[cue] as LineEdit).text = String(lines.get(cue, ""))
		(_line_edits_en[cue] as LineEdit).text = String(lines_en.get(cue, ""))


static func _select_voice(opt: OptionButton, voices: Array, voice: String) -> void:
	opt.selected = 0
	for i in voices.size():
		if voices[i][0] == voice:
			opt.selected = i


func _collect_voice_config() -> Dictionary:
	var lines := {}
	var lines_en := {}
	for cue: String in _line_edits:
		lines[cue] = (_line_edits[cue] as LineEdit).text.strip_edges()
		lines_en[cue] = (_line_edits_en[cue] as LineEdit).text.strip_edges()
	return {voice = VOICES[_voice_opt.selected][0], voice_en = VOICES_EN[_voice_en_opt.selected][0],
			gain = snappedf(_gain.value, 0.05), lines = lines, lines_en = lines_en}


## 写回 lines.json 并跑 make_voices.sh(edge-tts,需联网;中英各五句)
func _on_make_voices() -> void:
	var path: String = _robot.voice_config_path()
	if path == "":
		_log.text = tr("找不到 hardware/firmware/sounds/lines.json")
		return
	_cfg = _collect_voice_config()
	for table: String in ["lines", "lines_en"]:
		for cue: String in _cfg[table]:
			if String(_cfg[table][cue]) == "":
				_log.text = tr("台词「%s」为空") % (cue if table == "lines" else cue + "_en")
				return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_log.text = tr("写不了 %s") % path
		return
	f.store_string(JSON.stringify(_cfg, "\t", false))
	f.close()
	_run_script("voices", _robot.voices_log_path(), tr("已保存台词,正在用微软语音生成 wav(中英各五句,需联网,约半分钟)…"))


## 本机试听当前 wav(生成后才是新的;小机上的要刷入后才更新);name = cue 或 cue_en
func _on_preview(name: String) -> void:
	var path: String = _robot.sound_path(name)
	if path == "" or not FileAccess.file_exists(path):
		_log.text = tr("还没有 %s.wav,先「保存并生成语音」") % name
		return
	var stream := AudioStreamWAV.load_from_file(path)
	if stream == null:
		_log.text = tr("读不了 %s") % path
		return
	_player.stream = stream
	_player.play()
	var cue := name.trim_suffix("_en")
	var edit: LineEdit = _line_edits_en[cue] if name.ends_with("_en") else _line_edits[cue]
	_log.text = tr("试听 %s:%s") % [name, edit.text]


# ---- 校准 ----

func _on_auto() -> void:
	_robot.calibrate_look()
	_cal_status.text = tr("小机张望中…正对屏幕时朝它挥手!")


func _on_event(d: Dictionary) -> void:
	match d.get("evt", ""):
		"cal_done":
			_cal_status.text = tr("已锁定屏幕方向 pan=%s tilt=%s") % [d.get("pan"), d.get("tilt")]
		"cal_timeout":
			_cal_status.text = tr("超时了,再试一次?")
