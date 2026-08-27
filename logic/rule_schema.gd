class_name RuleSchema
extends RefCounted
## 一台"仪器"(推理规则)的模式定义:有哪些输入口、输出口,各口的命题模板。
##
## 模板里的元变量(P、Q、R)是"模式变量":每放置一台机器,ProofGraph 会把
## 它们统一换成全局新鲜的元变量,所以这里的 Formula 对象只是蓝图,
## 绝不能直接接到棋盘上(硬规则 4)。
##
## 局部假设口(is_hypothesis):封程机/汇路机特有的输出口。它吐出的命题
## 只能用在"最终汇入本机 scope_input 号输入口"的子证明里,越界即
## ESCAPED_HYP 错误 —— 这是自然演绎"假设只在子证明内有效"的图形化表达。
##
## 可钉口(pinnable):模板里含"自由元变量"(不由任何输入口决定)的输出口,
## 由玩家用钉纹样窗口给那个自由变量赋值;求解严格正向,绝不从下游反推。
## 用白名单而不是"含自由变量即可钉":封程机的 P→Q 口也含 P,但钉的入口只放在假设口。

class PortSpec:
	var template: Formula
	var is_hypothesis: bool = false
	var scope_input: int = -1     ## 假设口对应的封存输入口下标(仅假设口有效)
	var pinnable: bool = false    ## 玩家可给本口的自由元变量钉纹样


var id: StringName
var cn_name: String
var inputs: Array[PortSpec] = []
var outputs: Array[PortSpec] = []


func _init(p_id: StringName, p_cn_name: String) -> void:
	id = p_id
	cn_name = p_cn_name


# 链式建口,让 rules.gd 的规则表一行一台机器、直接可读

func inp(template: Formula) -> RuleSchema:
	inputs.append(_port(template))
	return self


func out(template: Formula, p_pinnable := false) -> RuleSchema:
	var p := _port(template)
	p.pinnable = p_pinnable
	outputs.append(p)
	return self


func hyp(template: Formula, p_scope_input: int, p_pinnable := false) -> RuleSchema:
	var p := _port(template)
	p.is_hypothesis = true
	p.scope_input = p_scope_input
	p.pinnable = p_pinnable
	outputs.append(p)
	return self


static func _port(template: Formula) -> PortSpec:
	var p := PortSpec.new()
	p.template = template
	return p
