class_name StoryArt
extends RefCounted
## 故事界面美术登记表:中文角色名 / 表情 / 场景名 → assets/art/story/ 下的 PNG。
## 美术新加一张图:按 char_<角色id>_<表情id>.png / scene_<场景id>.png 命名放进目录,再在下面表里补一行。
## 缺图时返回 null 并 push_warning,界面隐藏对应元素,不崩。

const DIR := "res://assets/art/story/"

## 角色:中文名 → {id: 文件名用的 id, full_name: 对话区显示的全名}
const CHARACTERS: Dictionary = {
	"诺拉": {id = "nora", full_name = "诺拉·拉弗蒂"},
	"莉娅": {id = "lia", full_name = "莉娅"},
	"亚瑟": {id = "arthur", full_name = "亚瑟·威客利夫"},
}
const EXPRESSIONS: Dictionary = {"默认": "default", "苦恼": "worried", "严肃": "serious", "惊讶": "surprised"}
const SCENES: Dictionary = {"工坊": "workshop", "宿舍": "dorm", "街景": "street"}
const NORA := "诺拉"


## 发言人是否主角诺拉(显示名可以是 "诺拉" 或 "诺拉·拉弗蒂")
static func is_nora(speaker: String) -> bool:
	return speaker.begins_with(NORA)


## 显示名 → 登记表里的角色中文名("" = 不是登记角色,如占位的阿梭/档案员)
static func character_of(speaker: String) -> String:
	for name: String in CHARACTERS:
		if speaker.begins_with(name):
			return name
	return ""


## 对话区显示的名字:登记角色写短名时补全名("莉娅" → "莉娅","诺拉" → "诺拉·拉弗蒂"),其余原样
static func display_name(speaker: String) -> String:
	if CHARACTERS.has(speaker):
		return CHARACTERS[speaker].full_name
	return speaker


static func portrait_path(char_name: String, expr: String) -> String:
	if not CHARACTERS.has(char_name) or not EXPRESSIONS.has(expr):
		return ""
	return DIR + "char_%s_%s.png" % [CHARACTERS[char_name].id, EXPRESSIONS[expr]]


static func mask_path(char_name: String) -> String:
	if not CHARACTERS.has(char_name):
		return ""
	return DIR + "char_%s_mask.png" % CHARACTERS[char_name].id


static func scene_path(scene_name: String) -> String:
	if not SCENES.has(scene_name):
		return ""
	return DIR + "scene_%s.png" % SCENES[scene_name]


static func portrait(char_name: String, expr: String) -> Texture2D:
	return _load(portrait_path(char_name, expr), "立绘 %s(%s)" % [char_name, expr])


static func mask(char_name: String) -> Texture2D:
	return _load(mask_path(char_name), "遮罩 %s" % char_name)


static func scene(scene_name: String) -> Texture2D:
	return _load(scene_path(scene_name), "场景 %s" % scene_name)


static func _load(path: String, what: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("StoryArt: 缺图 %s(%s)" % [what, path])
		return null
	return load(path) as Texture2D
