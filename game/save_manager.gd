class_name SaveManager
extends RefCounted
## 存档:user://save.json。结构:
## { solved: {level_id: true}, boards: {level_id: session.save_state()}, notebook: [entry_id] }

const PATH := "user://save.json"

var solved: Dictionary = {}
var boards: Dictionary = {}
var notebook: Array = []


static func open() -> SaveManager:
	var sm := SaveManager.new()
	if FileAccess.file_exists(PATH):
		var txt := FileAccess.get_file_as_string(PATH)
		var d: Variant = JSON.parse_string(txt)
		if d is Dictionary:
			sm.solved = d.get("solved", {})
			sm.boards = d.get("boards", {})
			sm.notebook = d.get("notebook", [])
	return sm


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败: " + PATH)
		return
	f.store_string(JSON.stringify({solved = solved, boards = boards, notebook = notebook}))


func is_solved(level_id: StringName) -> bool:
	return solved.get(String(level_id), false)


func mark_solved(level_id: StringName) -> void:
	solved[String(level_id)] = true


func board_state(level_id: StringName) -> Dictionary:
	return boards.get(String(level_id), {})


func set_board_state(level_id: StringName, state: Dictionary) -> void:
	boards[String(level_id)] = state


func unlock_notebook(entry_id: StringName) -> bool:
	if notebook.has(String(entry_id)):
		return false
	notebook.append(String(entry_id))
	return true


func wipe() -> void:
	solved = {}
	boards = {}
	notebook = []
	save()
