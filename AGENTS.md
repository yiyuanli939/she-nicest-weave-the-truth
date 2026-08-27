# AGENTS.md — She Nicest 开发指南

Godot 4.7 自然演绎解谜游戏:复刻 [The Incredible Proof Machine](https://incredible.pm/),
换皮为维多利亚纺织世界(命题=纹样,推理规则=黄铜仪器)。

**先读这两份**:
- `plan.md` — 完整开发计划 + Godot 教学(架构、算法、里程碑、素材方案都在这)
- `information/自然演绎游戏提案.pdf` — 游戏设定与美术方向

## 常用命令

```bash
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

# 跑测试(退出码 = 失败数;改完 logic/ 必跑)
"$GODOT" --headless --path . --script res://tests/run_tests.gd

# 新增/改名了 class_name 之后,先重建全局类缓存再跑测试
"$GODOT" --headless --path . --import

# 跑游戏(M1 设好 main_scene 之后可用)
"$GODOT" --path .
```

## 架构与硬规则

**Model/View 严格分离**:`logic/` 是纯 GDScript 逻辑层(全部 `extends RefCounted` +
`class_name`,禁止引用任何 Node/场景),`ProofGraph` 是唯一 source of truth;
UI 只通过 `ProofGraph.solve()` 返回的 `SolveResult` 刷新。

1. **Formula 不可变**:构造后不改字段;变换返回新树;相等用 `equals()`,禁止 `==` 比引用。
2. **元变量防捕获**:放置机器必须走 `add_rule_node`(内部 `rename_metas` 发新鲜名);
   禁止直接使用 `Rules` 表里的模板 Formula 对象。
3. **公式文本只有一种格式**:`FormulaParser.parse/to_text`(`&` `|` `>`,`false`=⊥,
   `>` 右结合,`?名字`=元变量)。关卡、存档、测试统一用它。
4. **GraphEdit 收口**(M1 起):所有 GraphEdit/GraphNode API 只许出现在
   `board/proof_board.gd` 与 `board/machine_node.gd`;连线合法性由 ProofGraph 裁决。
5. 信号用代码连(`sig.connect(_on_x)`),不用编辑器连线。
6. 缩进 Tab;文件 snake_case、类 PascalCase;一个文件一个 `class_name`。

## 代码地图(M0 已完成 ✅)

| 文件 | 职责 |
|---|---|
| `logic/formula.gd` | 命题 AST(不可变;`key()` 规范串 = 相等/哈希/序列化基础) |
| `logic/formula_parser.gd` | 公式文本 ↔ AST(递归下降;`to_text` 保证往返) |
| `logic/rule_schema.gd` | 仪器模式:端口模板 + 假设口(`is_hypothesis`/`scope_input`) |
| `logic/rules.gd` | 八台仪器规则表(id 与 incredible.pm 规则名对应) |
| `logic/unifier.gd` | 一阶合一(occurs check;union-find 式 walk/resolve) |
| `logic/proof_graph.gd` | 棋盘模型 + solve 五步管线(方程→合一→环→辖域→胜负) |
| `logic/solve_result.gd` | solve 的输出:端口纹样、边状态、缺口、胜负 |
| `tests/` | headless 测试,27 例;`test_base.gd` 提供 `check`/`f("A & B")` |

## 踩过的坑(改这些地方前必读)

- **假设口的边不是依赖**:封程机假设口→子证明→回到本机输入口,在节点图上
  像环但不是循环论证。`_topo_order`/`_propagate_hyps` 已把假设边排除出依赖、
  开局直接赋 `{自己}`。改环检测或辖域检查时别破坏这一点(有测试盯着)。
- **JSON 往返会变类型**:整数→浮点、字典键→字符串。`ProofGraph.from_dict`
  里已统一 `int()` 转回;新增序列化字段时照做。
- **新 class_name 不生效**:命令行跑脚本前需 `--import` 重建缓存(编辑器开着
  的话它会自己扫)。

## 当前进度

M0 引擎 ✅ → API(ProofSession/PatternView)✅ → M1 灰盒板 ✅ → M2 编辑器/全规则 ✅ →
M3 内容层(17 关+存档+对话+笔记本)✅ → 实体机器人联动(固件/桥接/语音/校准)✅ →
交互改版(进关前全屏开场对话 StoryScene、右键删节点、无跳过键点击推进、
连线只留错误徽章、汇路机免手动钉、未连线口幽灵纹样)✅。
剧情台词与 UI 为**占位版**,更新接口见 `docs/CONTENT_INTERFACE.md`、`docs/ART_INTERFACE.md`;
机器人手册见 `docs/ROBOT_API.md`。全流程回归:`tests/visual_smoke_m3.gd`(17 关自动通关)。
