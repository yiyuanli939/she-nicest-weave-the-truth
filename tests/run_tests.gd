extends SceneTree
## 测试入口(不依赖任何插件)。运行:
##   godot --headless --path . --script res://tests/run_tests.gd
## 退出码 = 失败数,CI 直接可用。
## 约定:测试文件 extends TestBase,方法以 test_ 开头、返回 bool。

const FILES: Array[String] = [
	"res://tests/test_formula.gd",
	"res://tests/test_parser.gd",
	"res://tests/test_unifier.gd",
	"res://tests/test_graph.gd",
	"res://tests/test_scope.gd",
	"res://tests/test_serialize.gd",
	"res://tests/test_session.gd",
	"res://tests/test_pattern_layout.gd",
	"res://tests/test_pattern_editor.gd",
	"res://tests/test_levels.gd",
	"res://tests/test_solver_exhaustive.gd",
	"res://tests/test_story_art.gd",
	"res://tests/test_dialogue_import.gd",
	"res://tests/test_theme.gd",
	"res://tests/test_res_paths.gd",
	"res://tests/test_robot_logic.gd",
	"res://tests/test_step_guide.gd",
	"res://tests/test_bgm.gd",
	"res://tests/test_perf_settings.gd",
	"res://tests/test_art_alignment.gd",
]


func _initialize() -> void:
	# --script 的 _initialize 跑在 root 进树之前:测试里 add_child 到 root 的节点不算在树里(播音频/建 Tween 会报错),先等一帧
	await process_frame
	var total := 0
	var fails := 0
	for path in FILES:
		print(path.get_file())
		var scr := load(path) as GDScript
		if scr == null or not scr.can_instantiate():
			print("  ✗ 脚本加载失败(语法错误?)")
			total += 1
			fails += 1
			continue
		var t: RefCounted = scr.new()
		for m in t.get_method_list():
			if not String(m.name).begins_with("test_"):
				continue
			total += 1
			if t.call(m.name):
				print("  ✓ " + m.name)
			else:
				print("  ✗ " + m.name)
				fails += 1
	print("——— %d/%d 通过 ———" % [total - fails, total])
	quit(fails)
