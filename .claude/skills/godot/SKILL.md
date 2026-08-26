---
name: godot
description: She Nicest 项目的 Godot 4.7 开发约定 — GDScript 风格、Model/View 分离规则、headless 运行与测试命令、GraphEdit 收口规范。实现、调试、测试本工程任何代码前加载。
---

# Godot 4.7 项目约定(She Nicest)

总蓝本见仓库根目录 `plan.md`(含完整架构、算法细节与 Godot 教学);本 skill 只收录实现时每次都要遵守的硬规则与命令。

## 运行与测试命令

```bash
# macOS 的 Godot 可执行文件(如路径不同,用 `mdfind -name Godot.app` 找)
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

"$GODOT" --path /Users/yiyuanli/she-nicest                # 跑游戏(需已设 main_scene)
"$GODOT" --headless --path /Users/yiyuanli/she-nicest \
         --script res://tests/run_tests.gd                # headless 测试;退出码 = 失败数
"$GODOT" --headless --path /Users/yiyuanli/she-nicest \
         --check-only --script res://logic/formula.gd     # 仅语法/类型检查单脚本
```

改完逻辑层必跑 headless 测试;改 UI 后用 `--path` 实跑对应里程碑验收项(见 plan.md 各节末)。

## 硬规则

1. **Model/View 分离**:`res://logic/` 全部 `extends RefCounted` + `class_name`,禁止 import/引用任何场景、Node、Control;UI 永远通过 `ProofGraph.solve()` 返回的 `SolveResult` 刷新,禁止在 view 层存逻辑状态。
2. **GraphEdit 收口**:所有 GraphEdit/GraphNode API 调用只允许出现在 `board/proof_board.gd` 与 `board/machine_node.gd`;连线合法性(单输入口单线、自环、类型)一律由 ProofGraph 裁决后才 `connect_node`。
3. **Formula 不可变**:构造后不改字段;任何变换(subst/rename_metas)返回新树;相等用 `equals()`(即 `key()` 串比较),禁止 `==` 比引用。
4. **元变量防捕获**:放置机器时必须经 `rename_metas` 用全局计数器发新鲜名;禁止直接使用 `Rules` 表里的 schema 模板 Formula 对象。
5. **信号用代码连**(`sig.connect(_on_x)`),不用编辑器连线,便于 review。
6. **公式文本格式统一**:关卡 .tres、存档、测试全部走 `FormulaParser.parse/to_text`(`&` `|` `>`、`false`=⊥;`>` 右结合)。

## GDScript 风格

- Godot 4 语法:`@export`/`@onready`、typed 声明(`var x: int`、`-> void`)、`StringName` 字面量 `&"imp_intro"`。
- 文件名 snake_case,类名 PascalCase;一个文件一个 `class_name`。
- 缩进用 Tab(Godot 默认);注释只写代码本身说不出的约束。
- 版本钉死 4.7;不使用已废弃 API(GraphEdit 4.2 起大改名,以 stable 文档为准)。

## 目录速查

`logic/` 引擎(纯脚本)· `pattern/` 纹样渲染与编辑 · `board/` GraphEdit 证明板 · `levels/` 关卡 .tres · `narrative/` 对话/笔记本 · `game/` autoload Game、存档、undo · `ui/` 菜单/选关/关卡场景 · `tests/` headless 测试 · `assets/` svg/fonts/shaders · `theme/` main_theme.tres
