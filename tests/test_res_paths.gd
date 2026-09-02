extends TestBase
## Windows/导出包可移植性:res:// 引用与磁盘文件名大小写必须完全一致。
## macOS/Windows 的文件系统大小写不敏感 —— 开发期把大小写写错不报错,但导出 PCK(以及 Linux)
## 严格区分大小写,一到导出版就 load 失败。这里把代码/场景/资源里的 res:// 字面量逐段
## 对着 DirAccess 目录清单核对精确大小写;动态拼接的路径(StoryArt 立绘、Bgm 槽位)单独覆盖。
## 注释里引用的「根本不存在的示例路径」放过(只抓"存在但大小写不符"的真隐患)。

const SCAN_DIRS: Array[String] = ["res://api", "res://board", "res://game", "res://levels",
	"res://logic", "res://narrative", "res://pattern", "res://tests", "res://theme",
	"res://tools", "res://ui"]


func test_literal_res_paths_exact_case() -> bool:
	var regex := RegEx.new()
	regex.compile("res://[A-Za-z0-9_\\-./]+")
	var ok := true
	var seen := {}
	var files := _source_files()
	files.append("res://project.godot")
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		for m in regex.search_all(text):
			var p := m.get_string()
			while p.ends_with(".") or p.ends_with("/"):
				p = p.substr(0, p.length() - 1)
			if p.get_extension() == "" or seen.has(p):
				continue   # 目录引用 / 在 % 处截断的动态拼接:跳过
			seen[p] = true
			var bad := _case_check(p)
			if bad != "":
				ok = check(false, "%s 引用 %s:%s" % [f.get_file(), p, bad]) and ok
	return check(seen.size() > 30, "应扫到几十条字面量路径(得 %d,太少说明正则/目录不对)" % seen.size()) and ok


func test_dynamic_art_and_music_paths_exact_case() -> bool:
	var ok := true
	for who: String in StoryArt.CHARACTERS:
		for expr: String in StoryArt.EXPRESSIONS:
			ok = _check_generated(StoryArt.portrait_path(who, expr)) and ok
		ok = _check_generated(StoryArt.mask_path(who)) and ok
	for sc: String in StoryArt.SCENES:
		ok = _check_generated(StoryArt.scene_path(sc)) and ok
	var bgm := load("res://game/bgm.gd") as GDScript
	for slot in bgm.TRACKS:
		var p: String = bgm.TRACKS[slot]
		if p != "":
			ok = check(_case_check(p) == "", "BGM %s → %s 大小写不符" % [slot, p]) and ok
	var sfx := load("res://game/sfx.gd") as GDScript
	for slot in sfx.CLIPS:
		var p: String = sfx.CLIPS[slot]
		if p != "":
			ok = check(_case_check(p) == "", "音效 %s → %s 大小写不符" % [slot, p]) and ok
	for e in NotebookCatalog.load_default().entries:
		ok = check(_case_check(e.image) == "", "笔记整页图 %s 大小写不符" % e.image) and ok
	return ok


## 生成路径允许整个文件不存在(没画的表情组合界面自己回退),但存在时大小写必须精确
func _check_generated(p: String) -> bool:
	if p == "":
		return true
	var bad := _case_check(p)
	return check(bad == "", "%s:%s" % [p, bad])


## "" = 通过(或文件根本不存在 —— 注释示例);否则返回大小写问题描述
static func _case_check(p: String) -> String:
	var parts := p.trim_prefix("res://").split("/")
	var cur := "res://"
	for i in parts.size():
		var part := parts[i]
		var names := DirAccess.get_files_at(cur) if i == parts.size() - 1 else DirAccess.get_directories_at(cur)
		if part in names:
			cur = cur.path_join(part)
			continue
		for n in names:
			if n.to_lower() == part.to_lower():
				return "第 %d 段大小写不符(写的 %s,磁盘是 %s)" % [i + 1, part, n]
		return ""   # 精确名和不敏感名都没有:文件不存在,不算大小写问题
	return ""


func _source_files() -> Array[String]:
	var out: Array[String] = []
	var stack := SCAN_DIRS.duplicate()
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(d):
			stack.append(d.path_join(sub))
		for f in DirAccess.get_files_at(d):
			if f.get_extension() in ["gd", "tres", "tscn"]:
				out.append(d.path_join(f))
	return out
