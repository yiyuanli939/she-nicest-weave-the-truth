class_name LevelSolutions
extends RefCounted
## 16 关的脚本化解法(全流程验收 + 演示用)。
## 节点引用:"s0","s1"=第 N 条假设线轴;"g"=目标织机;"m0".."mN"=按 m 表顺序放置的仪器。
## w = 连线 [from, from_port, to, to_port];p = 钉纹样 [machine, out_port, 公式文本]。
## 解法只能用本关已上架的仪器(tests/test_levels.gd 盯着)。

const DATA: Dictionary = {
	&"l01": {m = [], w = [["s0", 0, "g", 0]], p = []},
	&"l02": {m = [&"and_intro"],
		w = [["s0", 0, "m0", 0], ["s1", 0, "m0", 1], ["m0", 0, "g", 0]], p = []},
	&"l03": {m = [&"and_elim"],
		w = [["s0", 0, "m0", 0], ["m0", 0, "g", 0]], p = []},
	&"l04": {m = [&"and_elim", &"and_intro"],
		w = [["s0", 0, "m0", 0], ["m0", 1, "m1", 0], ["m0", 0, "m1", 1], ["m1", 0, "g", 0]], p = []},
	&"l05": {m = [&"and_elim", &"and_elim", &"and_intro", &"and_intro"],
		w = [["s0", 0, "m0", 0], ["m0", 1, "m1", 0],
			["m0", 0, "m2", 0], ["m1", 0, "m2", 1],
			["m2", 0, "m3", 0], ["m1", 1, "m3", 1], ["m3", 0, "g", 0]], p = []},
	&"l06": {m = [&"imp_elim"],
		w = [["s1", 0, "m0", 0], ["s0", 0, "m0", 1], ["m0", 0, "g", 0]], p = []},
	&"l07": {m = [&"imp_intro"],
		w = [["m0", 1, "m0", 0], ["m0", 0, "g", 0]], p = [["m0", 1, "A"]]},
	&"l08": {m = [&"imp_intro", &"imp_elim", &"imp_elim"],
		w = [["s0", 0, "m1", 0], ["m0", 1, "m1", 1],
			["s1", 0, "m2", 0], ["m1", 0, "m2", 1],
			["m2", 0, "m0", 0], ["m0", 0, "g", 0]],
		p = [["m0", 1, "A"]]},
	&"l09": {m = [&"imp_intro", &"imp_intro"],
		w = [["m1", 0, "m0", 0], ["m0", 1, "m1", 0], ["m0", 0, "g", 0]],
		p = [["m0", 1, "A"], ["m1", 1, "B"]]},
	&"l10": {m = [&"imp_intro", &"imp_intro", &"and_intro", &"imp_elim"],
		w = [["m0", 1, "m2", 0], ["m1", 1, "m2", 1],
			["s0", 0, "m3", 0], ["m2", 0, "m3", 1],
			["m3", 0, "m1", 0], ["m1", 0, "m0", 0], ["m0", 0, "g", 0]],
		p = [["m0", 1, "A"], ["m1", 1, "B"]]},
	&"l11": {m = [&"or_intro"],
		w = [["s0", 0, "m0", 0], ["m0", 0, "g", 0]], p = [["m0", 0, "B"]]},
	&"l12": {m = [&"or_elim", &"or_intro", &"or_intro"],
		w = [["s0", 0, "m0", 0],
			["m0", 1, "m1", 0], ["m1", 1, "m0", 1],
			["m0", 2, "m2", 0], ["m2", 0, "m0", 2],
			["m0", 0, "g", 0]],
		p = [["m1", 1, "B"], ["m2", 0, "A"]]},
	&"l13": {m = [&"imp_intro", &"or_elim", &"and_elim", &"imp_elim", &"imp_elim"],
		w = [["s0", 0, "m2", 0],
			["m0", 1, "m1", 0],
			["m2", 0, "m3", 0], ["m1", 1, "m3", 1], ["m3", 0, "m1", 1],
			["m2", 1, "m4", 0], ["m1", 2, "m4", 1], ["m4", 0, "m1", 2],
			["m1", 0, "m0", 0], ["m0", 0, "g", 0]],
		p = [["m0", 1, "A | B"]]},
	&"l14": {m = [&"false_elim"],
		w = [["s0", 0, "m0", 0], ["m0", 0, "g", 0]], p = [["m0", 0, "A"]]},
	&"l15": {m = [&"imp_intro", &"imp_intro", &"imp_elim", &"imp_elim"],
		w = [["s0", 0, "m2", 0], ["m1", 1, "m2", 1],
			["m0", 1, "m3", 0], ["m2", 0, "m3", 1],
			["m3", 0, "m1", 0], ["m1", 0, "m0", 0], ["m0", 0, "g", 0]],
		p = [["m0", 1, "B > false"], ["m1", 1, "A"]]},
	&"l16": {m = [&"and_elim", &"imp_elim", &"false_elim"],
		w = [["s0", 0, "m0", 0],
			["m0", 1, "m1", 0], ["m0", 0, "m1", 1],
			["m1", 0, "m2", 0], ["m2", 0, "g", 0]], p = [["m2", 0, "B"]]},
}


## 在 scene 上按解法执行(palette 同款放置 + 编辑器路径钉纹样 + session.connect_wire 接线;
## 连线不再借用棋盘的 connection_request 处理器 —— 那边是 GraphEdit 图口号,封程机与模型口号不同)
static func apply(scene: LevelScene, board: ProofBoard, level_id: StringName) -> bool:
	if not DATA.has(level_id):
		return false
	var sol: Dictionary = DATA[level_id]
	var session := scene.session
	var machines: Array[int] = []
	for i in (sol.m as Array).size():
		board.place_machine_at_center(sol.m[i])
		var id: int = session.get_node_ids()[-1]
		machines.append(id)
		session.set_node_position(id, Vector2(600 + 400 * i, 180 + 320 * (i % 3)))   # 4K 逻辑坐标,避开左列线轴
	board.apply_positions()
	for pin: Array in sol.p:
		var target: int = machines[int(String(pin[0]).substr(1))]
		scene._on_pin_requested(target, pin[1])
		var e: PatternEditor = scene._editor
		e.tree = FormulaParser.parse(pin[2])
		e.pattern_committed.emit(e.tree)
		e.hide()
	for w: Array in sol.w:
		var from_id := _resolve(w[0], session, machines)
		var to_id := _resolve(w[2], session, machines)
		session.connect_wire(from_id, w[1], to_id, w[3])
	return true


static func _resolve(ref: String, session: ProofSession, machines: Array[int]) -> int:
	if ref == "g":
		return session.goal_id
	if ref.begins_with("s"):
		return session.assumption_ids[int(ref.substr(1))]
	return machines[int(ref.substr(1))]
