class_name StepGuide
extends RefCounted
## 关内操作指引:按棋盘状态挑出玩家下一步该做的**操作**,一行字显示在棋盘左下(LevelScene 挂)。
## 每条只在玩家还没做过这个操作时显示,做过一次就记进存档(SaveManager.steps,「重置进度」清掉)。
## 只讲操作(放仪器 / 拉线 / 钉纹样 / 断线拆机 / 翻笔记),不讲逻辑、不提示解法(文案守则同笔记)。
## 纯函数:facts 由 facts_of() 从 ProofSession 查出来,next_step / newly_done 不碰任何 Node,headless 可测。
## 文案改这里的 TEXT;美术之后要换成图或改位置,在 ui/level_scene.gd 顶部 STEP_HINT_* 常量。

const TEXT: Dictionary = {
	&"fix": "这条线接不上:右键点线可以断开,右键点仪器可以把它拆掉",
	&"pin": "有一口的纹样要你自己定:点这台仪器标题栏的钉纹样按钮,画一幅钉上去",
	&"place": "从左边的仪器架点一台仪器,它会落在织案中央",
	&"wire": "按住线轴或仪器的出口往外拖出一条线,接到下一台仪器或目标织机的入口",
	&"notebook": "仪器架上来了新仪器,右缘的「笔记」里有它的用法",
}
## 优先级:先解决眼前接错的线(fix),再是钉、放、拉、翻笔记;每条做过一次就跳过
const ORDER: Array[StringName] = [&"fix", &"pin", &"place", &"wire", &"notebook"]


## 从会话查出指引需要的事实(视图层调用;facts 是普通字典,测试可直接构造)
static func facts_of(session: ProofSession, has_rack: bool, debut: bool) -> Dictionary:
	var machines := 0
	var unpinned := false
	var pinned := false
	for id in session.get_node_ids():
		var info := session.describe_node(id)
		if info == null or info.type != ProofSession.NodeType.MACHINE:
			continue
		machines += 1
		if not info.pinned.is_empty():
			pinned = true
		for p in info.outputs.size():
			if info.outputs[p].pinnable and not info.pinned.has(p):
				unpinned = true
	var wires := session.get_wires()
	var conflict := false
	for w in wires:
		if w.state == ProofSession.WireState.CONFLICT:
			conflict = true
	return {has_rack = has_rack, machines = machines, wires = wires.size(), conflict = conflict,
			unpinned = unpinned, pinned = pinned, debut = debut, solved = session.is_solved()}


## 当前该显示哪条(空 = 不显示):已通关不显示;done(键 = 操作名字符串)里有的跳过
static func next_step(facts: Dictionary, done: Dictionary) -> StringName:
	if facts.get("solved", false):
		return &""
	for step in ORDER:
		if done.has(String(step)):
			continue
		if _applies(step, facts):
			return step
	return &""


static func _applies(step: StringName, f: Dictionary) -> bool:
	match step:
		&"fix":
			return f.get("conflict", false)
		&"pin":
			return f.get("unpinned", false)
		&"place":
			return f.get("has_rack", false) and f.get("machines", 0) == 0
		&"wire":   # 有机可接、或本关本来就没仪器架(l01 线轴直连目标)
			return f.get("wires", 0) == 0 and (f.get("machines", 0) > 0 or not f.get("has_rack", false))
		&"notebook":
			return f.get("debut", false)
	return false


## 由棋盘事实推断"玩家已经做过"的操作(翻笔记由 UI 自己报);prev = 上一次的事实,用来看出断线/拆机
static func newly_done(prev: Dictionary, facts: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	if facts.get("machines", 0) > 0:
		out.append(&"place")
	if facts.get("wires", 0) > 0:
		out.append(&"wire")
	if facts.get("pinned", false):
		out.append(&"pin")
	if prev.get("conflict", false) and (facts.get("wires", 0) < prev.get("wires", 0)
			or facts.get("machines", 0) < prev.get("machines", 0)):
		out.append(&"fix")
	return out
