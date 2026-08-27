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
]


func _initialize() -> void:
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
