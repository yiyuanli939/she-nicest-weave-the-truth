extends TestBase
## 性能/功耗守门(Windows 笔记本导出版十分钟过热 + 啸叫的修法,别被无意改回去):
##   ① project.godot 三件套:帧率硬上限 60、低功耗模式(画面没变化不重绘)、显式 vsync;渲染器 = Compatibility
##      (纯 2D Control 游戏;Web 版本来就只能用它,视觉已验证;原来的 Forward+/d3d12 是脚手架默认);
##   ② 每帧脚本工作只许出现在白名单文件里(各自有 set_process 门控),_process 里不许 queue_redraw,
##      全项目不许循环 Tween(set_loops)/ SubViewport;
##   ③ 贴图导入全部开 mipmap(全局过滤器 LINEAR_WITH_MIPMAPS;4K 整页图在 1080p 上 2× 缩小采样);
##   ④ export_presets.cfg 有 Windows 预设,且和 Web 预设一样排除素材源目录(否则几十 MB 原画进包)。

const SCAN_DIRS: Array[String] = ["res://api", "res://board", "res://game", "res://narrative", "res://pattern", "res://ui"]
## 允许有 _process 的文件:Robot 轮询(无机器人模式关)/ 徽章跟随(没徽章关)/ 发呆计时(无机器人关)/ 维护面板刷新(关着关)
const PROCESS_ALLOWED: Array[String] = ["res://game/robot_link.gd", "res://board/wire_overlay.gd", "res://ui/level_scene.gd", "res://ui/robot_maint_ui.gd"]


func test_project_settings_cap_fps_and_use_compatibility() -> bool:
	var text := _strip_comments(FileAccess.get_file_as_string("res://project.godot"), ";")
	var ok := true
	for want: String in ["run/max_fps=60", "run/low_processor_mode=true", "window/vsync/vsync_mode=1",
			"renderer/rendering_method=\"gl_compatibility\"", "renderer/rendering_method.mobile=\"gl_compatibility\""]:
		ok = check(text.contains("\n%s\n" % want), "project.godot 含整行 %s" % want) and ok
	ok = check(text.contains("\"GL Compatibility\""), "features 标签 = GL Compatibility") and ok
	for bad: String in ["d3d12", "\"Forward Plus\""]:
		ok = check(not text.contains(bad), "project.godot 不再含 %s" % bad) and ok
	ok = check(int(ProjectSettings.get_setting("application/run/max_fps", 0)) == 60 and Engine.max_fps == 60, "生效 max_fps = 60") and ok
	ok = check(bool(ProjectSettings.get_setting("application/run/low_processor_mode", false)) and OS.low_processor_usage_mode, "生效低功耗模式") and ok
	ok = check(int(ProjectSettings.get_setting("display/window/vsync/vsync_mode", 0)) == 1, "生效 vsync = Enabled") and ok
	return check(String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "gl_compatibility", "生效渲染器 = gl_compatibility") and ok


func test_per_frame_work_is_whitelisted() -> bool:
	var ok := true
	var scanned := 0
	for f in _source_files():
		scanned += 1
		var code := _strip_comments(FileAccess.get_file_as_string(f), "#")
		if code.contains("func _process(") or code.contains("func _physics_process("):
			ok = check(PROCESS_ALLOWED.has(f), "%s 有 _process:每帧工作只许在白名单文件里(要加请先做 set_process 门控并更新 PROCESS_ALLOWED)" % f) and ok
			ok = check(not _process_body(code).contains("queue_redraw("), "%s 的 _process 里不许 queue_redraw(每帧强制重绘,低功耗模式白开)" % f) and ok
		ok = check(not code.contains("set_loops("), "%s 不许循环 Tween(set_loops)" % f) and ok
		ok = check(not code.contains("SubViewport"), "%s 不许 SubViewport(独立每帧渲染)" % f) and ok
	return check(scanned >= 20, "应扫到 20+ 个脚本(得 %d,太少说明目录不对)" % scanned) and ok


func test_art_imports_have_mipmaps() -> bool:
	var ok := true
	var n := 0
	for f in _files_under("res://assets/art", "import"):
		var t := FileAccess.get_file_as_string(f)
		if not t.contains("importer=\"texture\""):
			continue
		n += 1
		ok = check(t.contains("mipmaps/generate=true"), "%s 必须开 mipmap(全局过滤 LINEAR_WITH_MIPMAPS,缩小显示才不抖、少读 4× 纹理)" % f) and ok
	return check(n >= 30, "应扫到 30+ 张贴图导入(得 %d)" % n) and ok


func test_windows_export_preset_matches_web() -> bool:
	var t := FileAccess.get_file_as_string("res://export_presets.cfg")
	var web := _preset_block(t, "Web")
	var win := _preset_block(t, "Windows Desktop")
	if not check(web != "" and win != "", "export_presets.cfg 有 Web 与 Windows Desktop 两个预设"):
		return false
	var re := RegEx.create_from_string("exclude_filter=\"([^\"]*)\"")
	var mw := re.search(web)
	var mn := re.search(win)
	var ok := check(mw != null and mn != null and mw.get_string(1) == mn.get_string(1), "Windows 预设的 exclude_filter 与 Web 逐字一致")
	ok = check(mn != null and mn.get_string(1).contains("美术/*") and mn.get_string(1).contains("tests/*"), "排除素材源目录与测试") and ok
	return check(win.contains("export_path=\"build/windows/"), "导出到 build/windows/(build/ 已 .gitignore + .gdignore)") and ok


# ---- helpers ----

## 去掉注释行与行尾注释(marker = "#" 脚本 / ";" project.godot),保留换行以便整行匹配
static func _strip_comments(src: String, marker: String) -> String:
	var out := PackedStringArray()
	for line in src.split("\n"):
		out.append(line.get_slice(marker, 0).strip_edges(false, true))
	return "\n" + "\n".join(out) + "\n"


## _process 函数体:从 func _process( 到下一个顶层 func
static func _process_body(code: String) -> String:
	var start := code.find("func _process(")
	if start < 0:
		return ""
	var end := code.find("\nfunc ", start + 1)
	var end2 := code.find("\nstatic func ", start + 1)
	if end < 0 or (end2 >= 0 and end2 < end):
		end = end2
	return code.substr(start, (end - start) if end >= 0 else -1)


static func _preset_block(cfg: String, preset_name: String) -> String:
	for chunk in cfg.split("\n[preset."):
		if chunk.contains("name=\"%s\"" % preset_name):
			return chunk
	return ""


func _source_files() -> Array[String]:
	var out: Array[String] = []
	for d in SCAN_DIRS:
		out.append_array(_files_under(d, "gd"))
	return out


static func _files_under(root_dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [root_dir]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(d):
			stack.append(d.path_join(sub))
		for f in DirAccess.get_files_at(d):
			if f.get_extension() == ext:
				out.append(d.path_join(f))
	return out
