extends SceneTree
## 一次性生成 15 关 .tres + catalog + 笔记本(占位文案,标 [占位])。
##   godot --headless --path . --script res://tools/gen_levels.gd
## 生成后策划直接在 Inspector 改 .tres;本脚本仅在想整表重生成时再跑
## (会覆盖 levels/data/ 与 narrative/data/ 下的同名文件)。

const CH_RULES: Array = [
	[&"and_intro", &"and_elim"],
	[&"imp_intro", &"imp_elim"],
	[&"or_intro", &"or_elim"],
	[&"false_elim"],
]

# [id, 标题, 假设, 目标, 章内新原子, 进关cue, 通关cue, 笔记解锁, 对话行...]
# 对话行: [speaker, text, robot_cue]
const LEVELS: Array = [
	[1, "第一缕丝", [], ["A"], "A", ["A"], [
		["阿梭", "[占位] 欢迎来到织坊。把线轴上的纹样引到目标织机,轻点连线即可。", "greet"],
	]],
	[2, "并织初试", [], ["A", "B"], "A & B", ["A", "B"], [
		["阿梭", "[占位] 两股丝可以并成一幅纹样——试试并织机。", ""],
	]],
	[3, "左右互换", [], ["A & B"], "B & A", ["A", "B"], [
		["阿梭", "[占位] 拆开,再反着织回去。", ""],
	]],
	[4, "结绳记事", ["notebook_and"], ["A & (B & C)"], "(A & B) & C", ["A", "B", "C"], [
		["阿梭", "[占位] 括号只是记法,布面自会说话。", ""],
	]],
	[5, "引渡", [], ["A", "A > B"], "B", ["A", "B"], [
		["莉娅", "[占位] 迭层纹是一张承诺:给它上层的纹样,它吐出下层。", ""],
	]],
	[6, "接力", [], ["A > B", "B > C"], "A > C", ["A", "B", "C"], [
		["莉娅", "[占位] 承诺可以串成链。你需要封程机来立一张新承诺。", ""],
	]],
	[7, "自证", ["notebook_imp_intro"], [], "A > A", ["A"], [
		["莉娅", "[占位] 封程机是全场最讲究的一台。别急,我一步步带你。", "think"],
		["莉娅", "[占位] 它要立一张「若…则…」的封单,可你现在手上一根线都没有。", ""],
		["莉娅", "[占位] 那就先借:点封程机的「钉纹样」,钉住一幅 A —— 线轴口会吐出这幅暂借的丝。", "think"],
		["莉娅", "[占位] 拿借来的 A 去织要交的成品。这一关要交的恰好也是 A,原样送回散口即可。", ""],
		["莉娅", "[占位] 封程机会把整段织程封成「若 A 则 A」,借来的丝就此还清。细节翻右边的笔记。", ""],
	]],
	[8, "层层封存", [], [], "A > (B > A)", ["A", "B"], [
		["莉娅", "[占位] 诺中之诺。外层的假设,内层也认。", ""],
	]],
	[9, "柯里化", ["notebook_imp"], ["A & B > C"], "A > (B > C)", ["A", "B", "C"], [
		["莉娅", "[占位] 一次收两股,等于分两次各收一股。档案室里有类似的记载……", ""],
	]],
	[10, "岔路", [], ["A"], "A | B", ["A", "B"], [
		["档案员", "[占位] 岔纹机:已有其一,便可宣称「二者有其一」。", ""],
	]],
	[11, "殊途同归", [], ["A | B"], "B | A", ["A", "B"], [
		["档案员", "[占位] 不知道来的是哪股?汇路机让你两头都备好。", ""],
	]],
	[12, "两案并陈", ["notebook_or"], ["(A > C) & (B > C)"], "(A | B) > C", ["A", "B", "C"], [
		["档案员", "[占位] 无论走哪条岔路,终点相同,结论便立。", ""],
	]],
	[13, "焦土", [], ["false"], "A", ["A"], [
		["档案员", "[占位] 焦纹是烧穿的布。从谬误出发,织机可以吐出任何纹样——这很危险。", "confused"],
	]],
	[14, "逆否", [], ["A > B"], "(B > false) > (A > false)", ["A", "B"], [
		["档案员", "[占位] 若 B 会烧穿,那给出 A 也终将烧穿。", ""],
	]],
	[15, "矛盾爆炸", ["notebook_bot"], ["A & (A > false)"], "B", ["A", "B"], [
		["档案员", "[占位] 同时持有一股丝与它的禁纹,织机就失去了约束……小家伙好像不太安稳。", "glitch"],
	]],
]

const CH_TITLES: Array[String] = ["第一章·并织", "第二章·封程", "第三章·岔纹", "第四章·焦纹"]
const CH_LOCATIONS: Array[String] = ["[占位] 织坊", "[占位] 封程工房", "[占位] 档案室", "[占位] 焦纹禁室"]
const CH_OF_LEVEL: Array[int] = [0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3]

const NOTEBOOK: Array = [
	["notebook_and", "并织即「与」", "[占位] 档案室手稿:竖分的纹样,恰是逻辑学里的合取 A ∧ B。", "A & B"],
	["notebook_imp_intro", "封程机 · 立一张封单",
		"[占位] 封程机能凭空立下一张封单,分三步:\n"
		+ "[b]① 借[/b] —— 点「钉纹样」,钉住一幅想假借的纹样;机器的线轴口便吐出这幅暂借的丝。\n"
		+ "[b]② 织[/b] —— 把借来的丝当真丝用,一路织出要交的成品,汇回机器的散口。\n"
		+ "[b]③ 封[/b] —— 机器把「借了它,便织得出」封成一幅迭层纹。借来的丝就此还清,不欠账。\n"
		+ "口诀:先借,再织,封单还清。", "A > B"],
	["notebook_imp", "迭层即「蕴含」", "[占位] 上层作前提,下层作结论:A → B。", "A > B"],
	["notebook_or", "岔纹即「或」", "[占位] 对角一分,两可之间:A ∨ B。", "A | B"],
	["notebook_bot", "焦纹即「谬」", "[占位] 烧穿之处,万物皆可织出:⊥。", "false"],
]

# 仪器介绍卡(点选机器时弹出):[rule_id, 展示名, 一句话, 详解(BBCode), 示例公式]
# 文案守则:只讲机器行为与操作,用纺织语汇;不出现逻辑符号/逻辑术语/规则陈述/解法提示。
# 逻辑同构只在通关后解锁的笔记条目里揭示(那是奖励,不是提示)。
const RULE_GUIDE: Array = [
	["and_intro", "并织机", "[占位] 两股丝,并作一幅。",
		"[占位] 左右两口各收一幅纹样,织成一幅左右并排的并纹。少了任何一股,机器都不开工。", "A & B"],
	["and_elim", "拆股机", "[占位] 并纹拆回两股。",
		"[占位] 收一幅并纹,上口吐出它的左半,下口吐出右半。想用哪股接哪股。", "A & B"],
	["or_intro", "岔纹机", "[占位] 一股丝,岔出两可。",
		"[占位] 收一幅纹样,织成对角分岔的岔纹:上口把它排在岔口一侧、下口排在另一侧。岔纹的另一支机器自己不知道该织什么——点标题栏的「钉上口/钉下口」,由你来定。", "A | B"],
	["or_elim", "汇路机", "[占位] 岔路汇流,殊途同归。",
		"[占位] 0 号口收一幅岔纹,两个线轴口各吐出岔纹的一支,交给两条支路分头去织;两条支路织回同样的成品,机器才把它吐出来。线轴口的纹样随 0 号口自动定,不用钉。", "A | B"],
	["imp_intro", "封程机", "[占位] 空手立一张「若…则…」的封单。",
		"[占位] 全场最讲究的一台。线轴口凭空吐出一幅你钉住的纹样,当作暂借的丝;拿去织出成品、汇回散口,机器便把整段织程封成一张迭层纹封单,借来的丝就此还清。详见织者笔记。", "A > B"],
	["imp_elim", "引渡机", "[占位] 凭单取货。",
		"[占位] 一口收一张迭层纹封单,另一口收它上层的纹样,机器兑出下层的货。", "A > B"],
	["false_elim", "溃散机", "[占位] 焦纹入机,百无禁忌。",
		"[占位] 收进一幅烧穿的焦纹后,这台机器什么都肯织——织什么由你钉。工坊严令:慎用。", "A"],
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
		var lv := _build_level(row, ch_idx)
		var path := "res://levels/data/l%02d_%s.tres" % [row[0], lv.id]
		_save(lv, path)
		catalog.chapters[ch_idx].levels.append(load(path))
	_save(catalog, "res://levels/data/catalog.tres")

	var nb := NotebookCatalog.new()
	for row in NOTEBOOK:
		var e := NotebookEntry.new()
		e.id = StringName(row[0])
		e.title = row[1]
		e.body = row[2]
		e.demo_formula = row[3]
		nb.entries.append(e)
	_save(nb, "res://narrative/data/notebook.tres")

	var guides := RuleGuideCatalog.new()
	for row in RULE_GUIDE:
		var g := RuleGuide.new()
		g.rule_id = StringName(row[0])
		g.title = row[1]
		g.summary = row[2]
		g.body = row[3]
		g.demo_formula = row[4]
		guides.entries.append(g)
	_save(guides, "res://narrative/data/rule_guide.tres")

	print("生成完毕: %d 关 + catalog + notebook + %d 仪器介绍" % [LEVELS.size(), RULE_GUIDE.size()])
	quit(0)


func _build_level(row: Array, ch_idx: int) -> LevelDef:
	var lv := LevelDef.new()
	var num: int = row[0]
	lv.id = StringName("l%02d" % num)
	lv.title = row[1]
	lv.notebook_unlocks.assign(row[2])
	lv.assumptions.assign(row[3])
	lv.goal = row[4]
	lv.atoms.assign(row[5].map(func(s: String) -> StringName: return StringName(s)))
	var rules: Array[StringName] = []
	for c in ch_idx + 1:
		rules.append_array(CH_RULES[c])
	lv.allowed_rules = rules
	lv.allow_bot = ch_idx >= 3
	var dlg := DialogueRes.new()
	dlg.location_title = CH_LOCATIONS[ch_idx]
	for line: Array in row[6]:
		var dl := DialogueLine.new()
		dl.speaker = line[0]
		dl.text = line[1]
		dl.robot_cue = line[2]
		dl.side_right = line[0] == "小机"
		dlg.lines.append(dl)
	lv.intro_dialogue = dlg
	lv.robot_cue_on_win = "celebrate"
	return lv


func _save(res: Resource, path: String) -> void:
	# 子资源(对话行等)随主资源内嵌保存,策划在 Inspector 里展开即可编辑
	var err := ResourceSaver.save(res, path)
	assert(err == OK, "保存失败 %s: %d" % [path, err])
