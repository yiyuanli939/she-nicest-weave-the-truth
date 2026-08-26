class_name Rules
extends RefCounted
## 全部八台仪器的规则表。id 与 incredible.pm 的规则名对应,方便对照原版关卡。
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

	# 析取:岔纹机(两个输出口用不同的模式变量,各自独立可用)/ 汇路机
	_add(&"or_intro", "岔纹机").inp(P) \
		.out(Formula.disj(P, Q)).out(Formula.disj(R, P))
	_add(&"or_elim", "汇路机") \
		.inp(Formula.disj(P, Q)).inp(R).inp(R) \
		.out(R).hyp(P, 1).hyp(Q, 2)

	# 蕴含:封程机 / 引渡机
	_add(&"imp_intro", "封程机").inp(Q) \
		.out(Formula.imp(P, Q)).hyp(P, 0)
	_add(&"imp_elim", "引渡机").inp(Formula.imp(P, Q)).inp(P) \
		.out(Q)

	# ⊥:溃散机(爆炸原理:烧毁的布能织出任何纹样)
	_add(&"false_elim", "溃散机").inp(Formula.bot()) \
		.out(P)

	# 经典逻辑:两仪机(排中律,第五章才解锁)
	_add(&"tnd", "两仪机") \
		.out(Formula.disj(P, Formula.imp(P, Formula.bot())))


static func _add(id: StringName, cn_name: String) -> RuleSchema:
	var r := RuleSchema.new(id, cn_name)
	_table[id] = r
	return r
