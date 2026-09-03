extends Node
## Autoload "Robot":实体小机器人链路(WebSocket → 本地桥接 → 串口 ESP32-S3)。
## 没跑桥接/没插机器人时静默降级:连接失败每 3 秒重试,cue 全部无害丢弃(sent_log 照记,测试与维护面板用)。
## 高层 cue(供 Game/对话 robot_cue 使用):greet celebrate confused hint think panic glitch calm sleep idle
## 剧情态:broken = true(3-1 通关瞬间坏掉,结局「感谢游玩」黑屏时修好)时任何 cue(sleep 除外)
## 都变成故障演出:故障脸 + 乱动 + 随机一段「坏掉」音效,没有台词。
## 不动模式:stationary = true(维护面板「小机动作」开关,存 settings)时云台直控/云台动画/自动校准一律不发,
## 表情、语音、口型、屏幕照常 —— 舵机坏了或展示怕动静时用。
## 语音:桥接转来的 {"evt":"speech"} 命中「请指导我 / 请帮帮我」或英文 "please guide me / please help me" → guide_requested(LevelScene 接);
## 语音助手(hardware/speech/listen.py)中英两个识别器同时听,speech_ready/alive 带 langs。
## 英文语音:英文模式下有台词的 say 命令改发 <cue>_en(hardware/firmware/sounds/<cue>_en.wav,lines.json 的 lines_en 生成),
## 没有该 wav 就退回中文;固件只按文件名找声音,协议不变(localize_commands,纯函数)。
## 回头:turn_to_limit() 把底部云台转到极限(turn_dir 左/右,存 SaveManager.settings),return_center() 转回。
## 外部进程:launch("run"/"stop"/"flash") 跑 hardware/*.sh(接入小机 / 刷固件)。协议见 docs/ROBOT_API.md。
## 无机器人模式:enabled = false(优先级:命令行 --no-robot > --robot > settings.robot_enabled > 平台默认,macOS 开、其它平台关;Web 一律关)
## 时不连桥接、不每帧轮询,send/launch 一律静默(sent_log 也不记);UI 侧据此隐藏一切指向实体小机的提示与入口
## (关内求助提示、开发者信息页「小机维护」)。切换在维护面板(标题页 F9),存 settings,「重置进度」不清。

## 机器人上行事件(pong / button / cal_done / cal_timeout / err / serial / speech*),已解析为 Dictionary
signal robot_event(data: Dictionary)
## 玩家对麦克风说了「请指导我」或「请帮帮我」
signal guide_requested

const URL := "ws://127.0.0.1:9800"
const RETRY_SEC := 3.0
const THROTTLE_MS: Dictionary = {"confused": 8000, "hint": 15000, "__broken": 6000}   # cue -> 最小间隔(语音勿刷屏)
const GUIDE_THROTTLE_MS := 3000
const SPEECH_TIMEOUT_SEC := 10.0      # 语音助手心跳超时
const PAN_LEFT := 5        # 固件 1.2:pan 实测左右各 90°,限位 5–175
const PAN_RIGHT := 175
const PAN_CENTER := 90
const TILT_CENTER := 90
const TURN_SEC := 0.6
const SENT_LOG_MAX := 60
const GUIDE_PHRASES: Dictionary = {
	"zh": ["请指导我", "指导我", "请帮帮我", "帮帮我"],
	"en": ["please guide me", "guide me", "please help me", "help me"],
}
const VOICE_CUES: Array[String] = ["greet", "win", "encourage", "hint", "calm"]   # 有台词的声音名(lines.json);英文版 <名>_en.wav
const SCRIPTS: Dictionary = {"run": "run_robot.sh", "stop": "stop_robot.sh", "flash": "flash_robot.sh", "voices": "make_voices.sh", "cam": "cam_check.sh"}
const GLITCH_SFX_COUNT := 3            # sounds/glitch1..3.wav(hardware/make_sfx.py 合成的纯音效)
## 不动模式下拦掉的命令:云台直控 / 云台动画 / 自动校准(要扫头);不发也不记 sent_log
const STILL_CMDS: Array = ["gimbal", "anim", "cal_look"]

var enabled: bool = true           # false = 无机器人模式(见文件头);_ready 按命令行/settings/平台解析
var connected: bool = false        # ws 连上桥接
var serial_open: bool = false      # 桥接报告串口(小机)在线
var speech_online: bool = false    # 语音助手心跳在线
var speech_langs: Array = []       # 语音助手在听的语言(speech_ready/alive 的 langs;老版助手不带 → ["zh"])
var broken: bool = false           # 剧情故障态(Game.start_level 按章节设)
var stationary: bool = false       # 「小机不动」:不发云台/动画/校准,其余照常(维护面板开关,存 settings)
var turn_dir: String = "right"     # 「请指导我」时回头方向
var oled_ok: bool = true           # 固件 ready 上报的外设状态
var audio_ok: bool = true
var last_gimbal_ack: Dictionary = {}   # 固件回的 {"evt":"gimbal","pan","tilt"}(+ at_ms)
var sent_log: Array[Dictionary] = []   # 最近发出的命令(无桥接也记)

var _ws := WebSocketPeer.new()
var _retry := 0.0
var _last_at: Dictionary = {}
var _last_guide_ms := -100000
var _speech_seen := -1.0e9
var _pan := PAN_CENTER            # 客户端记账的云台角(固件只认绝对角度)
var _tilt := TILT_CENTER
var _turn_tween: Tween
var _pids: Dictionary = {}


func _ready() -> void:
	var game := get_node_or_null("/root/Game")
	var settings: Dictionary = {}
	if game != null and game.save != null:
		settings = game.save.settings
		turn_dir = _norm_dir(String(settings.get("robot_turn", "right")))
		stationary = bool(settings.get("robot_stationary", false))
	# 引擎对 -- 之前的未知参数「可能丢弃或修改」,推荐 `游戏 -- --no-robot`;两处都认
	var args := OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	enabled = robot_possible() and resolve_enabled(args, settings, platform_default_enabled())
	set_process(enabled)
	if enabled:
		_connect()


## 平台默认:桥接/语音脚本只在 macOS 能跑,其它平台默认无机器人
static func platform_default_enabled() -> bool:
	return OS.has_feature("macos")


## Web 导出永远无机器人(F9 面板也切不开):浏览器连不上 ws://127.0.0.1(https 页面的混合内容被拦),重连循环只会刷控制台错误
static func robot_possible() -> bool:
	return not OS.has_feature("web")


## 是否启用实体小机(纯函数,测试盯着):--no-robot > --robot > settings.robot_enabled > 平台默认
static func resolve_enabled(args: PackedStringArray, settings: Dictionary, platform_default: bool) -> bool:
	if args.has("--no-robot"):
		return false
	if args.has("--robot"):
		return true
	if settings.has("robot_enabled"):
		return bool(settings["robot_enabled"])
	return platform_default


## 无机器人模式开关(维护面板);persist = false 只改运行态(命令行覆盖/测试),不落盘
func set_enabled(on: bool, persist: bool = true) -> void:
	on = on and robot_possible()
	if on != enabled:
		enabled = on
		if on:
			_retry = 0.0
			_connect()
		else:
			_ws = WebSocketPeer.new()   # 丢掉旧连接(析构即关 socket);不再轮询
			connected = false
			serial_open = false
			speech_online = false
	set_process(on)
	if persist:
		var game := get_node_or_null("/root/Game")
		if game != null and game.save != null:
			game.save.settings["robot_enabled"] = on
			game.save.save()


func _connect() -> void:
	_ws = WebSocketPeer.new()
	if _ws.connect_to_url(URL) != OK:
		connected = false


func _process(delta: float) -> void:
	_ws.poll()
	var s := _ws.get_ready_state()
	if s == WebSocketPeer.STATE_OPEN:
		if not connected:
			connected = true
			print("[Robot] 已连上桥接")
		while _ws.get_available_packet_count() > 0:
			var msg := _ws.get_packet().get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(msg)
			if parsed is Dictionary:
				_on_event(parsed)
	elif s == WebSocketPeer.STATE_CLOSED:
		if connected:
			print("[Robot] 桥接断开,静默重试")
		connected = false
		serial_open = false
		_retry += delta
		if _retry >= RETRY_SEC:
			_retry = 0.0
			_connect()
	if speech_online and Time.get_unix_time_from_system() - _speech_seen > SPEECH_TIMEOUT_SEC:
		speech_online = false


func _on_event(d: Dictionary) -> void:
	match String(d.get("evt", "")):
		"speech":
			if matches_guide(String(d.get("text", ""))):
				var now := Time.get_ticks_msec()
				if now - _last_guide_ms >= GUIDE_THROTTLE_MS:
					_last_guide_ms = now
					guide_requested.emit()
		"speech_ready", "speech_alive":
			speech_online = true
			speech_langs = d.get("langs", ["zh"])
			_speech_seen = Time.get_unix_time_from_system()
		"serial":
			serial_open = bool(d.get("open", false))
		"ready":
			oled_ok = bool(d.get("oled", true))
			audio_ok = bool(d.get("audio", true))
		"gimbal":
			last_gimbal_ack = {pan = int(d.get("pan", -1)), tilt = int(d.get("tilt", -1)), at_ms = Time.get_ticks_msec()}
	robot_event.emit(d)


## 识别文本是否「请指导我 / 请帮帮我」或 "please guide me / please help me"(Vosk 输出词间有空格,先去掉;英文不分大小写)。
## 两种语言都认、不看当前界面语言:识别器两边同时在听,玩家用哪种都行
static func matches_guide(text: String) -> bool:
	var compact := text.replace(" ", "").replace("　", "")
	for p in GUIDE_PHRASES["zh"]:
		if compact.contains(p):
			return true
	var lower := compact.to_lower()
	for p in GUIDE_PHRASES["en"]:
		if lower.contains(String(p).replace(" ", "")):
			return true
	return false


## 英文模式:有台词的 say 换成 <名>_en(has_wav(名_en) 为真才换,否则退回中文);其它命令与中文模式原样。纯函数,测试盯着
static func localize_commands(cmds: Array[Dictionary], lang: String, has_wav: Callable) -> Array[Dictionary]:
	if lang != "en":
		return cmds
	var out: Array[Dictionary] = []
	for c in cmds:
		var d: Dictionary = c.duplicate()
		var name := String(d.get("name", ""))
		if d.get("cmd") == "say" and VOICE_CUES.has(name) and bool(has_wav.call(name + "_en")):
			d["name"] = name + "_en"
		out.append(d)
	return out


static func has_sound(name: String) -> bool:
	var p := sound_path(name)
	return p != "" and FileAccess.file_exists(p)


# ---- cue ----

## 每个 cue = 表情 + 云台动作 + 语音(引导定位:成功庆祝/失败鼓励);纯函数,测试盯着。
## 故障态(broken)下除 sleep 外一律故障演出(variant 选哪段坏掉音效);未知 cue 原样当 emote 发,方便策划在 .tres 里扩展。
static func commands_for(cue_name: String, is_broken: bool, variant: int = 0) -> Array[Dictionary]:
	if is_broken and cue_name != "sleep":
		return _glitch_show(variant)
	match cue_name:
		"greet":       # 进关引导
			return [{cmd = "emote", name = "happy"}, {cmd = "anim", name = "nod"}, {cmd = "say", name = "greet"}]
		"celebrate":   # 通关庆祝
			return [{cmd = "emote", name = "happy"}, {cmd = "anim", name = "celebrate"}, {cmd = "say", name = "win"}]
		"confused":    # 接错线 → 鼓励而非嘲讽
			return [{cmd = "emote", name = "confused"}, {cmd = "anim", name = "shake"}, {cmd = "say", name = "encourage"}]
		"hint":        # 引导:装作看一眼电脑,转回来再开口提示
			return [{cmd = "emote", name = "think"}, {cmd = "anim", name = "look_pc"}, {cmd = "say", name = "hint"}]
		"panic":       # 故障演出(第三章开头坏掉那一刻):没有台词,只放动画 + 坏掉音效
			return _glitch_show(variant)
		"calm":        # 归于平静(第四章开头修好)
			return [{cmd = "emote", name = "happy"}, {cmd = "anim", name = "nod"}, {cmd = "say", name = "calm"}]
		"think", "glitch", "sleep", "idle":
			return [{cmd = "emote", name = cue_name}]
	return [{cmd = "emote", name = cue_name}]


## 故障脸 + 乱动 + 第 variant 段坏掉音效(glitch1..3 循环取);不说任何话
static func _glitch_show(variant: int) -> Array[Dictionary]:
	var n := posmod(variant, GLITCH_SFX_COUNT) + 1
	return [{cmd = "emote", name = "glitch"}, {cmd = "anim", name = "panic"}, {cmd = "say", name = "glitch%d" % n}]


func cue(cue_name: String) -> void:
	if cue_name == "":
		return
	var key := "__broken" if (broken and cue_name != "sleep") else cue_name
	if THROTTLE_MS.has(key):
		var now := Time.get_ticks_msec()
		if now - int(_last_at.get(key, -100000)) < int(THROTTLE_MS[key]):
			return
		_last_at[key] = now
	for c in localize_commands(commands_for(cue_name, broken, randi() % GLITCH_SFX_COUNT), Loc.current(), has_sound):
		send(c)


func send(d: Dictionary) -> void:
	if not enabled:
		return   # 无机器人模式:不发也不记
	if stationary and STILL_CMDS.has(d.get("cmd")):
		return
	sent_log.append(d)
	if sent_log.size() > SENT_LOG_MAX:
		sent_log.pop_front()
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(d))


## 测试用:sent_log 里是否有匹配 cmd(+name / pan)的命令
func sent(cmd: String, name: String = "", pan: int = -1) -> bool:
	for d: Dictionary in sent_log:
		if d.get("cmd") != cmd:
			continue
		if name != "" and d.get("name") != name:
			continue
		if pan >= 0 and int(d.get("pan", -1)) != pan:
			continue
		return true
	return false


# ---- 回头(「请指导我」)----

static func turn_target(dir: String) -> int:
	return PAN_LEFT if dir == "left" else PAN_RIGHT


static func _norm_dir(dir: String) -> String:
	return "left" if dir == "left" else "right"


func set_turn_dir(dir: String) -> void:
	turn_dir = _norm_dir(dir)
	var game := get_node_or_null("/root/Game")
	if game != null and game.save != null:
		game.save.settings["robot_turn"] = turn_dir
		game.save.save()


func set_stationary(on: bool) -> void:
	stationary = on
	var game := get_node_or_null("/root/Game")
	if game != null and game.save != null:
		game.save.settings["robot_stationary"] = on
		game.save.save()


## 底部云台转到极限(固件 gimbal 瞬时到位,插值在这里做;期间别发 anim,固件动画会抢云台)
func turn_to_limit(sec: float = TURN_SEC) -> void:
	_tween_pan(turn_target(turn_dir), sec)


func return_center(sec: float = TURN_SEC) -> void:
	_tween_pan(PAN_CENTER, sec)


## 维护面板「试转一下」:转到极限,停 1 s 再回中。await 放在 autoload 上 —— 放在面板里的话,这 1 s 内换场景面板被释放,
## 协程静默丢弃、回中永远不发,小机会停在极限位
func try_turn() -> void:
	turn_to_limit()
	await get_tree().create_timer(1.0).timeout
	return_center()


func _tween_pan(target: int, sec: float) -> void:
	if stationary:
		return   # 不动模式:客户端记账的角度也不改,关掉后从上次真实角度继续
	if _turn_tween != null:
		_turn_tween.kill()
		_turn_tween = null
	if sec <= 0.0 or not is_inside_tree():
		_set_pan(float(target))
		return
	_turn_tween = create_tween()
	_turn_tween.tween_method(_set_pan, float(_pan), float(target), sec)


func _set_pan(v: float) -> void:
	var a := clampi(roundi(v), PAN_LEFT, PAN_RIGHT)
	if a == _pan:
		return
	_pan = a
	send({cmd = "gimbal", pan = a})


# ---- "看电脑"方向校准(见 docs/ROBOT_API.md) ----

## 自动:云台扫描,玩家在小机正对屏幕时挥手/按 BOOT 锁定;结果听 robot_event cal_done
func calibrate_look() -> void:
	send({cmd = "cal_look"})


## 手动微调一步后,把当前方向存为"屏幕方向"
func nudge(d_pan: int, d_tilt: int) -> void:
	if stationary:
		return
	_pan = clampi(_pan + d_pan, PAN_LEFT, PAN_RIGHT)
	_tilt = clampi(_tilt + d_tilt, 70, 110)
	send({cmd = "gimbal", pan = _pan, tilt = _tilt})


func save_look_here() -> void:
	send({cmd = "cal_set"})


# ---- 外部进程:接入(桥接 + 语音助手)/ 刷固件(hardware/*.sh) ----

## hardware/ 目录:编辑器里用 res://,导出版从可执行文件往上找
static func hardware_dir() -> String:
	if OS.has_feature("editor"):
		var p := ProjectSettings.globalize_path("res://hardware")
		if DirAccess.dir_exists_absolute(p):
			return p
	var d := OS.get_executable_path().get_base_dir()
	for i in 6:
		if DirAccess.dir_exists_absolute(d.path_join("hardware")):
			return d.path_join("hardware")
		d = d.get_base_dir()
	return ""


## 跑 hardware/<脚本>(zsh),返回 pid(-1 = 失败);子进程不随游戏退出
func launch(which: String, args: Array = []) -> int:
	if not enabled or not OS.has_feature("macos"):
		return -1   # 无机器人模式不拉进程;hardware/*.sh 是 macOS 的 zsh 脚本:其他平台直接降级(维护面板会提示手动跑)
	var hw := hardware_dir()
	if hw == "" or not SCRIPTS.has(which):
		return -1
	var argv: Array = [hw.path_join(SCRIPTS[which])]
	argv.append_array(args)
	var pid := OS.create_process("/bin/zsh", PackedStringArray(argv))
	_pids[which] = pid
	return pid


func is_running(which: String) -> bool:
	var pid: int = _pids.get(which, -1)
	return pid > 0 and OS.is_process_running(pid)


static func flash_log_path() -> String:
	return ProjectSettings.globalize_path("user://robot_flash.log")


static func voices_log_path() -> String:
	return ProjectSettings.globalize_path("user://robot_voices.log")


## 小机台词/音色/音量配置(hardware/firmware/sounds/lines.json),维护面板读写,make_voices.sh 按它生成 wav
static func voice_config_path() -> String:
	var hw := hardware_dir()
	return hw.path_join("firmware/sounds/lines.json") if hw != "" else ""


static func sound_path(name: String) -> String:
	var hw := hardware_dir()
	return hw.path_join("firmware/sounds/%s.wav" % name) if hw != "" else ""
