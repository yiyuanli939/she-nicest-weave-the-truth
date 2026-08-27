class_name RuleGuideCatalog
extends Resource
## 全部仪器介绍卡的登记表。按 rule_id 查;查不到返回 null(视图侧回退到中文机名)。

@export var entries: Array[RuleGuide] = []


static func load_default() -> RuleGuideCatalog:
	return load("res://narrative/data/rule_guide.tres")


func guide(rule_id: StringName) -> RuleGuide:
	for e in entries:
		if e.rule_id == rule_id:
			return e
	return null
