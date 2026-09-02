extends Node
## Autoload "Bgm":背景音乐。槽位 -> 文件见 TRACKS(与 music/音乐bgm位置.md 一一对应)。
## 场景在 _ready 里 play(槽位):同槽位不重启(标题/选关/开发者信息互切、同章下一关),
## 换槽位用两个播放器交叉淡化;槽位没曲子就淡出到静音(补曲只改 TRACKS 一行)。
## 故事界面(开场 / 结局对话)也报 title:从选关进来标题曲接着播不重启,从棋盘进来关内曲淡出换回标题曲;关内曲只在棋盘起。
## 音量:基准 VOLUME_LINEAR × 文件响度修正 × 玩家设置 user_volume(标题页设置模块的滑条,存 settings.music_volume,启动时这里读)。

const TRACKS: Dictionary = {
	&"title": "res://music/title.mp3",   # 标题 / 选关 / 故事界面(开场 / 结局对话)/ 开发者信息
	&"level_1": "res://music/level_1.wav",  # 第一章 并纹:level.wav 柔和版(低通 + 轻混响;tools/level_music/level_remix.py soft)
	&"level_2": "res://music/level_2.wav",  # 第二章 叠层纹:脉动版(半拍颤音 + 合唱;pulse)
	&"level_3": "res://music/level_3.wav",  # 第三章 岔纹:暗调版(降两个半音拉回原速 + 长回声;dark)
	&"level_4": "res://music/level.wav",    # 第四章 焦纹:原版
}
const VOLUME_LINEAR := 0.32   # 约 -10 dB:钢琴 BGM 压低,给实体小机的喇叭留空间
const FADE_SEC := 1.2
## 按文件的响度修正(dB):不同来源响度不一,压平到标题曲(基准 0);RMS 量法见 music/音乐bgm位置.md
const GAIN_DB: Dictionary = {
	"res://music/level.wav": -5.5,     # RMS -18.5 dBFS,标题曲 -24.0
	"res://music/level_1.wav": -3.0,   # RMS -20.9(loudnorm 后)
	"res://music/level_2.wav": -4.0,   # RMS -19.9
	"res://music/level_3.wav": -3.0,   # RMS -20.9
}

var slot: StringName = &""    # 当前请求的槽位(静音槽位也记着,同槽位再调才能免重启)
var user_volume := 1.0        # 玩家设置的音乐音量(0..1),乘在 target_volume 上;SettingsPanel 改,启动时 _ready 从 settings 读
var _path := ""               # 正在播的文件("" = 静音);几个槽位共用一首时换槽位不重启

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _tween: Tween
var _streams: Dictionary = {}   # path -> AudioStream 缓存


## 播放器在构造时建好(不是 _ready):测试 new() 后直接可用,进树前 _ready 不一定同步跑
func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_linear = 0.0
		add_child(p)
		_players.append(p)


## autoload 顺序 Game → Robot → Bgm:这里能读到存档里的音量设置(没有 Game 的测试实例保持 1.0)
func _ready() -> void:
	var game := get_node_or_null("/root/Game")
	if game != null and game.save != null:
		user_volume = clampf(float(game.save.settings.get("music_volume", 1.0)), 0.0, 1.0)


## 章号(Game.current_chapter,0..3)对应关内槽位;-1(无 Game / 测试注入关)给空槽位 = 静音
static func slot_for_chapter(ch: int) -> StringName:
	if ch >= 0 and ch <= 3:
		return StringName("level_%d" % (ch + 1))
	return &""


## 某文件的目标音量(线性)= 基准音量 x 响度修正(不含玩家设置;实际播放用 _target)
static func target_volume(path: String) -> float:
	return VOLUME_LINEAR * db_to_linear(float(GAIN_DB.get(path, 0.0)))


func _target(path: String) -> float:
	return target_volume(path) * user_volume


## 玩家改音量(设置模块滑条):当场生效。淡化进行中就直接落到终态(来者到目标音量、去者停),不等淡化结束
func set_user_volume(v: float) -> void:
	user_volume = clampf(v, 0.0, 1.0)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	for i in _players.size():
		var p := _players[i]
		if i == _active:
			p.volume_linear = _target(_path)
		else:
			p.volume_linear = 0.0
			p.stop()


func play(new_slot: StringName) -> void:
	if new_slot == slot:
		return
	slot = new_slot
	var path: String = TRACKS.get(new_slot, "")
	if path == _path:
		return   # 同一首(两章共用)或静音到静音:只记槽位,不重启
	_path = path
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var outgoing := _players[_active]
	_active = 1 - _active
	var incoming := _players[_active]
	# 淡化中途再切:去者从当前音量接着淡出;来者是上一轮的去者(尾音已很小),直接复用
	incoming.stop()
	incoming.stream = _stream_for(new_slot)
	incoming.volume_linear = 0.0
	if incoming.stream != null:
		incoming.play()
	# 只 tween volume_linear,别碰 volume_db(0 线性 = -inf dB)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(incoming, "volume_linear", _target(path), FADE_SEC)
	_tween.tween_property(outgoing, "volume_linear", 0.0, FADE_SEC)
	_tween.chain().tween_callback(outgoing.stop)


func stop() -> void:
	play(&"")


func is_playing() -> bool:
	for p in _players:
		if p.playing:
			return true
	return false


func active_player() -> AudioStreamPlayer:
	return _players[_active]


## 按路径缓存加载;三种格式都经 set_looping 设整曲循环,音乐同学交 mp3 / ogg / wav 都行
func _stream_for(s: StringName) -> AudioStream:
	var path: String = TRACKS.get(s, "")
	if path == "":
		return null
	if _streams.has(path):
		return _streams[path]
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("Bgm: 加载失败 %s(槽位 %s)" % [path, s])
		return null
	set_looping(stream)
	_streams[path] = stream
	return stream


## 整曲循环。wav 要连循环点一起设:导入器只在 .import 选了 Forward 时才写 loop_end,「Detect From WAV」+ 无 smpl 块
## 的 wav 导入后 loop_end=0,只开 loop_mode 会让混音在第 0 帧就碰到循环末尾、混 1 帧即停(关内无声,2026-09 踩过)。
## 没有循环点就整曲循环(loop_end = 帧数-1,与导入器 loop_end=-1 的约定一致);wav 自带 smpl 循环点则保留。
static func set_looping(stream: AudioStream) -> void:
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		if wav.loop_end <= wav.loop_begin:
			wav.loop_begin = 0
			wav.loop_end = int(round(wav.get_length() * wav.mix_rate)) - 1
