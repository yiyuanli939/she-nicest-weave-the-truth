extends TestBase
## 小机剧情机制的纯逻辑(不需要真机/桥接):语音命中、章节 → 模式、故障态 cue 映射、回头目标、设置持久化。

const ROBOT := "res://game/robot_link.gd"
const GAME := "res://game/game.gd"


func _rl() -> GDScript:
	return load(ROBOT)


func test_guide_phrase_matching() -> bool:
	var rl := _rl()
	return check(rl.matches_guide("请 指导 我"), "Vosk 带空格输出") \
		and check(rl.matches_guide("请指导我"), "无空格") \
		and check(rl.matches_guide("请 帮帮 我") and rl.matches_guide("请 帮 帮 我"), "「请帮帮我」(含单字退化)") \
		and check(not rl.matches_guide("今天 天气 不错") and not rl.matches_guide(""), "无关句不命中")


func test_chapter_lookup_and_robot_mode() -> bool:
	var cat := LevelCatalog.load_default()
	var game := load(GAME)
	var ok := check(cat.chapter_of(cat.find(&"l01")) == 0 and cat.chapter_of(cat.find(&"l05")) == 1
			and cat.chapter_of(cat.find(&"l10")) == 2 and cat.chapter_of(cat.find(&"l13")) == 3, "l01/l05/l10/l13 → 第 1/2/3/4 章")
	ok = check(cat.chapter_of(LevelDef.new()) == -1, "不在目录的关 → -1") and ok
	ok = check(game.robot_mode_for_chapter(0) == "guide" and game.robot_mode_for_chapter(1) == "guide", "一二章代解") and ok
	ok = check(game.robot_mode_for_chapter(2) == "broken", "第三章故障") and ok
	ok = check(game.robot_mode_for_chapter(3) == "look", "第四章只回头") and ok
	ok = check(game.robot_mode_for_chapter(-1) == "off", "目录外不触发") and ok
	return ok


func test_broken_cue_mapping() -> bool:
	var rl := _rl()
	var normal: Array = rl.commands_for("celebrate", false)
	var broken: Array = rl.commands_for("celebrate", true)
	var ok := check(normal.size() == 3 and normal[2].get("name") == "win", "正常态 celebrate 播 win")
	ok = check(broken.size() == 3 and broken[0].get("name") == "glitch" and broken[1].get("name") == "panic"
			and String(broken[2].get("name")).begins_with("glitch"), "故障态任何 cue 都是故障脸 + 乱动 + 坏掉音效(没有台词)") and ok
	ok = check(rl.commands_for("hint", true)[0].get("name") == "glitch", "故障态 hint 也故障") and ok
	ok = check(rl.commands_for("panic", false)[2].get("name") == "glitch1" and rl.commands_for("panic", false, 2)[2].get("name") == "glitch3"
			and rl.commands_for("panic", false, 3)[2].get("name") == "glitch1", "panic 没有台词,音效按 variant 循环取 glitch1..3") and ok
	for c in rl.commands_for("celebrate", true) + rl.commands_for("panic", false):
		ok = check(not (c.get("cmd") == "say" and c.get("name") == "panic"), "故障演出里没有 say panic(那句台词已删)") and ok
	ok = check(rl.commands_for("sleep", true) == [{cmd = "emote", name = "sleep"}], "故障态 sleep 例外照发") and ok
	ok = check(rl.commands_for("自定义", false) == [{cmd = "emote", name = "自定义"}], "未知 cue 原样当 emote") and ok
	return ok


func test_turn_targets() -> bool:
	var rl := _rl()
	return check(rl.turn_target("right") == 130 and rl.turn_target("left") == 50, "右=130 左=50(固件限位)") \
		and check(rl.turn_target("乱填") == 130, "非法值当右")


func test_settings_survive_wipe() -> bool:
	var sm := SaveManager.new()
	sm.mark_solved(&"l01")
	sm.settings["robot_turn"] = "left"
	sm.save()
	var sm2 := SaveManager.open()
	var ok := check(sm2.settings.get("robot_turn") == "left", "settings 往返")
	sm2.wipe()
	var sm3 := SaveManager.open()
	ok = check(not sm3.is_solved(&"l01") and sm3.settings.get("robot_turn") == "left", "重置进度保留 settings") and ok
	sm3.settings.clear()
	sm3.save()
	return ok


## 关卡数据:第三章开头当场故障(panic)、第四章开头修好(calm),其余进关无演出
func test_enter_cues_mark_breakdown_and_repair() -> bool:
	var cat := LevelCatalog.load_default()
	var ok := check(cat.find(&"l10").robot_cue_on_enter == "panic", "l10 进关 panic")
	ok = check(cat.find(&"l13").robot_cue_on_enter == "calm", "l13 进关 calm") and ok
	for lv in cat.all_levels():
		if lv.id != &"l10" and lv.id != &"l13":
			ok = check(lv.robot_cue_on_enter == "", "%s 进关无演出" % lv.id) and ok
	return ok


## 台词配置 lines.json:五句都有 wav、音色/音量合法、不再出现「织者」;故障没有台词(也不许出现警告/核心之类字样),只有三段合成音效
func test_voice_lines_config() -> bool:
	var txt := FileAccess.get_file_as_string("res://hardware/firmware/sounds/lines.json")
	var d: Variant = JSON.parse_string(txt)
	var ok := check(d is Dictionary and (d as Dictionary).has("lines"), "lines.json 可解析")
	if not ok:
		return false
	var lines: Dictionary = d.lines
	ok = check(not lines.has("panic") and not FileAccess.file_exists("res://hardware/firmware/sounds/panic.wav"), "故障没有台词(panic 句已删)") and ok
	for cue: String in lines:
		for bad in ["警告", "核心", "过热", "混乱"]:
			ok = check(not String(lines[cue]).contains(bad), "台词 %s 不得含「%s」" % [cue, bad]) and ok
	for i in [1, 2, 3]:
		ok = check(FileAccess.file_exists("res://hardware/firmware/sounds/glitch%d.wav" % i), "坏掉音效 glitch%d.wav 存在" % i) and ok
	for cue in ["greet", "win", "encourage", "hint", "calm"]:
		ok = check(lines.has(cue) and String(lines[cue]) != "", "台词 %s 存在" % cue) and ok
		ok = check(ResourceLoader.exists("res://hardware/firmware/sounds/%s.wav" % cue) or FileAccess.file_exists("res://hardware/firmware/sounds/%s.wav" % cue), "%s.wav 存在" % cue) and ok
		ok = check(not String(lines[cue]).contains("织者"), "%s 台词称呼用诺拉不用织者" % cue) and ok
	var gain: float = float(d.get("gain", 0))
	return ok and check(gain > 0.0 and gain <= 1.0, "音量 0-1") and check(String(d.get("voice", "")).begins_with("zh-CN-"), "音色是中文神经语音")


## RobotLink 解析固件回报:gimbal ack 与 ready 的外设标志(不需要真机,直接注入事件)
func test_robot_link_parses_ack_and_ready() -> bool:
	var rl: Node = _rl().new()
	rl._on_event({"evt": "ready", "oled": false, "audio": true})
	var ok := check(not rl.oled_ok and rl.audio_ok, "ready 带屏幕/功放状态")
	rl._on_event({"evt": "gimbal", "pan": 130, "tilt": 90})
	ok = check(rl.last_gimbal_ack.get("pan") == 130 and rl.last_gimbal_ack.get("tilt") == 90, "gimbal ack 记下角度") and ok
	rl._on_event({"evt": "serial", "open": true})
	ok = check(rl.serial_open, "serial 事件") and ok
	rl.free()
	return ok
