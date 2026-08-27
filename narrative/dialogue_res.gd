class_name DialogueRes
extends Resource
## 一段线性对话(进关前在全屏对话场景播)。
## location_title/background 是场景级美术槽位:空/null 时 StoryScene 用程序化占位。

@export var lines: Array[DialogueLine] = []
@export var location_title: String = ""       # 地点铭牌;"" = 回退关卡标题
@export var background: Texture2D = null      # 背景插图;null = 程序化占位
