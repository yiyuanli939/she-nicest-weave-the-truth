class_name LevelDef
extends Resource
## 一关的全部配置。策划改关卡 = 在 Inspector 改这些字段(见 docs/CONTENT_INTERFACE.md)。
## 公式一律用 FormulaParser 文本格式:`&` `|` `>`、`false`=⊥。

@export var id: StringName
@export var title: String = ""
@export var assumptions: Array[String] = []
@export var goal: String = ""
@export var allowed_rules: Array[StringName] = []
@export var atoms: Array[StringName] = []             # 纹样编辑器可用的原子
@export var atom_colors: Dictionary = {}              # 留空 → 用默认三色/hash 回退
@export var allow_bot: bool = false                   # 纹样编辑器解锁焦纹笔刷
@export var intro_dialogue: DialogueRes
@export var robot_cue_on_enter: String = ""           # 进关机器人动作(如 "glitch";当前无关卡使用)
@export var robot_cue_on_win: String = ""             # 通关机器人动作(默认 celebrate)

# 低饱和高明度(S≈0.38-0.40, V≈0.74-0.88),与 UI 主色(藕粉/棕红/乳黄/黄铜)协调
const DEFAULT_COLORS: Dictionary = {
	&"A": Color(0.88, 0.57, 0.53),   # 藕粉陶土红
	&"B": Color(0.52, 0.67, 0.84),   # 灰蓝
	&"C": Color(0.46, 0.74, 0.55),   # 豆青
	&"D": Color(0.78, 0.51, 0.78),   # 紫藕(原蜜金与亚麻底/黄铜撞色,换相;暂无关卡使用)
}


## 实际使用的调色板:显式配置优先,常用原子给默认色,其余 PatternView hash 回退
func effective_colors() -> Dictionary:
	var out := {}
	for a in atoms:
		if atom_colors.has(a):
			out[a] = atom_colors[a]
		elif DEFAULT_COLORS.has(a):
			out[a] = DEFAULT_COLORS[a]
	return out
