class_name Rules
extends RefCounted
## 全部七台仪器的规则表。id 与 incredible.pm 的规则名对应,方便对照原版关卡。
##
## 读法示例(封程机 = 蕴含引入):
##   输入口:Q(要求玩家用"假设了 P 的子证明"织出 Q)
##   输出口:P→Q(封装完成的迭层纹)
##   假设口:P,scope_input=0(P 只许用在汇入 0 号输入口的子证明里)

static var _table: Dictionary = {}     # StringName -> RuleSchema


static func get_rule(id: StringName) -> RuleSchema:
	if _table.is_empty():
		_build()
	return _table.get(id)


static func all_ids() -> Array:
	if _table.is_empty():
		_build()
	return _table.keys()


static func _build() -> void:
	var P := Formula.meta(&"P")
	var Q := Formula.meta(&"Q")
	var R := Formula.meta(&"R")

	# 合取:并织机 / 拆股机
	_add(&"and_intro", "并织机").inp(P).inp(Q) \
		.out(Formula.conj(P, Q))
	_add(&"and_elim", "拆股机").inp(Formula.conj(P, Q)) \
		.out(P).out(Q)

	# 析取:岔纹机(两个输出口各带一个自由变量:上口另一支 Q、下口另一支 R,由玩家钉)
	#       / 汇路机(P、Q 由 0 号入口的 P∨Q 正向决定,R 由两条支路正向决定,无可钉口)
	_add(&"or_intro", "岔纹机").inp(P) \
		.out(Formula.disj(P, Q), true).out(Formula.disj(R, P), true)
	_add(&"or_elim", "汇路机") \
		.inp(Formula.disj(P, Q)).inp(R).inp(R) \
		.out(R).hyp(P, 1).hyp(Q, 2)

	# 蕴含:封程机(假设 P 自由,玩家钉)/ 引渡机
	_add(&"imp_intro", "封程机").inp(Q) \
		.out(Formula.imp(P, Q)).hyp(P, 0, true)
	_add(&"imp_elim", "引渡机").inp(Formula.imp(P, Q)).inp(P) \
		.out(Q)

	# ⊥:溃散机(爆炸原理:烧毁的布能织出任何纹样 —— 织什么由玩家钉)
	_add(&"false_elim", "溃散机").inp(Formula.bot()) \
		.out(P, true)


static func _add(id: StringName, cn_name: String) -> RuleSchema:
	var r := RuleSchema.new(id, cn_name)
	_table[id] = r
	return r
