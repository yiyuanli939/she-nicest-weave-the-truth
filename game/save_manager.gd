class_name SaveManager
extends RefCounted
## 存档:user://save.json。结构:
## { layout: 关卡编排版本, solved: {level_id: true}, boards: {level_id: session.save_state()},
##   steps: {操作名: true}(关内操作指引里做过一次的操作,见 StepGuide),
##   settings: {music_volume: 0..1, sfx_volume: 0..1, fullscreen: bool, robot_enabled: bool, robot_turn: "right"|"left", robot_stationary: bool, language: "zh"|"en"} }
## settings 是设备/偏好设置(标题页设置模块 SettingsPanel + 小机维护面板写),「重置进度」wipe() 不清它。
## layout:关卡 id 整体重排后(2026-09-02 第一章加第三纹,l03 起后移一位),旧档里的 boards 是别的题目的棋盘,
## load_state 会把旧题的线轴/目标织机整套换进来 —— 读到旧版本就丢弃 boards,只保留 solved(顶多错位一关,不伤进度)。

const PATH := "user://save.json"
const LAYOUT_VERSION := 2   # 1 = 15 关(2026-08);2 = 16 关(第一章加第三纹、第二章 2-2/2-3 对调、仪器按关上架)

var solved: Dictionary = {}
var boards: Dictionary = {}
var steps: Dictionary = {}
var settings: Dictionary = {}


static func open() -> SaveManager:
	var sm := SaveManager.new()
	if FileAccess.file_exists(PATH):
		var txt := FileAccess.get_file_as_string(PATH)
		var d: Variant = JSON.parse_string(txt)
		if d is Dictionary:
			sm.solved = d.get("solved", {})
			sm.steps = d.get("steps", {})
			sm.settings = d.get("settings", {})
			if int(d.get("layout", 1)) == LAYOUT_VERSION:   # JSON 数字读回是 float
				sm.boards = d.get("boards", {})
	return sm


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败: " + PATH)
		return
	f.store_string(JSON.stringify({layout = LAYOUT_VERSION, solved = solved, boards = boards, steps = steps, settings = settings}))


func is_solved(level_id: StringName) -> bool:
	return solved.get(String(level_id), false)


func mark_solved(level_id: StringName) -> void:
	solved[String(level_id)] = true


func board_state(level_id: StringName) -> Dictionary:
	return boards.get(String(level_id), {})


func set_board_state(level_id: StringName, state: Dictionary) -> void:
	boards[String(level_id)] = state


func is_step_done(step: StringName) -> bool:
	return steps.get(String(step), false)


## 记下玩家做过某个操作;首次记下返回 true(调用方据此决定要不要落盘)
func mark_step_done(step: StringName) -> bool:
	if steps.get(String(step), false):
		return false
	steps[String(step)] = true
	return true


## 重置进度:清通关记录、棋盘与操作指引记忆,保留 settings
func wipe() -> void:
	solved = {}
	boards = {}
	steps = {}
	save()
