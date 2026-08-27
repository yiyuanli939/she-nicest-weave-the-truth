class_name Unifier
extends RefCounted
## 一阶合一器:给一组方程 "左式 ≐ 右式",求出让所有方程成立的元变量赋值。
## 这是证明机的心脏。棋盘求解走的是单向的 match_into(上游纹样灌进下游模板,
## 只绑下游变量,绝不反推上游);对称的 solve/unify_one 保留作通用原语。
##
## 实现风格(union-find 式,规避两类经典 bug):
##   * 绑定只写入 subst,从不回代修改已有绑定;
##   * 读取时用 walk 追到代表元,最终用 resolve 一次性完全展开。
##
## 失败的方程记入 conflicts 后丢弃、继续处理后面的方程 —— 这样冲突定位
## 顺序稳定(按方程插入序),UI 的错误标记不会闪变,剩余连线也仍能推导。


## eqs 的每项是 [Formula, Formula]。
## 返回 { "subst": {元变量名: Formula}, "conflicts": [失败方程的下标...] }
static func solve(eqs: Array) -> Dictionary:
	var subst: Dictionary = {}
	var conflicts: Array[int] = []
	for i in eqs.size():
		if not unify_one(eqs[i][0], eqs[i][1], subst):
			conflicts.append(i)
	return {"subst": subst, "conflicts": conflicts}


## 合一一条方程,绑定写入 subst。失败返回 false(subst 可能已含部分绑定,
## 属可接受行为:后续方程照常处理,错误已归因到本条)。
static func unify_one(a: Formula, b: Formula, subst: Dictionary) -> bool:
	a = walk(a, subst)
	b = walk(b, subst)
	if a.kind == Formula.Kind.META and b.kind == Formula.Kind.META and a.name == b.name:
		return true
	if a.kind == Formula.Kind.META:
		return _bind(a, b, subst)
	if b.kind == Formula.Kind.META:
		return _bind(b, a, subst)
	if a.kind != b.kind:
		return false
	match a.kind:
		Formula.Kind.ATOM:
			return a.name == b.name
		Formula.Kind.BOT:
			return true
		_:
			return unify_one(a.left, b.left, subst) and unify_one(a.right, b.right, subst)


## 单向匹配:把上游的 value 灌进下游的 template,只允许绑定 allowed 里的元变量
## (下游节点自己的);value 里未定的元变量视为刚性、直接跳过(上游还没织好,
## 不算冲突,最终由"不 ground"判为欠定)。只有两侧都是具体结构且对不上才返回 false。
##
## 判断顺序是有意的:先看 template 侧可绑(哪怕 value 也是元变量,照样绑成别名链,
## 这样上游之后织好了下游会自动跟着展开),再看 value 侧刚性跳过。
static func match_into(value: Formula, template: Formula, subst: Dictionary, allowed: Dictionary) -> bool:
	value = walk(value, subst)
	template = walk(template, subst)
	if template.kind == Formula.Kind.META and allowed.has(template.name):
		if value.kind == Formula.Kind.META and value.name == template.name:
			return true
		return _bind(template, value, subst)
	if value.kind == Formula.Kind.META:
		return true
	if template.kind == Formula.Kind.META:
		return true   # 经绑定链引入的外来元变量(别的节点的),不归本边绑
	if value.kind != template.kind:
		return false
	match value.kind:
		Formula.Kind.ATOM:
			return value.name == template.name
		Formula.Kind.BOT:
			return true
		_:
			return match_into(value.left, template.left, subst, allowed) \
				and match_into(value.right, template.right, subst, allowed)


## 元变量沿绑定链追到代表元(只追顶层,不深入子树)
static func walk(f: Formula, subst: Dictionary) -> Formula:
	while f.kind == Formula.Kind.META and subst.has(f.name):
		f = subst[f.name]
	return f


## 完全展开:树里每个已绑定的元变量都替换成最终值
static func resolve(f: Formula, subst: Dictionary) -> Formula:
	f = walk(f, subst)
	match f.kind:
		Formula.Kind.AND:
			return Formula.conj(resolve(f.left, subst), resolve(f.right, subst))
		Formula.Kind.OR:
			return Formula.disj(resolve(f.left, subst), resolve(f.right, subst))
		Formula.Kind.IMP:
			return Formula.imp(resolve(f.left, subst), resolve(f.right, subst))
		_:
			return f


## occurs check:禁止 ?a ≐ ?a∧B 这类自包含绑定,否则会造出无限纹样。
## 检查对象是 val 的完全展开形(经由链条间接自包含也要抓到)。
static func _bind(m: Formula, val: Formula, subst: Dictionary) -> bool:
	if resolve(val, subst).contains_meta(m.name):
		return false
	subst[m.name] = val
	return true
