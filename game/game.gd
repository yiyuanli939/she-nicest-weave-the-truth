extends Node
## Autoload "Game":游戏流程唯一单例(逻辑层保持可 new,不进这里)。
## 场景切换、当前关卡、存档、机器人 cue 转发都从这里走。
## 诺拉的笔记 = 七台仪器的说明(narrative/data/notebook.tres),关内按本关 allowed_rules 过滤显示。
## 小机剧情弧(按关卡序):3-1(l10)通关瞬间坏掉 —— 坏掉前玩家说「请指导我」小机代解("guide"),
## 坏掉后整段故障("broken",所有 cue 变故障演出);结局(l15 通关后 4-3 剧情播完,感谢游玩黑屏)才修好。
## 不在目录里的关(测试注入)不触发("off")。

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


## 小机坏掉的分界关:这一关(3-1)通关瞬间坏掉(notify_solved 里置 Robot.broken)
const BREAK_LEVEL := &"l10"


## 纯查表(测试用):坏掉分界关(含当关)之前代解,之后故障
static func robot_mode_at(idx: int, break_idx: int) -> String:
	if idx < 0:
		return "off"
	return "guide" if idx <= break_idx else "broken"


func robot_mode() -> String:
	var idx := level_index(current) if current != null else -1
	return robot_mode_at(idx, level_index(catalog.find(BREAK_LEVEL)))


func next_level() -> LevelDef:
	var idx := level_index(current)
	var all := catalog.all_levels()
	return all[idx + 1] if idx >= 0 and idx + 1 < all.size() else null


# ---- 场景切换 ----

func start_level(lv: LevelDef) -> void:
	ending_pending = false
	current = lv
	var robot := get_node_or_null("/root/Robot")
	if robot != null:
		robot.broken = robot_mode() == "broken"   # 3-2 起整段故障(重玩按关卡序回放)
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


# ---- 结局(表头注意事项②:4-3 在通关后播,播完感谢游玩黑屏 → 开发者信息) ----

var ending_pending := false        # StoryScene 据此播 outro_dialogue 而非 intro_dialogue
var credits_fade_pending := false  # 开发者信息页从黑淡入一次(「淡出到开发者信息界面」)


## l15 通关后点「继续」:全屏播 current.outro_dialogue
func play_ending() -> void:
	ending_pending = true
	get_tree().change_scene_to_file("res://ui/story_scene.tscn")


## StoryScene 感谢游玩黑屏放完后调
func finish_ending() -> void:
	ending_pending = false
	credits_fade_pending = true
	goto_credits()


# ---- 关卡回报 ----

## fire_cue = false:小机代解时不庆祝、不鼓励(美术/策划要求「此时没有鼓励」)
func notify_solved(board_state: Dictionary, fire_cue: bool = true) -> void:
	if current == null:
		return
	save.mark_solved(current.id)
	save.set_board_state(current.id, board_state)
	save.save()
	if fire_cue or current.id == BREAK_LEVEL:
		# 3-1 的通关演出是「坏掉」剧情节点(panic),不是庆祝:小机代解(平时压掉演出)也要演
		robot_cue(current.robot_cue_on_win)
	if current.id == BREAK_LEVEL:
		var robot := get_node_or_null("/root/Robot")
		if robot != null:
			robot.broken = true   # 3-1 通关瞬间坏掉;修好在结局(StoryScene._play_thanks)


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
