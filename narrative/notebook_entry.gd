class_name NotebookEntry
extends Resource
## 笔记本条目(同构揭示等)。demo_formula 用 PatternView 现场渲染。

@export var id: StringName
@export var title: String = ""
@export_multiline var body: String = ""      # BBCode
@export var demo_formula: String = ""        # 公式文本,空则不画
