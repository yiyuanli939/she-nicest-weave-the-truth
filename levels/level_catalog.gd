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
