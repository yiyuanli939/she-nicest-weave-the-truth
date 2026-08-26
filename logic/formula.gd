class_name Formula
extends RefCounted
## 命题公式的语法树(AST)。这是整个逻辑引擎的基础数据结构。
##
## 一个 Formula 是下面六种之一:
##   ATOM  原子命题(游戏里的一种纯色静语丝),如 A、B
##   META  元变量(游戏里的"未染纱"):尚未确定的命题,由合一器求解
##   AND   合取 A∧B(并织纹:左右竖分)
##   OR    析取 A∨B(岔纹:对角分)
##   IMP   蕴含 A→B(迭层纹:上下横分)
##   BOT   ⊥ 矛盾(焦纹:烧毁的布)
##
## 设计约定(硬规则,见 .claude/skills/godot):
##   1. 不可变:构造后不改字段;subst / rename_metas 都返回新树。
##   2. 相等 = key() 规范串相等。key 同时用作 Dictionary 键与序列化格式的基础。

enum Kind { ATOM, META, AND, OR, IMP, BOT }

var kind: int
var name: StringName        ## ATOM/META 的名字;META 的名字不含 "?" 前缀(如 "P"、"17")
var left: Formula           ## AND/OR/IMP 的左子式(IMP 的前件)
var right: Formula          ## AND/OR/IMP 的右子式(IMP 的后件)

var _key: String            ## key() 的惰性缓存


func _init(p_kind: int, p_name: StringName = &"", p_left: Formula = null, p_right: Formula = null) -> void:
	kind = p_kind
	name = p_name
	left = p_left
	right = p_right


# ---- 构造工厂(统一用这些,别直接 new) ----

static func atom(n: StringName) -> Formula:
	return Formula.new(Kind.ATOM, n)


static func meta(n: StringName) -> Formula:
	return Formula.new(Kind.META, n)


static func conj(a: Formula, b: Formula) -> Formula:
	return Formula.new(Kind.AND, &"", a, b)


static func disj(a: Formula, b: Formula) -> Formula:
	return Formula.new(Kind.OR, &"", a, b)


static func imp(a: Formula, b: Formula) -> Formula:
	return Formula.new(Kind.IMP, &"", a, b)


static func bot() -> Formula:
	return Formula.new(Kind.BOT)


# ---- 相等与查询 ----

## 规范前缀式字符串,如 "&(A,>(B,?3))"。
## META 前缀 "?"、BOT 记作 "⊥",都不是合法原子名的字符,所以不会和原子撞名。
func key() -> String:
	if _key.is_empty():
		match kind:
			Kind.ATOM: _key = String(name)
			Kind.META: _key = "?" + String(name)
			Kind.BOT:  _key = "⊥"
			Kind.AND:  _key = "&(%s,%s)" % [left.key(), right.key()]
			Kind.OR:   _key = "|(%s,%s)" % [left.key(), right.key()]
			Kind.IMP:  _key = ">(%s,%s)" % [left.key(), right.key()]
	return _key


func equals(o: Formula) -> bool:
	return o != null and key() == o.key()


func is_binary() -> bool:
	return kind == Kind.AND or kind == Kind.OR or kind == Kind.IMP


## 不含任何元变量 → 纹样可以完全染色(胜利判定的必要条件)
func is_ground() -> bool:
	if kind == Kind.META:
		return false
	if is_binary():
		return left.is_ground() and right.is_ground()
	return true


## 树中出现的全部元变量名(去重,不保证顺序)
func metas() -> Array[StringName]:
	var found: Dictionary = {}
	_collect_metas(found)
	var out: Array[StringName] = []
	for n: StringName in found:
		out.append(n)
	return out


func _collect_metas(found: Dictionary) -> void:
	if kind == Kind.META:
		found[name] = true
	elif is_binary():
		left._collect_metas(found)
		right._collect_metas(found)


func contains_meta(m: StringName) -> bool:
	if kind == Kind.META:
		return name == m
	if is_binary():
		return left.contains_meta(m) or right.contains_meta(m)
	return false


## 嵌套深度(叶子为 0);纹样渲染用它决定分割线粗细
func depth() -> int:
	if is_binary():
		return 1 + maxi(left.depth(), right.depth())
	return 0


# ---- 变换(都返回新树,自身不变) ----

## 把元变量替换成公式:s = {元变量名: Formula}。单遍替换,不递归展开替换结果
## (完全展开由 Unifier.resolve 负责)。
func subst(s: Dictionary) -> Formula:
	match kind:
		Kind.META:
			return s[name] if s.has(name) else self
		Kind.AND:
			return conj(left.subst(s), right.subst(s))
		Kind.OR:
			return disj(left.subst(s), right.subst(s))
		Kind.IMP:
			return imp(left.subst(s), right.subst(s))
		_:
			return self


## 元变量改名:map = {旧名: 新名}。放置机器时用它把模板的 P/Q/R
## 换成全局唯一的新鲜名,保证两台同种机器互不干扰(防捕获)。
func rename_metas(map: Dictionary) -> Formula:
	match kind:
		Kind.META:
			return meta(map[name]) if map.has(name) else self
		Kind.AND:
			return conj(left.rename_metas(map), right.rename_metas(map))
		Kind.OR:
			return disj(left.rename_metas(map), right.rename_metas(map))
		Kind.IMP:
			return imp(left.rename_metas(map), right.rename_metas(map))
		_:
			return self
