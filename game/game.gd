extends Node
## Autoload "Game":游戏流程唯一单例(逻辑层保持可 new,不进这里)。
## 场景切换、当前关卡、存档、机器人 cue 转发都从这里走。
## 诺拉的笔记 = 七台仪器的说明(narrative/data/notebook.tres),全量常驻,不解锁。
## 小机剧情弧(按章节):第一二章 玩家说「请指导我」小机代解("guide");第三章小机故障("broken",所有 cue 变故障演出);
## 第四章修好、「请指导我」只回头看你("look");不在目录里的关(测试注入)不触发("off")。

var catalog: LevelCatalog
var notebook: NotebookCatalog
var save: SaveManager
var current: LevelDef = null
var menu_greeted := false   # 每次开游戏只在主菜单问候一次


func _ready() -> void:
	catalog = LevelCatalog.load_default()
	notebook = NotebookCatalog.load_default()
	save = SaveManager.open()


# ---- 关卡推进(全线性:第 i 关解锁条件 = 第 i-1 关已通) ----

func level_index(lv: LevelDef) -> int:
	return catalog.all_levels().find(lv)


func is_unlocked(idx: int) -> bool:
	if idx <= 0:
		return true
	var prev := catalog.all_levels()[idx - 1]
	return save.is_solved(prev.id)


## 第一个未通关的已解锁关(全通则最后一关)
func first_unsolved() -> LevelDef:
	var all := catalog.all_levels()
	for lv in all:
		if not save.is_solved(lv.id):
			return lv
	return all[-1]


func current_chapter() -> int:
	return catalog.chapter_of(current) if current != null else -1


static func robot_mode_for_chapter(ch: int) -> String:
	match ch:
		0, 1:
			return "guide"
		2:
			return "broken"
		3:
			return "look"
	return "off"


func robot_mode() -> String:
	return robot_mode_for_chapter(current_chapter())


func next_level() -> LevelDef:
	var idx := level_index(current)
	var all := catalog.all_levels()
	return all[idx + 1] if idx >= 0 and idx + 1 < all.size() else null


# ---- 场景切换 ----

func start_level(lv: LevelDef) -> void:
	current = lv
	var robot := get_node_or_null("/root/Robot")
	if robot != null:
		robot.broken = robot_mode() == "broken"   # 第三章整章故障
	if lv != null and lv.intro_dialogue != null and not lv.intro_dialogue.lines.is_empty():
		get_tree().change_scene_to_file("res://ui/story_scene.tscn")
	else:
		enter_board()


## 开场对话播完(或没有对话)后进棋盘;场景路径收口在这里
func enter_board() -> void:
	get_tree().change_scene_to_file("res://ui/level_scene.tscn")


func goto_menu() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func goto_select() -> void:
	get_tree().change_scene_to_file("res://ui/level_select.tscn")


func goto_credits() -> void:
	get_tree().change_scene_to_file("res://ui/credits_scene.tscn")


# ---- 关卡回报 ----

## fire_cue = false:小机代解时不庆祝、不鼓励(美术/策划要求「此时没有鼓励」)
func notify_solved(board_state: Dictionary, fire_cue: bool = true) -> void:
	if current == null:
		return
	save.mark_solved(current.id)
	save.set_board_state(current.id, board_state)
	save.save()
	if fire_cue:
		robot_cue(current.robot_cue_on_win)


func store_board(board_state: Dictionary) -> void:
	if current == null:
		return
	save.set_board_state(current.id, board_state)
	save.save()


## 机器人联动接口:Phase5 挂 Robot autoload;没有机器人时静默无事
func robot_cue(cue: String) -> void:
	if cue == "":
		return
	var robot := get_node_or_null("/root/Robot")
	if robot != null:
		robot.cue(cue)
