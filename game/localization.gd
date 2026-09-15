extends Node
## 中英文语言状态。底层翻译由 Godot TranslationServer + localization/game.en.po 提供。
## 中文原文同时作为稳定的 msgid；美术资源键、规则 id 与存档结构不随语言变化。

signal locale_changed(locale: String)

const ZH_CN := "zh_CN"
const EN := "en"

var locale := ZH_CN


func _ready() -> void:
	var game := get_node_or_null("/root/Game")
	var saved := ZH_CN
	if game != null and game.save != null:
		saved = String(game.save.settings.get("language", ZH_CN))
	set_locale(saved, false)


func set_locale(value: String, persist: bool = true) -> void:
	locale = normalize_locale(value)
	TranslationServer.set_locale(locale)
	if persist:
		var game := get_node_or_null("/root/Game")
		if game != null and game.save != null:
			game.save.settings["language"] = locale
			game.save.save()
	locale_changed.emit(locale)


func toggle() -> void:
	set_locale(ZH_CN if locale == EN else EN)


func is_english() -> bool:
	return locale == EN


func switch_label() -> String:
	return "中文" if is_english() else "EN"


static func normalize_locale(value: String) -> String:
	return EN if value.to_lower().begins_with("en") else ZH_CN
