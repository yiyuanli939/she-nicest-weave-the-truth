extends SceneTree
## 一次性生成 15 关 .tres + catalog + 诺拉的笔记(七台仪器说明;占位文案标 [占位])。
##   godot --headless --path . --script res://tools/gen_levels.gd
## 生成后策划直接在 Inspector 改 .tres;本脚本仅在想整表重生成时再跑
## (会覆盖 levels/data/ 与 narrative/data/ 下的同名文件)。
## 关名按美术要求 = 章内序号「第N纹」,章名按美术图。
## 台词不在本表:正式台词用 tools/xlsx_to_csv.py + tools/import_dialogue.gd 灌进 .tres,
## 重生成时从现有 .tres 原样保留 intro/outro 对话(不会被打回占位)。

const CH_RULES: Array = [
	[&"and_intro", &"and_elim"],
	[&"imp_intro", &"imp_elim"],
	[&"or_intro", &"or_elim"],
	[&"false_elim"],
]

# [id, 假设, 目标, 本关原子];台词不在这(见文件头:import_dialogue 管线)
const LEVELS: Array = [
	[1, ["A"], "A", ["A"]],
	[2, ["A", "B"], "A & B", ["A", "B"]],
	[3, ["A & B"], "B & A", ["A", "B"]],
	[4, ["A & (B & C)"], "(A & B) & C", ["A", "B", "C"]],
	[5, ["A", "A > B"], "B", ["A", "B"]],
	[6, ["A > B", "B > C"], "A > C", ["A", "B", "C"]],
	[7, [], "A > A", ["A"]],
	[8, [], "A > (B > A)", ["A", "B"]],
	[9, ["A & B > C"], "A > (B > C)", ["A", "B", "C"]],
	[10, ["A"], "A | B", ["A", "B"]],
	[11, ["A | B"], "B | A", ["A", "B"]],
	[12, ["(A > C) & (B > C)"], "(A | B) > C", ["A", "B", "C"]],
	[13, ["false"], "A", ["A"]],
	[14, ["A > B"], "(B > false) > (A > false)", ["A", "B"]],
	[15, ["A & (A > false)"], "B", ["A", "B"]],
]

# 章名按美术图;关名 = 章内序号「第N纹」
const CH_TITLES: Array[String] = ["第一章 并纹", "第二章 叠层纹", "第三章 岔纹", "第四章 焦纹"]
const CN_NUM: Array[String] = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
const CH_OF_LEVEL: Array[int] = [0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3]

# 诺拉的笔记 = 七台仪器说明:[rule_id, 展示名, 一句话, 详解(BBCode), 示例公式(先仅文字,留空)]
# 顺序 = 仪器架顺序(美术图)。文案守则:只讲机器行为与操作,用纺织语汇;
# 不出现逻辑符号/逻辑术语/规则陈述/解法提示,也不出现字体没有的符号。
const RULE_GUIDE: Array = [
	["and_intro", "并织机", "[占位] 两股丝,并作一幅。",
		"[占位] 左右两口各收一幅纹样,织成一幅左右并排的并纹。少了任何一股,机器都不开工。", ""],
	["and_elim", "拆股机", "[占位] 并纹拆回两股。",
		"[占位] 收一幅并纹,上口吐出它的左半,下口吐出右半。想用哪股接哪股。", ""],
	["imp_intro", "封程机", "[占位] 空手立一张「若…则…」的封单。",
		"[占位] 全场最讲究的一台。线轴口凭空吐出一幅你钉住的纹样,当作暂借的丝;拿去织出成品、汇回散口,机器便把整段织程封成一张迭层纹封单,借来的丝就此还清。", ""],
	["imp_elim", "引渡机", "[占位] 凭单取货。",
		"[占位] 一口收一张迭层纹封单,另一口收它上层的纹样,机器兑出下层的货。", ""],
	["or_intro", "岔纹机", "[占位] 一股丝,岔出两可。",
		"[占位] 收一幅纹样,织成对角分岔的岔纹:上口把它排在岔口一侧、下口排在另一侧。岔纹的另一支机器自己不知道该织什么——点标题栏的「钉上口/钉下口」,由你来定。", ""],
	["or_elim", "汇路机", "[占位] 岔路汇流,殊途同归。",
		"[占位] 0 号口收一幅岔纹,两个线轴口各吐出岔纹的一支,交给两条支路分头去织;两条支路织回同样的成品,机器才把它吐出来。线轴口的纹样随 0 号口自动定,不用钉。", ""],
	["false_elim", "溃散机", "[占位] 焦纹入机,百无禁忌。",
		"[占位] 收进一幅烧穿的焦纹后,这台机器什么都肯织——织什么由你钉。工坊严令:慎用。", ""],
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://levels/data")
	DirAccess.make_dir_recursive_absolute("res://narrative/data")
	var catalog := LevelCatalog.new()
	for t in CH_TITLES:
		var ch := ChapterDef.new()
		ch.title = t
		catalog.chapters.append(ch)
	for i in LEVELS.size():
		var row: Array = LEVELS[i]
		var ch_idx := CH_OF_LEVEL[i]
		var lv := _build_level(row, ch_idx, catalog.chapters[ch_idx].levels.size())
		var path := "res://levels/data/l%02d_%s.tres" % [row[0], lv.id]
		if ResourceLoader.exists(path):   # 正式台词已灌进 .tres:重生成时原样保留
			var old: LevelDef = load(path)
			lv.intro_dialogue = old.intro_dialogue
			lv.outro_dialogue = old.outro_dialogue
		_save(lv, path)
		catalog.chapters[ch_idx].levels.append(load(path))
	_save(catalog, "res://levels/data/catalog.tres")

	var nb := NotebookCatalog.new()
	for row in RULE_GUIDE:
		var e := NotebookEntry.new()
		e.id = StringName(row[0])
		e.title = row[1]
		e.body = row[2] + "\n\n" + row[3]
		e.demo_formula = row[4]
		nb.entries.append(e)
	_save(nb, "res://narrative/data/notebook.tres")

	print("生成完毕: %d 关 + catalog + 诺拉的笔记 %d 条" % [LEVELS.size(), RULE_GUIDE.size()])
	quit(0)


## idx_in_chapter = 章内第几关(0 起),关名即「第N纹」
func _build_level(row: Array, ch_idx: int, idx_in_chapter: int) -> LevelDef:
	var lv := LevelDef.new()
	var num: int = row[0]
	lv.id = StringName("l%02d" % num)
	lv.title = "第%s纹" % CN_NUM[idx_in_chapter]
	lv.assumptions.assign(row[1])
	lv.goal = row[2]
	lv.atoms.assign(row[3].map(func(s: String) -> StringName: return StringName(s)))
	var rules: Array[StringName] = []
	for c in ch_idx + 1:
		rules.append_array(CH_RULES[c])
	lv.allowed_rules = rules
	lv.allow_bot = ch_idx >= 3
	# 小机剧情弧:3-1(l10)通关瞬间坏掉 → 它的通关演出是故障(panic),其余庆祝;进关一律无演出
	lv.robot_cue_on_win = "panic" if num == 10 else "celebrate"
	return lv


func _save(res: Resource, path: String) -> void:
	# 子资源(对话行等)随主资源内嵌保存,策划在 Inspector 里展开即可编辑
	var err := ResourceSaver.save(res, path)
	assert(err == OK, "保存失败 %s: %d" % [path, err])
