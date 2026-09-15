class_name NotebookEntry
extends Resource
## 笔记本条目 = 可本地化标题与正文 + 独立透明图示。
## NotebookUI 在纸张安全区内自动纵向排列，译文过长时只在纸内滚动。

@export var id: StringName
@export var title: String = ""
@export_multiline var description: String = ""
@export var image: String = ""      # 图示 res:// 路径(NotebookUI 原尺寸居中摆放)
