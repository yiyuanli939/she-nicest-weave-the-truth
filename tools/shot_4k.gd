extends SceneTree
## 1:1 全分辨率截图(3840×2160)给美术对照 —— 冒烟测试的截图随窗口缩放(Mac 上是 0.7875×),肉眼对不准像素。
## 这里把各界面放进一个 3840×2160 的 SubViewport 离屏渲染再存 PNG,与窗口大小无关;不改存档。
##   "$GODOT" --path . --script res://tools/shot_4k.gd
## 出图(build/shots4k/,已 gitignore + .gdignore,编辑器不会给截图生成 .import):
##   4k_title.png 标题页 / 4k_story.png 第一关开场对话第一句 / 4k_level.png 第一个上架 ≥2 台仪器的关 / 4k_notebook.png 同关笔记划出(有「翻页」)。
## 对照法:与 笔记本页面补充/位置参考.png、美术预览图叠图看边,或用 Python(PIL/numpy)做模板匹配;
## 引擎常量与参考实测数字见 docs/ART_INTERFACE.md「参考基准与实测值」。

const OUT_DIR := "res://build/shots4k"
const SIZE := Vector2i(3840, 2160)

var _sv: SubViewport


func _initialize() -> void:
	await process_frame
	OS.low_processor_usage_mode = false   # 项目开了低功耗模式(画面没变化不重绘),离屏渲染要每帧都画
	var game := root.get_node("/root/Game")
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

	await _shot(load("res://ui/main_menu.tscn").instantiate(), "4k_title", 0.6)

	game.current = first
	game.ending_pending = false
	await _shot(load("res://ui/story_scene.tscn").instantiate(), "4k_story", 2.5)   # 等打字机把第一句打完

	game.current = with_machines
	var scene: LevelScene = load("res://ui/level_scene.tscn").instantiate()
	_mount(scene)
	await _wait(0.6)
	_save("4k_level")
	scene._notebook_ui.open(game.notebook, scene.allowed_rules)   # 直接开抽屉(不走 _on_open_notebook,不写存档)
	await scene._notebook_ui.slide_finished
	await _wait(0.3)
	_save("4k_notebook")
	_unmount()
	print("4K 截图已写到 %s/4k_*.png" % OUT_DIR)
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
	img.save_png("%s/%s.png" % [OUT_DIR, tag])
	print("  %s.png %dx%d" % [tag, img.get_width(), img.get_height()])
