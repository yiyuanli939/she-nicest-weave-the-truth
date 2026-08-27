# She Nicest 设计与改法教程

面向接手的人:先讲整体怎么搭的、每层管什么,再讲最近两轮改了什么、为什么,最后是"想改 X 去哪改"的速查。
硬规则与命令在 `AGENTS.md`,更完整的架构推导在 `plan.md`;本文是把它们串起来的导读。

## 1. 一句话概括

玩家在 GraphEdit 棋盘上把"线轴(前提)"经"仪器(推理规则)"接到"目标织机(结论)";
每个端口显示一幅**纹样**(命题的图形化);求解器判断连线是否成立、证明是否完成。
逻辑复刻 [The Incredible Proof Machine](https://incredible.pm/),皮肤是维多利亚纺织世界。

## 2. 分层结构(自下而上)

```
logic/       纯 GDScript 引擎(RefCounted,零 Node 依赖)   ← 唯一 source of truth
api/         ProofSession(门面 + undo + 信号)、PatternView(纹样哑控件)
board/       ProofBoard(GraphEdit)、MachineNode(GraphNode)、WireOverlay(错误徽章)
pattern/     PatternEditor(挖孔画纹样的钉纹样窗口)
narrative/   DialogueBox(对话框)、DialogueRes/Line(台词数据)、NotebookUI
ui/          MainMenu / LevelSelect / StoryScene(进关前全屏对话)/ LevelScene(关卡)
game/        Game autoload(流程/存档/机器人 cue 转发)、SaveManager、RobotLink
levels/      LevelDef/ChapterDef/LevelCatalog + data/*.tres(生成器产物)
tools/       gen_levels.gd(关卡/笔记本批量生成器)
tests/       headless 单测(run_tests.gd)+ 开窗 smoke(visual_smoke_m2/m3)
```

**数据流只有一个方向**:UI 动作 → `ProofSession` 的编辑函数 → 改 `ProofGraph` → `solve()` →
`SolveResult` → `board_updated` 信号 → 视图全量刷新。视图层不存任何逻辑状态,连线合法性由模型裁决后视图才落地。

### 2.1 logic/ 引擎

| 文件 | 干什么 |
|---|---|
| `formula.gd` | 命题 AST,不可变。`key()` 规范串是相等/哈希/序列化的基础;`metas()`/`is_ground()` 是求解器常用的两个查询 |
| `formula_parser.gd` | 文本 ↔ AST。全项目只有这一种文本格式(`&` `\|` `>` `false`,`?x` 元变量) |
| `rule_schema.gd` | 一台仪器的端口模板。假设口 `is_hypothesis`+`scope_input`;**可钉口 `pinnable`** |
| `rules.gd` | 七台仪器规则表(并织/拆股/岔纹/汇路/封程/引渡/溃散) |
| `unifier.gd` | 合一原语:对称的 `unify_one`(通用)与**单向的 `match_into`**(棋盘求解用) |
| `proof_graph.gd` | 棋盘模型 + `solve()` 管线 + 序列化 |
| `solve_result.gd` | 求解输出:端口纹样、边状态、已连线端口集合、缺口、胜负 |

放置仪器时 `add_rule_node` 把模板里的 P/Q/R 统一换成全局新鲜名(`?1 ?2 …`),所以**不同节点的元变量绝不重名**——
这一点让"某元变量属于哪个节点"可以从端口模板直接算出来,不需要额外存。

### 2.2 solve() 五步管线(当前语义)

1. **钉纹样赋值**:每个 pinned 口找出它的自由元变量(出现在该口、不出现在任何输入口),直接 `subst[k] = 玩家纹样`。
2. **环检测**:Kahn 拓扑排序,假设口发出的边不算依赖(封程机假设口→子证明→回本机输入口不是循环论证);
   环上的边标 `CYCLE` 且不参与下一步传播。
3. **严格正向传播**:反复遍历边,把上游 `resolve` 后的纹样用 `match_into` 灌进下游入口模板,
   **只绑这条边入口模板里的元变量**(按口不按机——汇路机支路口 R 会成为假设 P 的别名,允许整机元变量就能反绑 P);
   上游还没织好的部分刚性跳过;两侧具体结构对不上才标 `CONFLICT`。绑定只增不减,轮数有上界,边按插入序遍历所以冲突归因稳定。
4. **辖域检查**:沿拓扑序传播每条边"搭载"的未封存假设,流进目标的非空 → `ESCAPED_HYP`。
5. **胜利判定**:从目标反向 BFS,祖先子图里每个输入口有线、每条边 OK。

边状态优先级:CONFLICT > CYCLE > ESCAPED_HYP > UNDERSPEC(任一侧 resolve 后仍含元变量)> OK。

### 2.3 钉纹样(pin)模型

- "钉"的对象是**可钉口的自由元变量**,存成 `ProofNode.pinned = {出口下标: Formula}`,序列化时键转字符串、值转文本。
- 封程机假设口 P、溃散机出口 P 整口就是那个变量;岔纹机上口 `P∨Q` 钉的是 Q(另一支)、下口 `R∨P` 钉的是 R。
- 哪些口可钉由 `rules.gd` 里的 `pinnable` **白名单**决定,不是"含自由变量即可钉"(封程机的 `P→Q` 口也含 P,但入口只放在假设口)。
- 汇路机的 P/Q 由 0 号入口的 `P∨Q` 正向决定、R 由两条支路正向决定,所以**没有**可钉口。
- 钉过的口在 `SolveResult.connected_ports` 里算"已连线"→ 视图画实纹样;没线没钉的口画半透明幽灵(`PatternView.ghost`)。

### 2.4 api/ 与视图

- `ProofSession`(Node):`setup/place_machine/connect_wire/disconnect_wire/remove_machine/pin_hypothesis/unpin_hypothesis`
  每个编辑函数都 `_push_undo()` → 改图 → `_notify()`(重解 + 发 `board_rebuilt`/`board_updated`/`proof_completed`)。
  UI 只用它的查询 getter(`get_input_pattern`/`is_input_connected`/`get_wires`/`describe_node`…),**从不直接碰 SolveResult**。
- `ProofBoard`(GraphEdit)与 `MachineNode`(GraphNode)是全项目**唯一**允许出现 GraphEdit API 的两个文件。
  `board_updated` 后:清空连线 → 按 `get_wires()` 重挂 → 每个节点 `refresh()` → `WireOverlay.rebuild()`(只给出错的线挂徽章)。
- `MachineNode`:每行一对(输入口,输出口)单元格;可钉口在标题栏出按钮(单口"钉纹样",岔纹机"钉上口/钉下口");
  右键节点体 → `delete_requested` → 板转 `session.remove_machine`(线轴/目标模型层拒删)。
- `PatternView`:哑控件,给 Formula 画纹样(AND 竖分 / IMP 横分 / OR 对角 / META 斜纹 / BOT 焦纹),`ghost` 用 `self_modulate` 调透明度。

### 2.5 流程与剧情

```
MainMenu → LevelSelect → Game.start_level(lv)
                            ├─ 有 intro_dialogue → StoryScene(全屏:底图+插图+地点铭牌+立绘+对话框)
                            │                         播完 → Game.enter_board()
                            └─ 无 → enter_board() → LevelScene(棋盘 + HUD + 关内 DialogueBox)
LevelScene.proof_completed → Game.notify_solved(记档、解锁笔记本、robot_cue 庆祝)→ "下一关"
```

- `DialogueBox`:打字机 + 点击推进(打字中点=整句显示,显示完点=下一句,最后一句后再点=关闭),没有跳过键;
  每行 `robot_cue` 转发给 `Game.robot_cue` → `RobotLink`(有实机才发)。
- 对话/立绘/背景/地点都是 `LevelDef.intro_dialogue`(`DialogueRes`)里的数据,美术空槽位走程序化占位。
- 关卡与笔记本 .tres 由 `tools/gen_levels.gd` 从表生成,重跑会覆盖。

## 3. 最近两轮改了什么(以及为什么)

### 3.1 交互改版

| 改动 | 落点 | 备注 |
|---|---|---|
| 进关前全屏开场对话 | `ui/story_scene.gd`、`game.gd start_level/enter_board`、`DialogueRes.location_title/background`、`DialogueLine.portrait` | 关内 `DialogueBox` 保留给关内剧情 |
| 删撤销/重做按钮,右键删节点 | `ui/level_scene.gd`、`board/machine_node.gd _gui_input`、`board/proof_board.gd _remove_machine` | 快捷键 Ctrl+Z/Ctrl+Shift+Z 保留;拖线中右键仍是"取消拖线"(`wire_dragging` 标志) |
| 对话去跳过键、点击推进 | `narrative/dialogue_box.gd` | 卡死根因:`visible_characters = -1` 哨兵值让"打字中"判断永真 |
| 连线只留错误徽章 | `board/wire_overlay.gd` | 端口内已有纹样预览,线上不再重复 |
| 未连线口幽灵纹样 | `SolveResult.connected_ports`、`PatternView.ghost`、`MachineNode.refresh` | 区分"推导出的期望"与"实际连入" |

### 3.2 删第五章 + 严格正向求解

**为什么删第五章**:排中律(两仪机 `⊢ P∨(P→⊥)`,零输入)在节点证明里对玩家过于诡异;第四章的矛盾消除已够展开剧情。
删法:`gen_levels.gd` 的表删两行 + `rules.gd` 删 tnd → 重跑生成器 → 手删 `l16/l17.tres` → 测试计数 17→15、5→4 章、8→7 台。
`panic`/`calm` 两个 cue 在关卡里没入口了,但固件和 `tests/robot_smoke.gd` 仍支持,留给策划。

**为什么改正向**:旧求解器把每条边当对称方程做全局合一,下游连线会反过来绑上游元变量——
把岔纹机接到目标 `A∨B` 上,另一支自动变成 B,玩家什么都没决定;汇路机只连一条支路,另一条口也跟着"自动填充"。
用户希望"仪器输出严格只由输入和钉纹样决定",把自由命题的决定权交回玩家,与封程机钉假设的交互统一。

改法(全部在 logic/,视图只改按钮判据):
1. `RuleSchema.PortSpec.pinnable` + `rules.gd` 标 5 个可钉口。
2. `Unifier.match_into(value, template, subst, allowed)`:单向匹配,只绑 `allowed` 里的元变量。
   判断顺序有讲究:**先**看模板侧可绑(值侧是元变量也照绑成别名链,这样上游之后织好了下游自动跟着展开),
   **再**看值侧刚性跳过;occurs check 不能省(环上的边也会进循环)。
3. `ProofGraph.solve()` 第 1-2 步重写成"钉纹样赋值 + 正向不动点";`UNDERSPEC` 改为双侧判定。
4. `pin_hypothesis` 校验从 `is_hypothesis` 改为 `pinnable`;`from_dict` 静默丢弃落在不可钉口上的旧存档钉。
5. 关卡解法补钉:l10 岔纹机上口钉 B、l11 两台岔纹机各钉一支、l13/l15 溃散机钉目标原子。

旧语义下能"白拿"的东西现在必须钉:封程机的假设 P(原本可靠连目标反推)、岔纹机的另一支、溃散机织出的纹样。
没钉时连线显示"? 欠定"徽章、端口是未染纱幽灵——这正是引导玩家去点钉按钮的提示。

### 3.3 审查后修掉的 bug(值得记住的坑)

| 问题 | 根因 | 修法 |
|---|---|---|
| 汇路机支路线能反绑假设 P,冲突徽章随接线顺序漂移 | `match_into` 的允许集给的是整机元变量;支路口 R 绑成 P 的别名后,`walk` 走到 P 就能绑 | 允许集改为**这条边入口模板里**的元变量(`solve()` 里的 `allowed_of`) |
| 坏存档钉了含 `?` 的纹样 → `Unifier.walk` 追自己死循环 | `from_dict` 只查可钉口,不查 ground | `from_dict` 只收"可钉口 + 全染色 + 自由变量唯一"的钉 |
| 真环上的边报 CONFLICT 而非 CYCLE | occurs check 先于环检测触发 | 环检测提前,环上的边不参与传播 |
| 点在对话面板/台词上不推进 | 面板是全屏捕捉层的兄弟,PanelContainer 默认 STOP 吃掉点击 | 去掉捕捉层,`DialogueBox._input` 在输入层截获左键(模态) |
| 右键节点正中不删、左键拖不动 | 行中间的 spacer `Control` 默认 STOP | spacer `mouse_filter = IGNORE` |
| 左键拖节点时按右键会误删手里的节点 | 右键事件发给鼠标焦点节点 | `_gui_input` 里 `button_mask` 含左键则忽略 |
| 旧档在新语义下"已通关但棋盘欠定",没有下一关按钮 | 按钮只在 `_on_win` 显示 | 进关时记档已通关就显示"下一关" |

教训:UI 交互回归要走 `Window.push_input` 的真实输入管线(见 `visual_smoke_m3.gd` 的 `_click`),直接调 `_on_click/_gui_input` 测不出 mouse_filter 这类问题。

## 4. 想改 X,去哪改

| 想做的事 | 去哪 |
|---|---|
| 改台词/立绘/背景/地点 | 关卡 .tres 的 `intro_dialogue`(Inspector),字段见 `docs/CONTENT_INTERFACE.md`;批量改走 `tools/gen_levels.gd` 的 `LEVELS` 表 |
| 加/删关卡或章节 | `tools/gen_levels.gd`(`LEVELS`/`CH_*`/`NOTEBOOK` 表)→ 重跑生成器 → 删孤儿 .tres → 改 `tests/test_levels.gd`、`visual_smoke_m3.gd` 计数 → 在 `tests/level_solutions.gd` 加脚本化解法(含 `p` 钉) |
| 加一台仪器 | `logic/rules.gd` 一行链式定义(自由变量所在口标 `pinnable`)→ `CH_RULES` 放进某章 → 测试 `test_describe_rule_metadata` 的台数 → 解法 |
| 改"钉"的规则(哪些口可钉) | 只改 `rules.gd` 的 `pinnable` 标记;`_port_free_meta` 要求可钉口恰有一个自由变量 |
| 改求解语义 | `logic/proof_graph.gd solve()` + `logic/unifier.gd match_into`;先看 `tests/test_graph.gd` 末尾的正向语义测试和 `test_unifier.test_match_into_is_one_way` |
| 改纹样画法/幽灵透明度 | `api/pattern_view.gd`(`layout()` 是纯函数,`test_pattern_layout` 盯着;`GHOST_ALPHA`) |
| 改节点外观/钉按钮/右键行为 | `board/machine_node.gd`;连线与整板行为在 `board/proof_board.gd` |
| 改错误徽章文字/颜色 | `board/wire_overlay.gd BADGE/BADGE_COLOR` |
| 改全屏对话场景布局/占位色 | `ui/story_scene.gd` 顶部常量与 `_build_ui/_fill_portrait` |
| 改关卡 HUD/快捷键/发呆提示 | `ui/level_scene.gd` |
| 改进关流程 | `game/game.gd start_level/enter_board` |
| 机器人动作/语音 | `game/robot_link.gd` + `docs/ROBOT_API.md` |

## 5. 改完怎么验证

```bash
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . --import                              # 新 class_name/字段后重建缓存
"$GODOT" --headless --path . --script res://tests/run_tests.gd     # 72 例,退出码 = 失败数
"$GODOT" --path . --script res://tests/visual_smoke_m3.gd          # 15 关自动通关 + 对话点击回归 + 截图
"$GODOT" --path . --script res://tests/visual_smoke_m2.gd          # 封程嵌套 / 岔纹汇路 / 溃散 三场景
"$GODOT" --path . --script res://tests/visual_smoke_ui.gd          # UI 交互矩阵(真实输入管线)
"$GODOT" --path .                                                  # 实跑看手感
```

改 `logic/` 必跑 headless;改 UI 看 `tests/screenshots/` 的截图对比;改关卡数据两者都跑。

**测试分层**(想知道"某种情况有没有被测到"先看这里):
- `tests/test_solver_exhaustive.gd` — 穷举/随机:七台机器两两每个口互接、每台机自环、每个可钉口钉每种纹样;
  300 张固定种子随机图跑不变量(每口有纹样、OK 边两侧全染色相等、欠定边含未染纱、CYCLE 边在环上、
  钉值不被改写、**摘掉下游普通线上游出口不变(禁反推)**、重解确定、JSON 往返不变、接线乱序胜负一致);
  每关解法"完整通关 / 少任一钉不通关 / 少任一线不通关 / 4 种接线顺序仍通关 / 要钉的原子本关可用";
  存档残留 l16/l17/notebook_tnd 无害;ProofSession 随机操作序列 undo 全回初态、redo 全回终态。
- `tests/visual_smoke_ui.gd` — 真实输入:对话在名牌/正文/面板角/面板外/立绘/插图六个落点都能推进,
  立绘与背景贴图槽位,无对话关直进棋盘;右键在标题/纹样/标签/spacer/几何中心六个落点都能删,
  拖动中右键不删,线轴/目标不删,Delete 键、Ctrl+Z/Ctrl+Shift+Z;钉按钮→编辑器→钉住→📌;
  幽灵态切换;欠定/冲突徽章与断线;重置按钮;选关页点按钮进关。
- `tests/visual_smoke_m3.gd` / `m2.gd` — 端到端流程与三个代表性证明。
