extends SceneTree
## 一次性生成 17 关 .tres + catalog + 笔记本(占位文案,标 [占位])。
##   godot --headless --path . --script res://tools/gen_levels.gd
## 生成后策划直接在 Inspector 改 .tres;本脚本仅在想整表重生成时再跑
## (会覆盖 levels/data/ 与 narrative/data/ 下的同名文件)。

const CH_RULES: Array = [
	[&"and_intro", &"and_elim"],
	[&"imp_intro", &"imp_elim"],
	[&"or_intro", &"or_elim"],
	[&"false_elim"],
	[&"tnd"],
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
	[7, "自证", [], [], "A > A", ["A"], [
		["莉娅", "[占位] 空手也能立诺:钉住一个假设,再原样交还。点封程机上的「钉纹样」。", "think"],
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
	[16, "两仪", [], [], "A | (A > false)", ["A"], [
		["小机", "[占位] 警告——检测到排中律注入!我、我的推理核心在过热——", "panic"],
	]],
	[17, "归于平静", ["notebook_tnd"], ["A > B"], "(A > false) | B", ["A", "B"], [
		["小机", "[占位] ……在你的证明里,我找回了前提。谢谢你,织者。", "calm"],
	]],
]

const CH_TITLES: Array[String] = ["第一章·并织", "第二章·封程", "第三章·岔纹", "第四章·焦纹", "第五章·两仪"]
const CH_OF_LEVEL: Array[int] = [0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4]

const NOTEBOOK: Array = [
	["notebook_and", "并织即「与」", "[占位] 档案室手稿:竖分的纹样,恰是逻辑学里的合取 A ∧ B。", "A & B"],
	["notebook_imp", "迭层即「蕴含」", "[占位] 上层作前提,下层作结论:A → B。", "A > B"],
	["notebook_or", "岔纹即「或」", "[占位] 对角一分,两可之间:A ∨ B。", "A | B"],
	["notebook_bot", "焦纹即「谬」", "[占位] 烧穿之处,万物皆可织出:⊥。", "false"],
	["notebook_tnd", "两仪即「排中」", "[占位] 有或没有,天下无第三种布:A ∨ ¬A。", "A | (A > false)"],
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
	print("生成完毕: %d 关 + catalog + notebook" % LEVELS.size())
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
	for line: Array in row[6]:
		var dl := DialogueLine.new()
		dl.speaker = line[0]
		dl.text = line[1]
		dl.robot_cue = line[2]
		dl.side_right = line[0] == "小机"
		dlg.lines.append(dl)
	lv.intro_dialogue = dlg
	if ch_idx == 4:
		lv.robot_cue_on_enter = "panic" if num == 16 else "glitch"
	lv.robot_cue_on_win = "celebrate"
	return lv


func _save(res: Resource, path: String) -> void:
	# 子资源(对话行等)随主资源内嵌保存,策划在 Inspector 里展开即可编辑
	var err := ResourceSaver.save(res, path)
	assert(err == OK, "保存失败 %s: %d" % [path, err])
