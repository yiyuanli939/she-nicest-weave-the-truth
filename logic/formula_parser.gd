class_name FormulaParser
extends RefCounted
## 公式文本 ↔ Formula 的唯一转换器。关卡 .tres、存档、测试全走这一种格式。
##
## 语法:
##   原子:  字母开头的标识符,如 A、Rain
##   元变量: ? 后跟标识符或数字,如 ?P、?17(存档里会出现;关卡文件一般用不到)
##   ⊥:     写作 false 或 ⊥
##   连接词: &(合取) |(析取) >(蕴含);优先级 & 高于 | 高于 >,> 右结合
##   括号:  任意
## 例:  "A & B > C | D"  解析为  (A∧B) → (C∨D)

static var last_error: String = ""   ## parse 返回 null 时,这里是人类可读的原因


## 解析失败返回 null(原因见 last_error)
static func parse(src: String) -> Formula:
	last_error = ""
	var tokens := _tokenize(src)
	if tokens.is_empty():
		last_error = "空输入"
		return null
	var state := {"tokens": tokens, "pos": 0}
	var f := _parse_imp(state)
	if f == null:
		return null
	if state.pos < tokens.size():
		last_error = "位置 %d 处有多余内容: %s" % [state.pos, tokens[state.pos]]
		return null
	return f


## 带最少括号的人类可读输出,保证 parse(to_text(f)).equals(f)
static func to_text(f: Formula) -> String:
	match f.kind:
		Formula.Kind.ATOM: return String(f.name)
		Formula.Kind.META: return "?" + String(f.name)
		Formula.Kind.BOT:  return "false"
		Formula.Kind.AND:  return _child(f.left, 3, false) + " & " + _child(f.right, 3, true)
		Formula.Kind.OR:   return _child(f.left, 2, false) + " | " + _child(f.right, 2, true)
		Formula.Kind.IMP:  return _child(f.left, 1, true) + " > " + _child(f.right, 1, false)
	return ""


# ---- 输出侧:按优先级决定要不要加括号 ----

## & 和 | 按左结合打印(右子同级要括号);> 右结合(左子同级要括号)。
## tight = 该侧同优先级时是否必须加括号。
static func _child(f: Formula, parent_prec: int, tight: bool) -> String:
	var p := _prec(f)
	if p < parent_prec or (tight and p == parent_prec):
		return "(" + to_text(f) + ")"
	return to_text(f)


static func _prec(f: Formula) -> int:
	match f.kind:
		Formula.Kind.IMP: return 1
		Formula.Kind.OR:  return 2
		Formula.Kind.AND: return 3
	return 9   # 叶子永远不用括号


# ---- 解析侧:词法 + 递归下降 ----

static func _tokenize(src: String) -> Array[String]:
	var out: Array[String] = []
	var i := 0
	while i < src.length():
		var c := src[i]
		if c == " " or c == "\t" or c == "\n":
			i += 1
		elif c in ["&", "|", ">", "(", ")"]:
			out.append(c)
			i += 1
		elif c == "⊥":
			out.append("false")
			i += 1
		elif c == "?":
			var j := i + 1
			while j < src.length() and _is_word(src[j]):
				j += 1
			out.append(src.substr(i, j - i))   # 含 "?" 前缀
			i = j
		elif _is_word(c):
			var j := i + 1
			while j < src.length() and _is_word(src[j]):
				j += 1
			out.append(src.substr(i, j - i))
			i = j
		else:
			out.append("!bad:" + c)   # 交给解析侧报错
			i += 1
	return out


static func _is_word(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"


# 每层对应一个优先级;state = {tokens, pos}

static func _parse_imp(state: Dictionary) -> Formula:   # 最低优先级,右结合
	var lhs := _parse_or(state)
	if lhs == null:
		return null
	if _peek(state) == ">":
		state.pos += 1
		var rhs := _parse_imp(state)   # 递归到自身 → 右结合
		return Formula.imp(lhs, rhs) if rhs != null else null
	return lhs


static func _parse_or(state: Dictionary) -> Formula:
	var lhs := _parse_and(state)
	if lhs == null:
		return null
	while _peek(state) == "|":
		state.pos += 1
		var rhs := _parse_and(state)
		if rhs == null:
			return null
		lhs = Formula.disj(lhs, rhs)
	return lhs


static func _parse_and(state: Dictionary) -> Formula:
	var lhs := _parse_primary(state)
	if lhs == null:
		return null
	while _peek(state) == "&":
		state.pos += 1
		var rhs := _parse_primary(state)
		if rhs == null:
			return null
		lhs = Formula.conj(lhs, rhs)
	return lhs


static func _parse_primary(state: Dictionary) -> Formula:
	var t := _peek(state)
	if t == "":
		last_error = "位置 %d 处缺少公式" % state.pos
		return null
	if t == "(":
		state.pos += 1
		var inner := _parse_imp(state)
		if inner == null:
			return null
		if _peek(state) != ")":
			last_error = "位置 %d 处缺少右括号" % state.pos
			return null
		state.pos += 1
		return inner
	if t == "false":
		state.pos += 1
		return Formula.bot()
	if t.begins_with("?") and t.length() > 1:
		state.pos += 1
		return Formula.meta(StringName(t.substr(1)))
	if _is_word(t[0]) and not (t[0] >= "0" and t[0] <= "9"):
		state.pos += 1
		return Formula.atom(StringName(t))
	last_error = "位置 %d 处的记号无法识别: %s" % [state.pos, t]
	return null


static func _peek(state: Dictionary) -> String:
	return state.tokens[state.pos] if state.pos < state.tokens.size() else ""
