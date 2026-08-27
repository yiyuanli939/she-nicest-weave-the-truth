class_name RuleGuide
extends Resource
## 一台仪器的介绍卡(点选机器时弹出)。内容占位,策划在 Inspector 或 gen_levels 表里改。
## rule_id 对应 logic/rules.gd 的仪器 id;demo_formula 用 PatternView 现场渲染一个示例纹样。

@export var rule_id: StringName
@export var title: String = ""              # 展示名(默认用仪器中文名)
@export var summary: String = ""            # 一句话用途
@export_multiline var body: String = ""     # 详解,支持 BBCode
@export var demo_formula: String = ""       # 示例公式,空则不画
