extends SceneTree
## 一次性生成 16 关 .tres + catalog + 诺拉的笔记(七台仪器的可本地化文字与独立图示)。
##   godot --headless --path . --script res://tools/gen_levels.gd
## 生成后策划直接在 Inspector 改 .tres;本脚本仅在想整表重生成时再跑
## (会覆盖 levels/data/ 与 narrative/data/ 下的同名文件)。
## 关名按美术要求 = 章内序号「第N纹」,章名按美术图。
## 台词不在本表:正式台词用 tools/xlsx_to_csv.py + tools/import_dialogue.gd 灌进 .tres,
## 重生成时从现有 .tres 原样保留 intro/outro 对话(不会被打回占位)。

# [id, 假设, 目标, 本关原子, 本关新上架的仪器]
# 仪器按关解锁、逐关累计(allowed_rules = 到本关为止上架过的全部仪器;仪器架只显示这些):
#   l02 并织 · l03 拆股 · l06 引渡 · l07 封程 · l11 岔纹 · l12 汇路 · l14 溃散;l01 一台都没有。
# 台词不在这(见文件头:import_dialogue 管线)
const LEVELS: Array = [
	[1, ["A"], "A", ["A"], []],
	[2, ["A", "B"], "A & B", ["A", "B"], [&"and_intro"]],
	[3, ["A & B"], "A", ["A", "B"], [&"and_elim"]],
	[4, ["A & B"], "B & A", ["A", "B"], []],
	[5, ["A & (B & C)"], "(A & B) & C", ["A", "B", "C"], []],
	[6, ["A", "A > B"], "B", ["A", "B"], [&"imp_elim"]],
	[7, [], "A > A", ["A"], [&"imp_intro"]],
	[8, ["A > B", "B > C"], "A > C", ["A", "B", "C"], []],
	[9, [], "A > (B > A)", ["A", "B"], []],
	[10, ["A & B > C"], "A > (B > C)", ["A", "B", "C"], []],
	[11, ["A"], "A | B", ["A", "B"], [&"or_intro"]],
	[12, ["A | B"], "B | A", ["A", "B"], [&"or_elim"]],
	[13, ["(A > C) & (B > C)"], "(A | B) > C", ["A", "B", "C"], []],
	[14, ["false"], "A", ["A"], [&"false_elim"]],
	[15, ["A > B"], "(B > false) > (A > false)", ["A", "B"], []],
	[16, ["A & (A > false)"], "B", ["A", "B"], []],
]

# 章名按美术图;关名 = 章内序号「第N纹」
const CH_TITLES: Array[String] = ["第一章 并纹", "第二章 叠层纹", "第三章 岔纹", "第四章 焦纹"]
const CN_NUM: Array[String] = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
const CH_OF_LEVEL: Array[int] = [0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3]

# 诺拉的笔记 = [rule_id, 标题, 正文]；图示固定取 assets/art/level/notebook/<rule_id>.png。
# 顺序 = 仪器架顺序。文字由 NotebookUI 在纸张安全区自动排列，不能再烘焙进图示。
const NOTEBOOK_PAGES: Array = [
	["and_intro", "并织机", "左侧上下两口各收一幅纹样，织成一幅左右并排的并纹，少了任何一股，机器都不会开工。"],
	["and_elim", "拆股机", "收一幅并纹，上口吐出它的左半，下口吐出它的右半，想用哪股接哪股。"],
	["imp_intro", "封程机", "左上口自己钉一副纹样，机器会凭空吐出它，但吐出的只是虚纹，切不可放入最终交付，必须用它织出另一幅纹样（也可以与自身相同），接入右上口，随后右下口便可吐出一副实在的叠层纹。"],
	["imp_elim", "引渡机", "左上口收一副迭层纹，左下口收它上层的纹样，机器吐出下层的纹样。"],
	["or_intro", "岔纹机", "收一幅纹样，织成岔纹；上口输出的纹样中它在左上，下口输出的纹样中它在右下，对角线另一侧的纹样则由你自己钉。"],
	["or_elim", "汇路机", "上1口收入一副岔纹，岔纹对角线两侧的纹样分别由右2和右3口吐出，吐出的两幅纹样均为虚纹，若用他们都能织出同一副纹样分别送入左2和左3口，则汇路机可以织出这副纹样的实纹。"],
	["false_elim", "溃散机", "收进一幅焦纹以后，这台机器什么都肯织——织什么由你钉。工坊严令：慎用。"],
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://levels/data")
	DirAccess.make_dir_recursive_absolute("res://narrative/data")
	var catalog := LevelCatalog.new()
	for t in CH_TITLES:
		var ch := ChapterDef.new()
		ch.title = t
		catalog.chapters.append(ch)
	var shelved: Array[StringName] = []   # 到本关为止上架过的仪器(按上架顺序)
	for i in LEVELS.size():
		var row: Array = LEVELS[i]
		for r in row[4]:
			assert(not shelved.has(r), "仪器重复上架: %s" % r)
			shelved.append(r)
		var ch_idx := CH_OF_LEVEL[i]
		var lv := _build_level(row, ch_idx, catalog.chapters[ch_idx].levels.size(), shelved)
		var path := "res://levels/data/l%02d_%s.tres" % [row[0], lv.id]
		if ResourceLoader.exists(path):   # 正式台词已灌进 .tres:重生成时原样保留
			var old: LevelDef = load(path)
			lv.intro_dialogue = old.intro_dialogue
			lv.outro_dialogue = old.outro_dialogue
		_save(lv, path)
		catalog.chapters[ch_idx].levels.append(load(path))
	_save(catalog, "res://levels/data/catalog.tres")

	var nb := NotebookCatalog.new()
	for row: Array in NOTEBOOK_PAGES:
		var e := NotebookEntry.new()
		e.id = StringName(row[0])
		e.title = row[1]
		e.description = row[2]
		e.image = "res://assets/art/level/notebook/%s.png" % row[0]
		nb.entries.append(e)
	_save(nb, "res://narrative/data/notebook.tres")

	print("生成完毕: %d 关 + catalog + 诺拉的笔记 %d 条" % [LEVELS.size(), NOTEBOOK_PAGES.size()])
	quit(0)


## idx_in_chapter = 章内第几关(0 起),关名即「第N纹」;shelved = 到本关为止上架的仪器(复制一份存进关卡)
func _build_level(row: Array, ch_idx: int, idx_in_chapter: int, shelved: Array[StringName]) -> LevelDef:
	var lv := LevelDef.new()
	var num: int = row[0]
	lv.id = StringName("l%02d" % num)
	lv.title = "第%s纹" % CN_NUM[idx_in_chapter]
	lv.assumptions.assign(row[1])
	lv.goal = row[2]
	lv.atoms.assign(row[3].map(func(s: String) -> StringName: return StringName(s)))
	lv.allowed_rules.assign(shelved)
	lv.allow_bot = ch_idx >= 3
	# 小机剧情弧:3-1 通关瞬间坏掉 → 它的通关演出是故障(panic),其余庆祝;进关一律无演出
	lv.robot_cue_on_win = "panic" if (ch_idx == 2 and idx_in_chapter == 0) else "celebrate"
	return lv


func _save(res: Resource, path: String) -> void:
	# 子资源(对话行等)随主资源内嵌保存,策划在 Inspector 里展开即可编辑
	var err := ResourceSaver.save(res, path)
	assert(err == OK, "保存失败 %s: %d" % [path, err])
