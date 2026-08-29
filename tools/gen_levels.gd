extends SceneTree
## 一次性生成 15 关 .tres + catalog + 诺拉的笔记(七台仪器说明;占位文案标 [占位])。
##   godot --headless --path . --script res://tools/gen_levels.gd
## 生成后策划直接在 Inspector 改 .tres;本脚本仅在想整表重生成时再跑
## (会覆盖 levels/data/ 与 narrative/data/ 下的同名文件)。
## 关名按美术要求 = 章内序号「第N纹」,章名按美术图;台词是占位,正式台词用 tools/import_dialogue.gd 从 CSV 灌。

const CH_RULES: Array = [
	[&"and_intro", &"and_elim"],
	[&"imp_intro", &"imp_elim"],
	[&"or_intro", &"or_elim"],
	[&"false_elim"],
]

# [id, 假设, 目标, 本关原子, 对话行...]
# 对话行: [speaker, text, robot_cue]
const LEVELS: Array = [
	[1, ["A"], "A", ["A"], [
		["阿梭", "[占位] 欢迎来到织坊。把线轴上的纹样引到目标织机,轻点连线即可。", "greet"],
	]],
	[2, ["A", "B"], "A & B", ["A", "B"], [
		["阿梭", "[占位] 两股丝可以并成一幅纹样——试试并织机。", ""],
	]],
	[3, ["A & B"], "B & A", ["A", "B"], [
		["阿梭", "[占位] 拆开,再反着织回去。", ""],
	]],
	[4, ["A & (B & C)"], "(A & B) & C", ["A", "B", "C"], [
		["阿梭", "[占位] 括号只是记法,布面自会说话。", ""],
	]],
	[5, ["A", "A > B"], "B", ["A", "B"], [
		["莉娅", "[占位] 迭层纹是一张承诺:给它上层的纹样,它吐出下层。", ""],
	]],
	[6, ["A > B", "B > C"], "A > C", ["A", "B", "C"], [
		["莉娅", "[占位] 承诺可以串成链。你需要封程机来立一张新承诺。", ""],
	]],
	[7, [], "A > A", ["A"], [
		["莉娅", "[占位] 封程机是全场最讲究的一台。别急,我一步步带你。", "think"],
		["莉娅", "[占位] 它要立一张「若…则…」的封单,可你现在手上一根线都没有。", ""],
		["莉娅", "[占位] 那就先借:点封程机的「钉纹样」,钉住一幅 A —— 线轴口会吐出这幅暂借的丝。", "think"],
		["莉娅", "[占位] 拿借来的 A 去织要交的成品。这一关要交的恰好也是 A,原样送回散口即可。", ""],
		["莉娅", "[占位] 封程机会把整段织程封成「若 A 则 A」,借来的丝就此还清。细节翻右边的笔记。", ""],
	]],
	[8, [], "A > (B > A)", ["A", "B"], [
		["莉娅", "[占位] 诺中之诺。外层的假设,内层也认。", ""],
	]],
	[9, ["A & B > C"], "A > (B > C)", ["A", "B", "C"], [
		["莉娅", "[占位] 一次收两股,等于分两次各收一股。档案室里有类似的记载……", ""],
	]],
	[10, ["A"], "A | B", ["A", "B"], [
		["档案员", "[占位] 岔纹机:已有其一,便可宣称「二者有其一」。", ""],
	]],
	[11, ["A | B"], "B | A", ["A", "B"], [
		["档案员", "[占位] 不知道来的是哪股?汇路机让你两头都备好。", ""],
	]],
	[12, ["(A > C) & (B > C)"], "(A | B) > C", ["A", "B", "C"], [
		["档案员", "[占位] 无论走哪条岔路,终点相同,结论便立。", ""],
	]],
	[13, ["false"], "A", ["A"], [
		["档案员", "[占位] 焦纹是烧穿的布。从谬误出发,织机可以吐出任何纹样——这很危险。", "confused"],
	]],
	[14, ["A > B"], "(B > false) > (A > false)", ["A", "B"], [
		["档案员", "[占位] 若 B 会烧穿,那给出 A 也终将烧穿。", ""],
	]],
	[15, ["A & (A > false)"], "B", ["A", "B"], [
		["档案员", "[占位] 同时持有一股丝与它的禁纹,织机就失去了约束……小家伙好像不太安稳。", "glitch"],
	]],
]

# 章名按美术图;关名 = 章内序号「第N纹」
const CH_TITLES: Array[String] = ["第一章 并纹", "第二章 叠层纹", "第三章 岔纹", "第四章 焦纹"]
const CN_NUM: Array[String] = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
const CH_OF_LEVEL: Array[int] = [0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3]
# 进关时的小机演出:第三章开头(l10)当场故障,第四章开头(l13)修好
const ENTER_CUE: Dictionary = {10: "panic", 13: "calm"}

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
	# 占位对话:场景一律工坊;发言人若是登记过立绘的配角就站左侧,否则左侧留空;诺拉恒右
	var dlg := DialogueRes.new()
	for line: Array in row[4]:
		var dl := DialogueLine.new()
		dl.speaker = line[0]
		dl.text = line[1]
		dl.robot_cue = line[2]
		dl.scene = "工坊"
		var who := StoryArt.character_of(line[0])
		dl.left_char = who if who != "" and not StoryArt.is_nora(line[0]) else ""
		dlg.lines.append(dl)
	lv.intro_dialogue = dlg
	lv.robot_cue_on_win = "celebrate"
	lv.robot_cue_on_enter = ENTER_CUE.get(num, "")
	return lv


func _save(res: Resource, path: String) -> void:
	# 子资源(对话行等)随主资源内嵌保存,策划在 Inspector 里展开即可编辑
	var err := ResourceSaver.save(res, path)
	assert(err == OK, "保存失败 %s: %d" % [path, err])
