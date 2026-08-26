class_name NotebookCatalog
extends Resource
## 全部笔记本条目的登记表(顺序即显示顺序)。

@export var entries: Array[NotebookEntry] = []


static func load_default() -> NotebookCatalog:
	return load("res://narrative/data/notebook.tres")


func entry(entry_id: StringName) -> NotebookEntry:
	for e in entries:
		if e.id == entry_id:
			return e
	return null
