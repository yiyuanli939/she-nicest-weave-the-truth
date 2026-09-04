class_name NotebookEn
extends RefCounted
## 诺拉的笔记 —— 七页整页图的英文文案(中文只画在 assets/art/level/notebook/<rule_id>.png 里,这里是英文版唯一的文字源)。
## tools/gen_locale_art.gd 用它把英文画进 <rule_id>.en.png(程序占位图,美术交英文图后直接覆盖文件即可)。
## 文案守则同 docs/CONTENT_INTERFACE.md 笔记段:只用纺织词汇(pattern / ply / layered docket / fork / scorched …),
## 不出现逻辑符号或规则名;只用 ASCII + – — …(站酷小薇体没有重音字母,弯引号是全角字形不用;tests/test_theme.gd 盯)。
## 仪器英文名与 locale/ui.csv 一致(Plying / Unply / Sealing / Redeem / Forking / Merging / Ruin Loom)。

const PAGES: Dictionary = {
	&"and_intro": {
		title = "Plying Loom",
		body = "The two ports on the left each take in a pattern, and the loom weaves them into one plied pattern, side by side. If either strand is missing, the loom will not start.",
		note = "",
	},
	&"and_elim": {
		title = "Unply Loom",
		body = "Takes in a plied pattern: the upper port gives out its left half, the lower port its right half. Use whichever strand you need.",
		note = "",
	},
	&"imp_intro": {
		title = "Sealing Loom",
		body = "The spool port conjures a pattern you have pinned, a phantom thread on loan. Weave it into a finished piece and feed that into the loose port: the loom seals the whole run into one layered docket, and the borrowed thread is repaid.",
		note = "Your call!",
	},
	&"imp_elim": {
		title = "Redeem Loom",
		body = "One port takes in a layered docket, the other takes in its upper pattern; the loom hands over the lower one.",
		note = "",
	},
	&"or_intro": {
		title = "Forking Loom",
		body = "Takes in a pattern and weaves it into a fork pattern, split on the diagonal: the upper port sets it on the plug side, the lower port on the other side. The other branch of the fork is unknown to the loom – you decide it.",
		note = "",
	},
	&"or_elim": {
		title = "Merging Loom",
		body = "Port 0 takes in a fork pattern; the two dashed ports each give out one branch of the fork, for two routes to weave separately. Only when both routes weave the same finished piece does the loom give out its solid pattern.",
		note = "",
	},
	&"false_elim": {
		title = "Ruin Loom",
		body = "Once it has taken in a scorched pattern, this loom will weave anything at all – what it weaves is yours to pin. Workshop orders: use with care.",
		note = "Really? Anything?",
	},
}
