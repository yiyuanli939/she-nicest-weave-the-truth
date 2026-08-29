class_name NotebookEntry
extends Resource
## 笔记本条目 = 一张整页图(标题/正文全画在图里,引擎不渲染文字)。
## image = assets/art/level/notebook/<rule_id>.png,3840×2160 全屏导出、透明底,与打开的抽屉对齐。

@export var id: StringName
@export var image: String = ""      # 整页图 res:// 路径(NotebookUI 原尺寸摆放)
