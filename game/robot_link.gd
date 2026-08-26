extends Node
## Autoload "Robot":实体小机器人链路(WebSocket → 本地桥接 → 串口 ESP32-S3)。
## 没跑桥接/没插机器人时静默降级:连接失败每 3 秒重试,cue 全部无害丢弃。
## 高层 cue(供 Game/对话 robot_cue 使用):
##   greet celebrate confused think panic glitch calm sleep
## 直发协议见 docs/CONTENT_INTERFACE.md 与 hardware/firmware。

const URL := "ws://127.0.0.1:9800"
const RETRY_SEC := 3.0
const THROTTLE_MS: Dictionary = {"confused": 8000, "hint": 15000}   # cue -> 最小间隔(语音勿刷屏)

## 机器人上行事件(pong / button / cal_done / cal_timeout / err),已解析为 Dictionary
signal robot_event(data: Dictionary)
## 手势遥操手部数据({seen,x,y,pinch,fist,gesture}),20Hz
signal teleop_hand(data: Dictionary)
## 遥操进程开/关状态变化
signal teleop_state_changed(on: bool)

var _ws := WebSocketPeer.new()
var _state := WebSocketPeer.STATE_CLOSED
var _retry := 0.0
var _last_at: Dictionary = {}
var connected: bool = false

# 客户端记账的云台角(手动校准微调用;固件只认绝对角度)
var _pan := 90
var _tilt := 90

## 手势虚拟光标层(全场景生效)
var gesture: GestureInput
var _teleop_pid := -1


func _ready() -> void:
	gesture = GestureInput.new()
	add_child(gesture)
	teleop_hand.connect(gesture.on_hand)
	_connect()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		teleop_stop()


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
				if parsed.has("teleop"):
					teleop_hand.emit(parsed.teleop)
				else:
					robot_event.emit(parsed)
	elif s == WebSocketPeer.STATE_CLOSED:
		if connected:
			print("[Robot] 桥接断开,静默重试")
		connected = false
		_retry += delta
		if _retry >= RETRY_SEC:
			_retry = 0.0
			_connect()
	_state = s


## 高层动作:每个 cue = 表情 + 云台动作 + 语音(引导定位:成功庆祝/失败鼓励)。
## 未知 cue 原样当 emote 发,方便策划在 .tres 里扩展。
func cue(cue_name: String) -> void:
	if cue_name == "":
		return
	if THROTTLE_MS.has(cue_name):
		var now := Time.get_ticks_msec()
		if now - int(_last_at.get(cue_name, -100000)) < int(THROTTLE_MS[cue_name]):
			return
		_last_at[cue_name] = now
	match cue_name:
		"greet":       # 进关引导
			send({cmd = "emote", name = "happy"})
			send({cmd = "anim", name = "nod"})
			send({cmd = "say", name = "greet"})
		"celebrate":   # 通关庆祝
			send({cmd = "emote", name = "happy"})
			send({cmd = "anim", name = "celebrate"})
			send({cmd = "say", name = "win"})
		"confused":    # 接错线 → 鼓励而非嘲讽
			send({cmd = "emote", name = "confused"})
			send({cmd = "anim", name = "shake"})
			send({cmd = "say", name = "encourage"})
		"hint":        # 引导:装作看一眼电脑,转回来再开口提示
			send({cmd = "emote", name = "think"})
			send({cmd = "anim", name = "look_pc"})
			send({cmd = "say", name = "hint"})
		"think":
			send({cmd = "emote", name = "think"})
		"panic":       # 第五章失控演出
			send({cmd = "emote", name = "glitch"})
			send({cmd = "anim", name = "panic"})
			send({cmd = "say", name = "panic"})
		"glitch":
			send({cmd = "emote", name = "glitch"})
		"calm":        # 第五章通关归于平静
			send({cmd = "emote", name = "happy"})
			send({cmd = "anim", name = "nod"})
			send({cmd = "say", name = "calm"})
		"sleep":
			send({cmd = "emote", name = "sleep"})
		_:
			send({cmd = "emote", name = cue_name})


func send(d: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(d))


# ---- "看电脑"方向校准(见 docs/ROBOT_API.md) ----

## 自动:云台扫描,玩家在小机正对屏幕时挥手/按 BOOT 锁定;结果听 robot_event cal_done
func calibrate_look() -> void:
	send({cmd = "cal_look"})


## 手动微调一步后,把当前方向存为"屏幕方向"
func nudge(d_pan: int, d_tilt: int) -> void:
	_pan = clampi(_pan + d_pan, 50, 130)
	_tilt = clampi(_tilt + d_tilt, 70, 110)
	send({cmd = "gimbal", pan = _pan, tilt = _tilt})


func save_look_here() -> void:
	send({cmd = "cal_set"})


# ---- 手势遥操进程(可开关;见 docs/ROBOT_API.md) ----

func teleop_running() -> bool:
	return _teleop_pid > 0 and OS.is_process_running(_teleop_pid)


func teleop_start(extra_args: PackedStringArray = []) -> bool:
	if teleop_running():
		return true
	# mediapipe 在 mac 上要 py3.12 专用 venv(.venv-teleop);没有则退回通用 .venv
	var py := ProjectSettings.globalize_path("res://hardware/.venv-teleop/bin/python")
	if not FileAccess.file_exists(py):
		py = ProjectSettings.globalize_path("res://hardware/.venv/bin/python")
	var script := ProjectSettings.globalize_path("res://hardware/teleop/teleop.py")
	var args := PackedStringArray([script])
	args.append_array(extra_args)
	_teleop_pid = OS.create_process(py, args)
	var ok := teleop_running()
	teleop_state_changed.emit(ok)
	return ok


func teleop_stop() -> void:
	if _teleop_pid > 0 and OS.is_process_running(_teleop_pid):
		OS.kill(_teleop_pid)
	_teleop_pid = -1
	teleop_state_changed.emit(false)
