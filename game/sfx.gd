class_name SoundFx
extends Node
## autoload Sfx:玩家操作音效。做法同 Bgm —— 槽位表 CLIPS(槽位 → 文件,"" = 静音),换音效 = 换文件或改一行表;
## 素材来自 Kenney CC0 包(assets/sfx/LICENSE-kenney.txt),槽位说明与换法见 assets/sfx/音效位置.md。
##   * play(槽位):从 POOL_SIZE 个一次性播放器里取空闲的播(都忙就抢最早那个);同一帧同槽位只播一次
##     (多选删除 / 多条线同时断 / 多枚徽章同时出现不会机关枪);GAIN_DB 按片段响度修正 × BASE_VOLUME × 玩家音量。
##   * push_mute / pop_mute:代解、示答、载入旧棋盘、撤销重做重建期间静音(这些不是玩家亲手的操作)。
##   * 按钮不用逐个接:_ready 监听 node_added,凡 BaseButton 进树就连 pressed → 播 meta "sfx"(默认 click;
##     set_meta(&"sfx", &"") = 不出声),mouse_entered → hover。全项目按钮都是代码 new() 出来的,一个钩子全覆盖。
##   * 无 _process、无循环 Tween(低功耗模式白名单);headless 下 dummy 驱动,play() 无害,冒烟脚本另有静音总线。
## 播放器在 _init 建好,测试 new() 后可用;进树前 play() 只记 last_slot 不真播(root 未进树时 play 会报错)。

const CLIPS: Dictionary = {
	# 通用界面
	&"click": "res://assets/sfx/click.ogg",              # 任意按钮按下(默认)
	&"hover": "res://assets/sfx/hover.ogg",              # 按钮悬停(轻)
	&"back": "res://assets/sfx/back.ogg",                # 返回主界面 / 取消 / 撤销
	&"confirm": "res://assets/sfx/confirm.ogg",          # 「继续」/ 钉纹样确认成功
	&"open": "res://assets/sfx/open.ogg",                # 弹窗打开(设置 / 钉纹样 / 小机维护)
	&"close": "res://assets/sfx/close.ogg",              # 弹窗关闭
	&"toggle": "res://assets/sfx/toggle.ogg",            # 全屏 / 小机联动等开关
	&"slider": "res://assets/sfx/slider.ogg",            # 音量滑条松手 / 点轨道
	&"reset_progress": "res://assets/sfx/reset_progress.ogg",
	&"loom": "res://assets/sfx/loom.ogg",                # 织布机声:进入选关页、选定一关(用户 2026-09-02:原翻页音挪到这里)
	# 棋盘
	&"place": "res://assets/sfx/place.ogg",              # 仪器放上棋盘
	&"delete": "res://assets/sfx/delete.ogg",            # 删仪器
	&"refuse": "res://assets/sfx/refuse.ogg",            # 线轴 / 目标织机拒删
	&"pick": "res://assets/sfx/pick.ogg",                # 拿起插头(拉线开始)
	&"drop": "res://assets/sfx/drop.ogg",                # 插头空放(没接上)
	&"plug": "res://assets/sfx/plug.ogg",                # 接线成功
	&"unplug": "res://assets/sfx/unplug.ogg",            # 玩家右键拔线
	&"error": "res://assets/sfx/error.ogg",              # 冲突 / 成环 / 逃逸徽章出现
	&"warn": "res://assets/sfx/warn.ogg",                # 欠定徽章出现
	&"snap": "res://assets/sfx/snap.ogg",                # 接错的线 0.5 s 后自动断开
	&"move": "res://assets/sfx/move.ogg",                # 拖动仪器松手
	&"zoom": "res://assets/sfx/zoom.ogg",
	&"undo": "res://assets/sfx/back.ogg",
	&"redo": "res://assets/sfx/redo.ogg",
	&"reset_board": "res://assets/sfx/reset_board.ogg",
	# 钉纹样弹窗
	&"brush": "res://assets/sfx/brush.ogg",              # 选笔刷
	&"paint": "res://assets/sfx/paint.ogg",              # 落笔
	&"clear": "res://assets/sfx/clear.ogg",              # 清空画布
	&"unpin": "res://assets/sfx/close.ogg",              # 空画布确认 = 取消钉住
	&"pin_error": "res://assets/sfx/error.ogg",          # 钉被模型层拒绝
	# 笔记 / 指引 / 故事
	&"drawer_open": "res://assets/sfx/drawer_open.ogg",
	&"drawer_close": "res://assets/sfx/drawer_close.ogg",
	&"page": "res://assets/sfx/page.ogg",                # 翻页 = 纸翻页声(用户要求)
	&"hint": "res://assets/sfx/hint.ogg",                # 操作指引换成新一条
	&"guide": "res://assets/sfx/guide.ogg",              # 语音求助被接受
	&"next": "res://assets/sfx/next.ogg",                # 对话推进到下一句
	&"skip": "res://assets/sfx/zoom.ogg",                # 点一下先把当前句显示完
	&"portrait": "res://assets/sfx/portrait.ogg",        # 立绘换人
	&"win": "res://assets/sfx/win.ogg",                  # 通关(玩家自己解出)
}

## 按槽位的响度修正(dB):ffmpeg volumedetect 量 mean/peak,取 (-18 - mean) 并封顶在 -peak(不削波),见音效位置.md
const GAIN_DB: Dictionary = {
	&"hover": -4.0, &"back": -1.0, &"confirm": -6.5, &"open": -5.5, &"close": -5.5, &"toggle": -4.0,
	&"slider": -6.5, &"reset_progress": -2.0, &"loom": 1.0, &"place": -2.0, &"delete": -2.5, &"refuse": 1.0,
	&"pick": -3.5, &"drop": -2.0, &"plug": -5.5, &"unplug": -0.5, &"error": -5.0, &"warn": -6.0,
	&"snap": -1.5, &"move": -7.0, &"zoom": -6.5, &"undo": -1.0, &"redo": 1.0, &"reset_board": -3.5,
	&"brush": -5.0, &"paint": -6.5, &"clear": -4.0, &"unpin": -5.5, &"pin_error": -5.0, &"drawer_open": -4.0,
	&"drawer_close": -4.0, &"page": 0.0, &"hint": -8.0, &"guide": -8.0, &"next": -3.5, &"skip": -6.5,
	&"portrait": -2.5, &"win": -7.0,
}
const BASE_VOLUME := 0.5                  # 全体基准(约 -6 dB;峰值 -1 dB 的片段修正后不削波)
const POOL_SIZE := 8                      # 同时最多几声
const META := &"sfx"                      # 按钮上的槽位覆盖:set_meta(&"sfx", &"back");&"" = 不出声
const BUTTON_DEFAULT := &"click"

var user_volume := 1.0                    # 玩家「音效音量」(settings.sfx_volume)
var last_slot: StringName = &""           # 最近一次真正播出的槽位 / 帧号(测试与冒烟断言用)
var last_frame := -1
var play_count := 0
var counts: Dictionary = {}               # slot → 播出次数(测试 / 冒烟断言用)

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _streams: Dictionary = {}             # path → AudioStream
var _frame_played: Dictionary = {}        # slot → 上次播出的帧号
var _mute_depth := 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## autoload 顺序 Game → Robot → Bgm → Sfx:读存档里的音效音量(没有 Game 的测试实例保持 1.0)
func _ready() -> void:
	var game := get_node_or_null("/root/Game")
	if game != null and game.save != null:
		user_volume = clampf(float(game.save.settings.get("sfx_volume", 1.0)), 0.0, 1.0)
	get_tree().node_added.connect(_on_node_added)


## 任意 Node 上都能叫:找不到 autoload(测试 / 不在树里)就静默
static func hit(from: Node, slot: StringName) -> void:
	if from == null or not from.is_inside_tree():
		return
	var s := from.get_node_or_null(^"/root/Sfx")
	if s != null:
		s.play(slot)


static func target_volume(slot: StringName) -> float:
	return BASE_VOLUME * db_to_linear(float(GAIN_DB.get(slot, 0.0)))


func play(slot: StringName) -> bool:
	if _mute_depth > 0:
		return false
	var path: String = CLIPS.get(slot, "")
	if path == "":
		return false
	var frame := Engine.get_process_frames()
	if int(_frame_played.get(slot, -1)) == frame:
		return false
	var stream := _stream_for(path)
	if stream == null:
		return false
	_frame_played[slot] = frame
	var p := _idle_player()
	p.stream = stream
	p.volume_linear = target_volume(slot) * user_volume
	if p.is_inside_tree():
		p.play()
	last_slot = slot
	last_frame = frame
	play_count += 1
	counts[slot] = int(counts.get(slot, 0)) + 1
	return true


func set_user_volume(v: float) -> void:
	user_volume = clampf(v, 0.0, 1.0)


func push_mute() -> void:
	_mute_depth += 1


func pop_mute() -> void:
	_mute_depth = maxi(0, _mute_depth - 1)


func is_muted() -> bool:
	return _mute_depth > 0


func is_playing() -> bool:
	for p in _players:
		if p.playing:
			return true
	return false


func _idle_player() -> AudioStreamPlayer:
	for i in _players.size():
		var p := _players[(_next + i) % _players.size()]
		if not p.playing:
			_next = (_next + i + 1) % _players.size()
			return p
	var p := _players[_next]   # 都在响:轮到谁抢谁
	_next = (_next + 1) % _players.size()
	return p


func _stream_for(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	if stream == null:
		push_warning("Sfx: 读不到音效 " + path)
	_streams[path] = stream
	return stream


# ---- 按钮总钩子 ----

func _on_node_added(n: Node) -> void:
	var b := n as BaseButton
	if b == null:
		return
	b.pressed.connect(_on_button_pressed.bind(b))
	b.mouse_entered.connect(_on_button_hover.bind(b))


static func button_slot(b: BaseButton) -> StringName:
	return StringName(str(b.get_meta(META, BUTTON_DEFAULT)))


func _on_button_pressed(b: BaseButton) -> void:
	play(button_slot(b))


func _on_button_hover(b: BaseButton) -> void:
	if not b.disabled and button_slot(b) != &"":
		play(&"hover")
