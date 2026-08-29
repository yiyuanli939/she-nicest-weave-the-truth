class_name DialogueLine
extends Resource
## 一句台词。策划在 Inspector 里改,或用 tools/import_dialogue.gd 从 Excel 另存的 CSV 整表灌入。
## 角色 / 表情 / 场景一律写美术给的中文名(登记表与可用值见 narrative/story_art.gd);
## 主角诺拉恒在右侧立绘位,发言人是否诺拉由 StoryArt.is_nora(speaker) 判定。

@export var speaker: String = ""            # 发言人显示名,如 "诺拉·拉弗蒂" / "莉娅"
@export_multiline var text: String = ""     # 台词,支持 BBCode
@export var scene: String = ""              # 场景插图:工坊 / 宿舍 / 街景;"" = 沿用上一句
@export var left_char: String = ""          # 左侧人物:莉娅 / 亚瑟;"" = 左侧无人
@export var left_expr: String = "默认"      # 左侧人物表情
@export var nora_expr: String = "默认"      # 诺拉表情:默认 / 苦恼 / 严肃 / 惊讶
@export var robot_cue: String = ""          # 播到本句触发的实体小机动作(见 docs/CONTENT_INTERFACE.md);"" = 无
