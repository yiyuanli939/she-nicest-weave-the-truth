extends TestBase
## 背景音乐:槽位表与 music/音乐bgm位置.md 一致、文件真实存在(先跑 --import)、章号到槽位、
## 同槽位不重启、空槽位静音。播放行为用自建实例测,不碰 autoload。
## 退出时「AudioStreamMP3 / AudioStreamPlaybackMP3 leaked」「title.mp3 still in use」是引擎退出不回收 playback,无害(游戏退出同样会报)。

const BGM_SCRIPT := "res://game/bgm.gd"


func test_tracks_table_matches_doc() -> bool:
	var B: GDScript = load(BGM_SCRIPT)
	var keys: Array[String] = []
	for k in B.TRACKS:
		keys.append(String(k))
	keys.sort()
	var ok := check(keys == ["level_1", "level_2", "level_3", "level_4", "title"], "槽位集合 = title + level_1..4,得 %s" % str(keys))
	ok = check(B.TRACKS[&"title"] != "", "标题曲已填") and ok
	for k in B.TRACKS:
		var path: String = B.TRACKS[k]
		if path != "":
			ok = check(ResourceLoader.exists(path), "槽位 %s 的文件不存在或未导入(先跑 --import):%s" % [k, path]) and ok
	return ok


func test_gain_table_levels_loudness() -> bool:
	var B: GDScript = load(BGM_SCRIPT)
	var ok := true
	var paths: Array = B.TRACKS.values()
	for p in B.GAIN_DB:
		ok = check(paths.has(p), "GAIN_DB 里的文件 %s 也在 TRACKS 里(别留死条目)" % p) and ok
	ok = check(is_equal_approx(B.target_volume("res://music/title.mp3"), B.VOLUME_LINEAR), "标题曲 = 基准音量") and ok
	ok = check(is_equal_approx(B.target_volume("res://music/level.wav"), B.VOLUME_LINEAR * db_to_linear(-5.5)), "关内曲压低 5.5 dB") and ok
	return ok


func test_slot_for_chapter() -> bool:
	var B: GDScript = load(BGM_SCRIPT)
	var seen := {}
	var ok := true
	for ch in 4:
		var s: StringName = B.slot_for_chapter(ch)
		ok = check(B.TRACKS.has(s), "第 %d 章槽位 %s 在表里" % [ch + 1, s]) and ok
		seen[s] = true
	ok = check(seen.size() == 4, "四章槽位互不相同") and ok
	ok = check(B.slot_for_chapter(-1) == &"" and B.slot_for_chapter(4) == &"", "无 Game / 越界章号 = 空槽位(静音)") and ok
	return ok


func test_play_same_slot_keeps_player_and_empty_slot_is_silent() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if not check(tree != null, "有 SceneTree"):
		return false
	var bgm: Node = (load(BGM_SCRIPT) as GDScript).new()
	tree.root.add_child(bgm)   # 播放器在 _init 建好;play() 要求在树里
	var ok := true
	bgm.play(&"title")
	ok = check(bgm.slot == &"title" and bgm.is_playing(), "play(title) 开始播放") and ok
	var p0: AudioStreamPlayer = bgm.active_player()
	ok = check(p0.stream != null and p0.stream.get("loop") == true, "标题曲已设循环") and ok
	bgm.play(&"title")
	ok = check(bgm.active_player() == p0 and p0.playing, "同槽位再 play 不重启、不换播放器") and ok
	bgm.play(&"")   # 章号 -1(无 Game / 测试注入关)= 空槽位
	ok = check(bgm.slot == &"" and bgm.active_player() != p0 and bgm.active_player().stream == null, "空槽位:来者无曲(标题曲淡出到静音)") and ok
	bgm.play(&"no_such_slot")
	ok = check(bgm.slot == &"no_such_slot" and bgm.active_player().stream == null, "表里没有的槽位 = 静音;静音到静音只记槽位") and ok
	bgm.stop()
	ok = check(bgm.slot == &"", "stop = 空槽位") and ok
	tree.root.remove_child(bgm)
	bgm.free()
	return ok


func test_level_slots_share_one_looping_track() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var bgm: Node = (load(BGM_SCRIPT) as GDScript).new()
	tree.root.add_child(bgm)
	var ok := true
	bgm.play(&"title")
	var p0: AudioStreamPlayer = bgm.active_player()
	bgm.play(&"level_1")
	var p1: AudioStreamPlayer = bgm.active_player()
	ok = check(p1 != p0 and p1.playing and p1.stream != null, "进关内换播放器播关内曲") and ok
	ok = check(p1.stream is AudioStreamWAV and p1.stream.get("loop_mode") == AudioStreamWAV.LOOP_FORWARD, "关内曲 wav 已设循环") and ok
	var wav := p1.stream as AudioStreamWAV
	var frames := int(round(wav.get_length() * wav.mix_rate))
	ok = check(wav.loop_begin == 0 and wav.loop_end == frames - 1 and frames > 44100, "关内曲 wav 循环点覆盖整曲(导入无 smpl 块时 loop_end 默认 0:只设 loop_mode 会混 1 帧即停 → 关内无声),得 %d..%d / %d 帧" % [wav.loop_begin, wav.loop_end, frames]) and ok
	bgm.play(&"level_3")
	ok = check(bgm.slot == &"level_3" and bgm.active_player() == p1 and p1.playing, "换章但同一首:不重启不换播放器") and ok
	bgm.play(&"title")
	ok = check(bgm.active_player() == p0 and p0.playing, "回标题换回标题曲") and ok
	tree.root.remove_child(bgm)
	bgm.free()
	return ok


## 玩家音量(设置模块滑条)乘在目标音量上、当场生效;淡化中途改音量直接落到终态
func test_user_volume_scales_playback() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var B: GDScript = load(BGM_SCRIPT)
	var bgm: Node = B.new()
	tree.root.add_child(bgm)
	var ok := check(is_equal_approx(bgm.user_volume, 1.0), "没有 Game 的实例默认音量 1.0")
	bgm.play(&"title")
	var p0: AudioStreamPlayer = bgm.active_player()
	bgm.set_user_volume(0.5)
	ok = check(is_equal_approx(p0.volume_linear, B.target_volume("res://music/title.mp3") * 0.5) and p0.playing, "改到 50%:淡入被截断,当场落到目标音量 x 0.5") and ok
	bgm.set_user_volume(1.7)
	ok = check(is_equal_approx(bgm.user_volume, 1.0) and is_equal_approx(p0.volume_linear, B.target_volume("res://music/title.mp3")), "越界夹到 1.0") and ok
	bgm.play(&"level_1")
	bgm.set_user_volume(0.0)
	var p1: AudioStreamPlayer = bgm.active_player()
	ok = check(p1 != p0 and is_equal_approx(p1.volume_linear, 0.0) and not p0.playing, "换曲淡化中改成 0:来者静音、去者立即停") and ok
	tree.root.remove_child(bgm)
	bgm.free()
	return ok


func test_set_looping_covers_whole_wav_and_keeps_existing_loop_points() -> bool:
	var B: GDScript = load(BGM_SCRIPT)
	var ok := true
	var pcm := PackedByteArray()
	pcm.resize(1000 * 2)   # 1000 帧 16-bit 单声道静音
	# 没有循环点的 wav(导入器「Detect From WAV」+ 无 smpl 块的产物):整曲循环,loop_end = 帧数-1(导入器 loop_end=-1 的约定)
	var plain := AudioStreamWAV.new()
	plain.format = AudioStreamWAV.FORMAT_16_BITS
	plain.stereo = false
	plain.mix_rate = 44100
	plain.data = pcm
	B.set_looping(plain)
	ok = check(plain.loop_mode == AudioStreamWAV.LOOP_FORWARD and plain.loop_begin == 0 and plain.loop_end == 999, "无循环点的 wav → 整曲循环 0..999,得 %d..%d" % [plain.loop_begin, plain.loop_end]) and ok
	# 自带循环点的 wav(smpl 块 / .import 手填的无缝循环):原样保留
	var cut := AudioStreamWAV.new()
	cut.format = AudioStreamWAV.FORMAT_16_BITS
	cut.data = pcm
	cut.loop_begin = 10
	cut.loop_end = 100
	B.set_looping(cut)
	ok = check(cut.loop_mode == AudioStreamWAV.LOOP_FORWARD and cut.loop_begin == 10 and cut.loop_end == 100, "自带循环点的 wav 原样保留,得 %d..%d" % [cut.loop_begin, cut.loop_end]) and ok
	var mp3 := AudioStreamMP3.new()
	B.set_looping(mp3)
	ok = check(mp3.loop, "mp3 设 loop") and ok
	return ok
