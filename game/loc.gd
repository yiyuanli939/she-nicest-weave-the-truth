class_name Loc
extends RefCounted
## 语言(2026-09-03 用户要求「所有地方都翻译的英文版,在设置里改语言」):
## 机制 = Godot TranslationServer + locale/ui.csv(列 keys,zh,en,键就是代码里的中文原串)。
## Control 的 text / tooltip 默认自动查表(auto_translate),所以绝大多数 `label.text = "继续"` 一行不用改,
## `.text` 属性仍是中文键(测试照旧按中文找按钮;要断言显示文本用 node.atr(node.text));
## 只有拼接出来的串要改成整串键或 tr(),台词走 DialogueLine.text_en(line_text)。
## 图:烧了中文的美术图按 project.godot 的 translation_remaps 换成 <名字>.en.png(load 时自动;localized_path 给代码/测试查)。
## 启动:Game._ready 按 settings.language 设 locale(默认 zh;不设的话 TranslationServer 会取系统语言);
## 切换:SettingsPanel「语言」行 → Game.set_language → 全树 NOTIFICATION_TRANSLATION_CHANGED + 已加载的换图资源原地重载。
## 英文文案只许 ASCII + “ ” ‘ ’ – — …(站酷小薇体没有重音字母,tests/test_locale.gd 盯)。

const DEFAULT := "zh"
const LANGUAGES: Array[String] = ["zh", "en"]
const CHARS_PER_SEC: Dictionary = {"zh": 40.0, "en": 90.0}   # 对话打字机速度:英文一句字符数约两倍
const REMAPS_SETTING := "internationalization/locale/translation_remaps"


static func normalize(v: Variant) -> String:
	return "en" if str(v) == "en" else DEFAULT


static func next(lang: String) -> String:
	return "en" if normalize(lang) == DEFAULT else DEFAULT


static func current() -> String:
	return normalize(TranslationServer.get_locale().substr(0, 2))


static func is_en() -> bool:
	return current() == "en"


static func apply(lang: String) -> void:
	TranslationServer.set_locale(normalize(lang))


## 某张图在指定语言下实际加载的路径(按 translation_remaps;没有该语言的备选或文件不存在就是原路径)
static func localized_path(path: String, lang: String = current()) -> String:
	var remaps: Dictionary = ProjectSettings.get_setting(REMAPS_SETTING, {})
	if not remaps.has(path):
		return path
	for alt in remaps[path]:
		var s := String(alt)
		var i := s.rfind(":")
		if i > 0 and s.substr(i + 1) == normalize(lang) and ResourceLoader.exists(s.substr(0, i)):
			return s.substr(0, i)
	return path


static func chars_per_sec(lang: String = current()) -> float:
	return float(CHARS_PER_SEC.get(normalize(lang), CHARS_PER_SEC[DEFAULT]))


## 台词:英文模式且译文非空才用英文,否则中文(译文没填的句子不会变空白)
static func line_text(line: DialogueLine, lang: String = current()) -> String:
	if normalize(lang) == "en" and line.text_en != "":
		return line.text_en
	return line.text
