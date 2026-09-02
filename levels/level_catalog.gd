class_name LevelCatalog
extends Resource
## 全部章节。关卡线性推进:上一关通了下一关才开。

@export var chapters: Array[ChapterDef] = []


static func load_default() -> LevelCatalog:
	return load("res://levels/data/catalog.tres")


func all_levels() -> Array[LevelDef]:
	var out: Array[LevelDef] = []
	for c in chapters:
		out.append_array(c.levels)
	return out


func find(level_id: StringName) -> LevelDef:
	for l in all_levels():
		if l.id == level_id:
			return l
	return null


## lv 属于第几章(0 起);不在目录里(如测试注入的关)返回 -1
func chapter_of(lv: LevelDef) -> int:
	for i in chapters.size():
		if chapters[i].levels.has(lv):
			return i
	return -1


## 本关新上架的仪器(前一关 allowed_rules 里没有的);不在目录里的关返回空
func debut_rules(lv: LevelDef) -> Array[StringName]:
	var out: Array[StringName] = []
	var all := all_levels()
	var idx := all.find(lv)
	if idx < 0:
		return out
	var prev: Array[StringName] = []
	if idx > 0:
		prev = all[idx - 1].allowed_rules
	for r in lv.allowed_rules:
		if not prev.has(r):
			out.append(r)
	return out
