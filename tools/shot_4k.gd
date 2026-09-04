extends SceneTree
## 1:1 全分辨率截图(3840×2160)给美术对照 —— 冒烟测试的截图随窗口缩放(Mac 上是 0.7875×),肉眼对不准像素。
## 这里把各界面放进一个 3840×2160 的 SubViewport 离屏渲染再存 PNG,与窗口大小无关;存档先备份、出完图复原
## (摆机 / 接线会让 LevelScene 把操作指引 steps 记进存档,headless test_sfx_hooks 要求开发机存档没有 steps)。
##   "$GODOT" --path . --script res://tools/shot_4k.gd
## 出图(build/shots4k/,已 gitignore + .gdignore,编辑器不会给截图生成 .import):
##   4k_title.png 标题页 / 4k_story.png 第一关开场对话第一句 / 4k_level.png 第一个上架 ≥2 台仪器的关 / 4k_notebook.png 同关笔记划出(有「翻页」)
##   4k_machines.png 七台仪器全摆上棋盘(v1.1 端口/边框/钉按钮/封程机凹形/汇路机分割线)/ 4k_editor.png 纹样绘制弹窗
##   4k_editor_bot.png 同弹窗解锁焦纹(第四章)时的笔刷行:第四个笔刷是焦纹图样(v1.2)
##   4k_settings.png 标题页「设置」弹窗 / 4k_win.png 通关弹窗「织成了」(v1.2,直接弹出不走通关:通关会写存档)/ 4k_maint.png 小机维护面板。
##   `-- en`:切到英文再出图(文件名 4k_en_*.png):翻译键换英文、烧字的图换 <名字>.en.png、台词 text_en —— 给美术对照英文版。
## 对照法:与 笔记本页面补充/位置参考.png、美术预览图叠图看边,或用 Python(PIL/numpy)做模板匹配;
## 引擎常量与参考实测数字见 docs/ART_INTERFACE.md「参考基准与实测值」。

const OUT_DIR := "res://build/shots4k"
const SIZE := Vector2i(3840, 2160)

var _sv: SubViewport
var _prefix := "4k_"


func _initialize() -> void:
	await process_frame
	OS.low_processor_usage_mode = false   # 项目开了低功耗模式(画面没变化不重绘),离屏渲染要每帧都画
	var game := root.get_node("/root/Game")
	var save_backup := FileAccess.get_file_as_bytes(SaveManager.PATH)   # 出完图原样写回
	if OS.get_cmdline_user_args().has("en"):   # 英文版出图(只切运行态 locale,不写 settings)
		Loc.apply("en")
		_prefix = "4k_en_"
	AudioServer.set_bus_mute(0, true)   # 出图别出声
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var first: LevelDef = game.catalog.chapters[0].levels[0]
	var with_machines: LevelDef = first   # 关内/笔记截图要有仪器架按钮、整页图和「翻页」:取第一个上架 ≥2 台仪器的关
	for ch in game.catalog.chapters:
		for lv in ch.levels:
			if lv.allowed_rules.size() >= 2:
				with_machines = lv
				break
		if with_machines != first:
			break

	var menu: MainMenu = load("res://ui/main_menu.tscn").instantiate()
	_mount(menu)
	await _wait(0.6)
	_save("4k_title")
	menu._settings.open()
	await _wait(0.3)
	_save("4k_settings")
	menu._settings.close()
	var robot := root.get_node_or_null("/root/Robot")
	if robot != null:
		menu._cal_ui.open(robot)
		await _wait(0.3)
		_save("4k_maint")
		menu._cal_ui.visible = false
	_unmount()

	game.current = first
	game.ending_pending = false
	await _shot(load("res://ui/story_scene.tscn").instantiate(), "4k_story", 2.5)   # 等打字机把第一句打完

	game.current = with_machines
	var scene: LevelScene = load("res://ui/level_scene.tscn").instantiate()
	_mount(scene)
	await _wait(0.6)
	if scene._notebook_ui.is_open():   # 首次上架仪器的关进关自动弹笔记(v1.1 §5):先收起,棋盘单独一张
		scene._notebook_ui.close()
		await scene._notebook_ui.slide_finished
		await _wait(0.2)
	_save("4k_level")
	scene._win_popup.open()
	await _wait(0.3)
	_save("4k_win")
	scene._win_popup.close()
	var debut: Array[StringName] = game.catalog.debut_rules(game.current)   # 有新上架的仪器就翻到它那页(带「新机器!」)
	if debut.is_empty():
		scene._notebook_ui.open(game.notebook, scene.allowed_rules)   # 直接开抽屉(不走 _on_open_notebook,不写存档)
	else:
		scene._notebook_ui.open_at(game.notebook, scene.allowed_rules, debut[0])
	await scene._notebook_ui.slide_finished
	await _wait(0.3)
	_save("4k_notebook")
	_unmount()

	# 七台仪器 + 弹窗(v1.1):用 first(无存档棋盘干扰的关)摆机,笔记若自动弹出先收起
	game.current = first
	var scene2: LevelScene = load("res://ui/level_scene.tscn").instantiate()
	_mount(scene2)
	await _wait(0.6)
	if scene2._notebook_ui.is_open():
		scene2._notebook_ui.close()
		await scene2._notebook_ui.slide_finished
	var rules: Array[StringName] = [&"and_intro", &"and_elim", &"or_intro", &"or_elim", &"imp_intro", &"imp_elim", &"false_elim"]
	var spots: Array[Vector2] = [Vector2(520, 120), Vector2(520, 640), Vector2(520, 1160), Vector2(1100, 120),
			Vector2(1100, 760), Vector2(1700, 120), Vector2(1700, 640)]
	var ids: Array[int] = []
	for i in rules.size():
		scene2._board.place_machine_at_center(rules[i])
		var id: int = scene2.session.get_node_ids()[-1]
		ids.append(id)
		scene2.session.set_node_position(id, spots[i])
	scene2._board.apply_positions()
	scene2.session.pin_hypothesis(ids[4], 1, "A")           # 封程机钉 A:一口钉住、其余可钉口留蚂蚁线
	scene2.session.connect_wire(ids[4], 1, ids[1], 0)       # 假设线 → 拆股机:整条假设色
	await _wait(0.4)
	_save("4k_machines")
	scene2._on_pin_requested(ids[2], 0)                     # 岔纹机上口的纹样绘制弹窗
	await _wait(0.4)
	_save("4k_editor")
	scene2._editor.open_for(scene2.atoms, scene2.atom_colors, null, true)   # 解锁焦纹:多一个焦纹图样笔刷
	await _wait(0.4)
	_save("4k_editor_bot")
	scene2._editor.hide()
	_unmount()
	print("4K 截图已写到 %s/%s*.png" % [OUT_DIR, _prefix])
	Loc.apply(Loc.DEFAULT)
	var f := FileAccess.open(SaveManager.PATH, FileAccess.WRITE)
	if f != null:
		f.store_buffer(save_backup)
		f.close()
	quit(0)


func _shot(scene: Node, tag: String, settle_sec: float) -> void:
	_mount(scene)
	await _wait(settle_sec)
	_save(tag)
	_unmount()


func _mount(scene: Node) -> void:
	_sv = SubViewport.new()
	_sv.size = SIZE
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.gui_disable_input = true
	_sv.gui_embed_subwindows = true   # 弹窗(PopupPanel 是 Window)嵌进离屏视口,截图才带上它
	if "oversampling_override" in _sv:
		_sv.oversampling_override = 1.0   # 字体按 1:1 栅格化(4.5+ 每视口过采样)
	root.add_child(_sv)
	_sv.add_child(scene)


func _unmount() -> void:
	_sv.queue_free()
	_sv = null


func _wait(sec: float) -> void:
	await create_timer(sec).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _save(tag: String) -> void:
	var img := _sv.get_texture().get_image()
	img.save_png("%s/%s%s.png" % [OUT_DIR, _prefix, tag.trim_prefix("4k_")])
	print("  %s%s.png %dx%d" % [_prefix, tag.trim_prefix("4k_"), img.get_width(), img.get_height()])
