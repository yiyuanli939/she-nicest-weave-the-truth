extends TestBase
## 标题页设置模块(SettingsPanel)的纯逻辑:全屏 ↔ 窗口模式映射、音量文案/夹取、
## settings 键(music_volume / fullscreen)往返且「重置进度」保留;无 autoload 时弹窗能建、开关、小机两行隐藏。


func test_window_mode_mapping() -> bool:
	var ok := check(SettingsPanel.window_mode_for(true) == DisplayServer.WINDOW_MODE_FULLSCREEN, "全屏开 = 全屏窗口模式")
	ok = check(SettingsPanel.window_mode_for(false, false) == DisplayServer.WINDOW_MODE_MAXIMIZED, "桌面:全屏关 = 回工程默认的最大化") and ok
	ok = check(SettingsPanel.window_mode_for(false, true) == DisplayServer.WINDOW_MODE_WINDOWED and SettingsPanel.window_mode_for(true, true) == DisplayServer.WINDOW_MODE_FULLSCREEN,
			"Web:全屏关 = 窗口模式(浏览器只认 WINDOWED 退出全屏,MAXIMIZED 是空操作)") and ok
	ok = check(SettingsPanel.is_fullscreen_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			and SettingsPanel.is_fullscreen_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			and not SettingsPanel.is_fullscreen_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
			and not SettingsPanel.is_fullscreen_mode(DisplayServer.WINDOW_MODE_WINDOWED), "两种全屏算开,最大化/窗口算关") and ok
	return ok


func test_volume_helpers() -> bool:
	var ok := check(SettingsPanel.volume_text(0.5) == "50%" and SettingsPanel.volume_text(1.0) == "100%" and SettingsPanel.volume_text(0.0) == "0%", "音量文案 = 整数百分比")
	ok = check(is_equal_approx(SettingsPanel.clamp_volume(1.7), 1.0) and is_equal_approx(SettingsPanel.clamp_volume(-0.2), 0.0), "音量夹到 0..1") and ok
	ok = check(SettingsPanel.volume_text(3.0) == "100%", "越界值文案也夹住") and ok
	return ok


func test_settings_keys_round_trip_and_survive_wipe() -> bool:
	var before := SaveManager.open().settings.duplicate(true)   # 跑完还原开发机的设置
	var sm := SaveManager.new()
	sm.mark_solved(&"l01")
	sm.settings["music_volume"] = 0.35
	sm.settings["fullscreen"] = true
	sm.save()
	var sm2 := SaveManager.open()
	var ok := check(is_equal_approx(float(sm2.settings.get("music_volume", -1.0)), 0.35) and sm2.settings.get("fullscreen") == true, "音量 / 全屏往返")
	sm2.wipe()
	var sm3 := SaveManager.open()
	ok = check(not sm3.is_solved(&"l01") and is_equal_approx(float(sm3.settings.get("music_volume", -1.0)), 0.35)
			and sm3.settings.get("fullscreen") == true, "重置进度保留音量 / 全屏") and ok
	sm3.settings = before
	sm3.save()
	return ok


func test_panel_without_autoloads() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var p := SettingsPanel.new()
	tree.root.add_child(p)   # Range 只在树里才发 value_changed
	p.setup(null, null, null, null)
	var ok := check(not p.visible, "建好时弹窗是关着的")
	p.open()
	ok = check(p.visible, "open 打开") and ok
	ok = check(not p._robot_btn.visible and not p._maint_btn.visible, "没有 Robot:小机联动 / 小机维护两行隐藏") and ok
	ok = check(p._fullscreen_btn.text == "全屏:关", "无头下全屏显示关(得 %s)" % p._fullscreen_btn.text) and ok
	ok = check(is_equal_approx(p._volume.value, SettingsPanel.VOLUME_DEFAULT) and p._volume_lbl.text == "100%", "默认音量 100%") and ok
	var texts: Array[String] = []
	for c in p.find_children("*", "Control", true, false):
		if c is Label:
			texts.append((c as Label).text)
		elif c is Button:
			texts.append((c as Button).text)
	ok = check(texts.has("设置") and texts.has("音乐音量") and texts.has("小机维护") and texts.has("关闭"), "文字齐全(得 %s)" % str(texts)) and ok
	p.close()
	ok = check(not p.visible, "close 关上") and ok
	# 百分数标签按「100%」预留宽度:拖到 5% 时行宽不变(否则整行在列里来回挪)
	var w100 := p._volume_lbl.get_combined_minimum_size().x
	p._volume.value = 0.05
	ok = check(p._volume_lbl.text == "5%" and is_equal_approx(p._volume_lbl.get_combined_minimum_size().x, w100), "百分数标签宽度固定(100%% → 5%%:%.0f → %.0f,文案 %s)" % [w100, p._volume_lbl.get_combined_minimum_size().x, p._volume_lbl.text]) and ok
	tree.root.remove_child(p)
	p.free()
	return ok
