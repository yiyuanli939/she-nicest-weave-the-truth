extends Node
## Autoload "Robot":实体小机器人链路(WebSocket → 本地桥接 → 串口 ESP32-S3)。
## 没跑桥接/没插机器人时静默降级:连接失败每 3 秒重试,cue 全部无害丢弃(sent_log 照记,测试与维护面板用)。
## 高层 cue(供 Game/对话 robot_cue 使用):greet celebrate confused hint think panic glitch calm sleep idle
## 剧情态:broken = true(第三章)时任何 cue(sleep 除外)都变成故障演出:故障脸 + 乱动 + 随机一段「坏掉」音效,没有台词。
## 语音:桥接转来的 {"evt":"speech"} 命中「请指导我 / 请帮帮我」→ guide_requested(LevelScene 接)。
## 回头:turn_to_limit() 把底部云台转到极限(turn_dir 左/右,存 SaveManager.settings),return_center() 转回。
## 外部进程:launch("run"/"stop"/"flash") 跑 hardware/*.sh(接入小机 / 刷固件)。协议见 docs/ROBOT_API.md。

## 机器人上行事件(pong / button / cal_done / cal_timeout / err / serial / speech*),已解析为 Dictionary
signal robot_event(data: Dictionary)
## 玩家对麦克风说了「请指导我」或「请帮帮我」
signal guide_requested

const URL := "ws://127.0.0.1:9800"
const RETRY_SEC := 3.0
const THROTTLE_MS: Dictionary = {"confused": 8000, "hint": 15000, "__broken": 6000}   # cue -> 最小间隔(语音勿刷屏)
const GUIDE_THROTTLE_MS := 3000
const SPEECH_TIMEOUT_SEC := 10.0      # 语音助手心跳超时
const PAN_LEFT := 50
const PAN_RIGHT := 130
const PAN_CENTER := 90
const TILT_CENTER := 90
const TURN_SEC := 0.6
const SENT_LOG_MAX := 60
const GUIDE_PHRASES: Array[String] = ["请指导我", "指导我", "请帮帮我", "帮帮我"]
const SCRIPTS: Dictionary = {"run": "run_robot.sh", "stop": "stop_robot.sh", "flash": "flash_robot.sh", "voices": "make_voices.sh", "cam": "cam_check.sh"}
const GLITCH_SFX_COUNT := 3            # sounds/glitch1..3.wav(hardware/make_sfx.py 合成的纯音效)

var connected: bool = false        # ws 连上桥接
var serial_open: bool = false      # 桥接报告串口(小机)在线
var speech_online: bool = false    # 语音助手心跳在线
var broken: bool = false           # 剧情故障态(Game.start_level 按章节设)
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
	if game != null and game.save != null:
		turn_dir = _norm_dir(String(game.save.settings.get("robot_turn", "right")))
	_connect()


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
			_speech_seen = Time.get_unix_time_from_system()
		"serial":
			serial_open = bool(d.get("open", false))
		"ready":
			oled_ok = bool(d.get("oled", true))
			audio_ok = bool(d.get("audio", true))
		"gimbal":
			last_gimbal_ack = {pan = int(d.get("pan", -1)), tilt = int(d.get("tilt", -1)), at_ms = Time.get_ticks_msec()}
	robot_event.emit(d)


## 识别文本是否「请指导我 / 请帮帮我」(Vosk 输出词间有空格,先去掉)
static func matches_guide(text: String) -> bool:
	var compact := text.replace(" ", "").replace("　", "")
	for p in GUIDE_PHRASES:
		if compact.contains(p):
			return true
	return false


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
	for c in commands_for(cue_name, broken, randi() % GLITCH_SFX_COUNT):
		send(c)


func send(d: Dictionary) -> void:
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


## 底部云台转到极限(固件 gimbal 瞬时到位,插值在这里做;期间别发 anim,固件动画会抢云台)
func turn_to_limit(sec: float = TURN_SEC) -> void:
	_tween_pan(turn_target(turn_dir), sec)


func return_center(sec: float = TURN_SEC) -> void:
	_tween_pan(PAN_CENTER, sec)


func _tween_pan(target: int, sec: float) -> void:
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
