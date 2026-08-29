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
	bgm.play(&"level_1")
	ok = check(bgm.slot == &"level_1" and bgm.active_player() != p0 and bgm.active_player().stream == null, "空槽位:来者无曲,槽位仍记住") and ok
	bgm.play(&"level_1")
	ok = check(bgm.slot == &"level_1" and bgm.active_player().stream == null, "空槽位同槽位再 play 无事") and ok
	bgm.stop()
	ok = check(bgm.slot == &"", "stop = 空槽位") and ok
	tree.root.remove_child(bgm)
	bgm.free()
	return ok
