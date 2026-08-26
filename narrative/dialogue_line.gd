class_name DialogueLine
extends Resource
## 一句台词。策划在 Inspector 里直接编辑;robot_cue 是机器人联动接口:
## 播到该行时触发实体小机器人动作(见 docs/CONTENT_INTERFACE.md 的 cue 一览)。

@export var speaker: String = ""
@export_multiline var text: String = ""      # 支持 BBCode
@export var side_right: bool = false         # 立绘/名牌靠右
@export var robot_cue: String = ""           # ""=无;如 "happy"/"panic"/"nod"
