extends SceneTree
## 把策划的剧情表(xlsx 先经 tools/xlsx_to_csv.py 转成 CSV)灌进各关 .tres 的对话字段。
##   python3 tools/xlsx_to_csv.py
##   godot --headless --path . --script res://tools/import_dialogue.gd [-- 路径]
## 默认读 res://information/dialogue.csv。表头(列顺序随意,按名字识别,支持策划表别名):
##   关卡id|关卡, 发言人, 场景, 左侧人物|左位人物, 左侧表情|左位人物表情, 诺拉表情|主角表情, 台词|语句, 小机动作(可缺)
## 表头行之前的行(策划的注意事项)自动跳过。
## 关卡可写 l01…l16,也可写「章-节」(如 1-1;映射按关卡目录章节大小);OUTRO_EPISODES(4-3)写入
## outro_dialogue(通关后播,注意事项②),其余写入 intro_dialogue;表里出现的关两个字段都会重写(缺者清空)。
## 场景/人物/表情写中文名(合法值见 narrative/story_art.gd);左侧人物可写登记短名、全名或「无」;
## 表情空 = 默认(注意事项①);台词里可含逗号、换行(用引号包住)。
## 导入是原子的:只要有任何错误(坏行/找不到关卡/某段首句没场景),一关都不写,改完重跑。
## parse_csv() 是纯函数(不碰文件),tests/test_dialogue_import.gd 直接测它。

const DEFAULT_PATH := "res://information/dialogue.csv"
## 规范列名 → 接受的表头写法(第一个是老格式,后面是策划正式表的写法)
const COL_ALIASES: Dictionary = {
	"关卡id": ["关卡id", "关卡"],
	"发言人": ["发言人"],
	"场景": ["场景"],
	"左侧人物": ["左侧人物", "左位人物"],
	"左侧表情": ["左侧表情", "左位人物表情"],
	"诺拉表情": ["诺拉表情", "主角表情"],
	"台词": ["台词", "语句"],
	"小机动作": ["小机动作"],
}
const REQUIRED: Array = ["关卡id", "发言人", "台词"]
## 表头注意事项②:这些段落在通关后播(→ outro_dialogue),其余进关前播(→ intro_dialogue)
const OUTRO_EPISODES: Array = ["4-3"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else DEFAULT_PATH
	if not FileAccess.file_exists(path):
		push_error("找不到 CSV: " + path)
		quit(1)
		return
	var result := parse_csv(FileAccess.get_file_as_string(path), episode_map())
	for level_id: String in result.levels:
		if _level_path(level_id) == "":
			result.errors.append("找不到关卡 %s 的 .tres" % level_id)
	if not result.errors.is_empty():
		for e: String in result.errors:
			push_error(e)
		print("导入中止:%d 条错误,一关都没写(改完表重跑即可)" % result.errors.size())
		quit(1)
		return
	var n := 0
	for level_id: String in result.levels:
		var lv_path := _level_path(level_id)
		var lv: LevelDef = load(lv_path)
		lv.intro_dialogue = result.levels[level_id].intro
		lv.outro_dialogue = result.levels[level_id].outro
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


## 「章-节」→ 关卡 id("1-1" → "l01"),映射按关卡目录的章节大小生成
static func episode_map() -> Dictionary:
	var out := {}
	var cat := LevelCatalog.load_default()
	for ci in cat.chapters.size():
		var levels: Array = cat.chapters[ci].levels
		for li in levels.size():
			out["%d-%d" % [ci + 1, li + 1]] = String((levels[li] as LevelDef).id)
	return out


## 返回 {levels: {关卡id: {intro: DialogueRes|null, outro: DialogueRes|null}}, errors: [String]}。
## 非法的场景/人物/表情整行跳过并记错;ep_map 由 episode_map() 生成(测试注入假映射保持纯函数)。
static func parse_csv(text: String, ep_map: Dictionary = {}) -> Dictionary:
	var out := {levels = {}, errors = []}
	var rows := split_rows(text)
	# 表头可能不在第一行(策划表第一行是注意事项):往下找同时含「发言人」和「台词/语句」的行
	var header_at := -1
	var col := {}
	for r in rows.size():
		col = _resolve_columns(rows[r])
		if col["发言人"] >= 0 and col["台词"] >= 0:
			header_at = r
			break
	if header_at < 0:
		out.errors.append("找不到表头(需要「发言人」与「台词/语句」列)")
		return out
	for name in REQUIRED:
		if col[name] < 0:
			out.errors.append("表头缺少必需列:" + name)
	if not out.errors.is_empty():
		return out
	for r in range(header_at + 1, rows.size()):
		var row: Array = rows[r]
		if row.is_empty() or "".join(row).strip_edges() == "":
			continue
		var get := func(name: String) -> String:
			var i: int = col[name]
			return row[i].strip_edges() if i >= 0 and i < row.size() else ""
		var raw_level: String = get.call("关卡id")
		var level_id: String = ep_map.get(raw_level, raw_level)
		var is_outro: bool = OUTRO_EPISODES.has(raw_level)
		var line := DialogueLine.new()
		line.speaker = get.call("发言人")
		line.text = get.call("台词")
		line.scene = get.call("场景")
		line.left_char = _normalize_left(get.call("左侧人物"))
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
			out.levels[level_id] = {intro = null, outro = null}
		var slot := "outro" if is_outro else "intro"
		if out.levels[level_id][slot] == null:
			out.levels[level_id][slot] = DialogueRes.new()
		(out.levels[level_id][slot] as DialogueRes).lines.append(line)
	# 「场景空 = 沿用上一句」只在一段之内成立:每段首句必须给场景,
	# 否则该段插图整段空白;策划只在全表第一行写场景是常见笔误,这里直接报错。
	for level_id: String in out.levels:
		for slot in ["intro", "outro"]:
			var dlg: DialogueRes = out.levels[level_id][slot]
			if dlg != null and not dlg.lines.is_empty() and dlg.lines[0].scene == "":
				out.errors.append("关卡 %s 的%s第一句没有场景(「空=沿用上一句」不跨段)"
						% [level_id, "通关后剧情" if slot == "outro" else ""])
	return out


## 左侧人物:「无」= 左侧无人;全名(莉娅·科尔宾)归一到登记短名;未登记的原样留给 _validate 报错
static func _normalize_left(name: String) -> String:
	if name == "" or name == "无":
		return ""
	var short := StoryArt.character_of(name)
	return short if short != "" else name


static func _validate(line: DialogueLine, level_id: String) -> String:
	if not level_id.is_valid_identifier() or not level_id.begins_with("l"):
		return "关卡不合法(既不是 l## 也不是目录里的 章-节):" + level_id
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


## 表头行 → {规范列名: 列号(-1 = 没有)};别名任取其一
static func _resolve_columns(row: Array) -> Dictionary:
	var header: Array = row.map(func(h: String) -> String: return h.strip_edges())
	var col := {}
	for name: String in COL_ALIASES:
		col[name] = -1
		for alias: String in COL_ALIASES[name]:
			var i: int = header.find(alias)
			if i >= 0:
				col[name] = i
				break
	return col


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
