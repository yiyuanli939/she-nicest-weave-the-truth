extends SceneTree
## 把美术/策划的 Excel 表(另存为 CSV)灌进各关 .tres 的 intro_dialogue。
##   godot --headless --path . --script res://tools/import_dialogue.gd [-- 路径]
## 默认读 res://information/dialogue.csv。表头(列顺序随意,按名字识别):
##   关卡id, 发言人, 场景, 左侧人物, 左侧表情, 诺拉表情, 台词, 小机动作
## 关卡id = l01…l15;场景/人物/表情写中文名(合法值见 narrative/story_art.gd);
## 左侧人物可空;左侧表情/诺拉表情空 = 默认;小机动作可空。台词里可含逗号、换行(用引号包住,Excel 另存 CSV 会自动做)。
## 同一关的行按出现顺序成为该关对话;表里没出现的关卡不动。
## 导入是原子的:只要有任何错误(坏行/找不到关卡/某关首句没场景),一关都不写,改完重跑。
## parse_csv() 是纯函数(不碰文件),tests/test_dialogue_import.gd 直接测它。

const DEFAULT_PATH := "res://information/dialogue.csv"
const COLS := ["关卡id", "发言人", "场景", "左侧人物", "左侧表情", "诺拉表情", "台词", "小机动作"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else DEFAULT_PATH
	if not FileAccess.file_exists(path):
		push_error("找不到 CSV: " + path)
		quit(1)
		return
	var result := parse_csv(FileAccess.get_file_as_string(path))
	for level_id: String in result.levels:
		if _level_path(level_id) == "":
			result.errors.append("找不到关卡 %s 的 .tres" % level_id)
	if not result.errors.is_empty():
		for e: String in result.errors:
			push_error(e)
		print("导入中止:%d 条错误,一关都没写(改完 CSV 重跑即可)" % result.errors.size())
		quit(1)
		return
	var n := 0
	for level_id: String in result.levels:
		var lv_path := _level_path(level_id)
		var lv: LevelDef = load(lv_path)
		lv.intro_dialogue = result.levels[level_id]
		var err := ResourceSaver.save(lv, lv_path)
		assert(err == OK, "保存失败 %s: %d" % [lv_path, err])
		n += 1
	print("导入完毕:%d 关的对话已更新,0 条错误" % n)
	quit(0)


static func _level_path(level_id: String) -> String:
	for f in DirAccess.get_files_at("res://levels/data"):
		if f.begins_with(level_id + "_") and f.ends_with(".tres"):
			return "res://levels/data/" + f
	return ""


## 返回 {levels: {关卡id: DialogueRes}, errors: [String]}。非法的场景/人物/表情整行跳过并记错。
static func parse_csv(text: String) -> Dictionary:
	var out := {levels = {}, errors = []}
	var rows := split_rows(text)
	if rows.is_empty():
		out.errors.append("CSV 为空")
		return out
	var header: Array = rows[0].map(func(h: String) -> String: return h.strip_edges())
	var col := {}
	for name in COLS:
		col[name] = header.find(name)
		if col[name] < 0 and name in ["关卡id", "发言人", "台词"]:
			out.errors.append("表头缺少必需列:" + name)
	if not out.errors.is_empty():
		return out
	for r in range(1, rows.size()):
		var row: Array = rows[r]
		if row.is_empty() or "".join(row).strip_edges() == "":
			continue
		var get := func(name: String) -> String:
			var i: int = col[name]
			return row[i].strip_edges() if i >= 0 and i < row.size() else ""
		var level_id: String = get.call("关卡id")
		var line := DialogueLine.new()
		line.speaker = get.call("发言人")
		line.text = get.call("台词")
		line.scene = get.call("场景")
		line.left_char = get.call("左侧人物")
		line.left_expr = get.call("左侧表情")
		line.nora_expr = get.call("诺拉表情")
		line.robot_cue = get.call("小机动作")
		if line.left_expr == "":
			line.left_expr = "默认"
		if line.nora_expr == "":
			line.nora_expr = "默认"
		var bad := _validate(line, level_id)
		if bad != "":
			out.errors.append("第 %d 行:%s" % [r + 1, bad])
			continue
		if not out.levels.has(level_id):
			out.levels[level_id] = DialogueRes.new()
		(out.levels[level_id] as DialogueRes).lines.append(line)
	# 「场景空 = 沿用上一句」只在一关之内成立(每关独立 DialogueRes):首句必须给场景,
	# 否则该关插图整段空白;策划在 Excel 里只写全表第一行场景是常见笔误,这里直接报错。
	for level_id: String in out.levels:
		var lines := (out.levels[level_id] as DialogueRes).lines
		if not lines.is_empty() and lines[0].scene == "":
			out.errors.append("关卡 %s 的第一句没有场景(「空=沿用上一句」不跨关)" % level_id)
	return out


static func _validate(line: DialogueLine, level_id: String) -> String:
	if not level_id.is_valid_identifier() or not level_id.begins_with("l"):
		return "关卡id 不合法:" + level_id
	if line.speaker == "":
		return "发言人为空"
	if line.text == "":
		return "台词为空"
	if line.scene != "" and not StoryArt.SCENES.has(line.scene):
		return "未知场景:" + line.scene
	if line.left_char != "" and (not StoryArt.CHARACTERS.has(line.left_char) or StoryArt.is_nora(line.left_char)):
		return "左侧人物不合法(诺拉恒在右侧):" + line.left_char
	if not StoryArt.EXPRESSIONS.has(line.left_expr):
		return "未知左侧表情:" + line.left_expr
	if not StoryArt.EXPRESSIONS.has(line.nora_expr):
		return "未知诺拉表情:" + line.nora_expr
	return ""


## RFC4180 风格 CSV:逗号分隔,引号包住的字段里可有逗号/换行/双写引号;兼容 \r\n。
static func split_rows(text: String) -> Array:
	var rows: Array = []
	var row: Array = []
	var field := ""
	var in_quotes := false
	var i := 0
	var n := text.length()
	if n > 0 and text.unicode_at(0) == 0xFEFF:   # Excel 的 UTF-8 BOM
		i = 1
	while i < n:
		var c := text[i]
		if in_quotes:
			if c == '"':
				if i + 1 < n and text[i + 1] == '"':
					field += '"'
					i += 1
				else:
					in_quotes = false
			else:
				field += c
		else:
			match c:
				'"':
					in_quotes = true
				',':
					row.append(field)
					field = ""
				'\r':
					pass
				'\n':
					row.append(field)
					rows.append(row)
					row = []
					field = ""
				_:
					field += c
		i += 1
	if field != "" or not row.is_empty():
		row.append(field)
		rows.append(row)
	return rows
