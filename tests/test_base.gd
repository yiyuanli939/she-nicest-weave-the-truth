class_name TestBase
extends RefCounted
## 测试基类:两个小工具。测试方法约定以 test_ 开头、返回 bool(true = 通过)。


## 断言:失败时打印原因并返回 false;配合 and 串联,一个失败整个方法失败
func check(cond: bool, msg: String) -> bool:
	if not cond:
		print("    断言失败: " + msg)
	return cond


## 公式速记:f("A & B") —— 测试里所有公式都这样写,顺便天天锻炼解析器
func f(src: String) -> Formula:
	var r := FormulaParser.parse(src)
	assert(r != null, "测试公式写错了: %s (%s)" % [src, FormulaParser.last_error])
	return r
