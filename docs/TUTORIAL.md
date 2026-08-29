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
game/        Game autoload(流程/存档/机器人 cue 转发)、SaveManager、RobotLink、Bgm(背景音乐槽位)
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
- `MachineNode`:每行一对(输入口,输出口)单元格,**只画纹样不写公式文字**(美术要求);可钉口在标题栏出按钮
  (单口"钉纹样",岔纹机"钉上口/钉下口"),钉住后口下出「已钉」小字;
  右键节点体 → `delete_requested` → 板转 `session.remove_machine`(线轴/目标模型层拒删)。
  关卡必需按钮(重置/示答/下一关/选关)挂在 GraphEdit 自带工具条上(`ProofBoard.add_toolbar_item`)。
- `PatternView`:哑控件,给 Formula 画纹样(AND 竖分 / IMP 横分 / OR 对角 / META 斜纹 / BOT 焦纹),`ghost` 用 `self_modulate` 调透明度。

### 2.5 流程与剧情

```
MainMenu(标题页:开始/继续游戏 · 重置进度 · 开发者信息 · 退出)→ LevelSelect → Game.start_level(lv)
                            ├─ 有 intro_dialogue → StoryScene(固定底图 + 场景插图 + 左右立绘 + 遮罩 + 对话区)
                            │                         播完 → Game.enter_board()
                            └─ 无 → enter_board() → LevelScene(仪器架 + 棋盘 + 右缘笔记抽屉)
LevelScene.proof_completed → Game.notify_solved(记档、robot_cue 庆祝)→ 工具条「下一关」
末关 l15 通关 → 「继续」→ Game.play_ending() → StoryScene 播 outro_dialogue(4-3,通关后剧情)
    → 「感谢游玩」黑屏淡入(此刻小机修好)→ Game.finish_ending() → CreditsScene 从黑淡入
CreditsScene(开发者信息,纯文字,Esc/点击返回)
```

- `DialogueBox`(Control,只管文字):打字机 + 点击/任意键推进(打字中=整句显示,显示完=下一句,最后一句后=关闭),没有跳过键;
  每行 `robot_cue` 转发给 `Game.robot_cue` → `RobotLink`(有实机才发)。
- 每句台词自带 `scene / left_char / left_expr / nora_expr`(中文名),`StoryArt` 登记表把中文名换成 `assets/art/story/` 的 PNG;
  主角诺拉恒在右侧,两人同在时非发言者叠 50% 遮罩;不显示场景名。正式台词从策划 xlsx 灌
  (`python3 tools/xlsx_to_csv.py` → `tools/import_dialogue.gd`;4-3 段写进 l15 的 `outro_dialogue`)。
- 诺拉的笔记 = 七台仪器说明(`notebook.tres`,由 `gen_levels.gd` 的 `RULE_GUIDE` 表生成),关内按本关 allowed_rules 过滤显示;
  关内右缘抽屉划出/收回(`NotebookUI`,Tween),「翻页」循环。
- 小机剧情弧(`Game.robot_mode()` 按关卡序,分界 `Game.BREAK_LEVEL = l10`):坏掉前(l01–l10)`guide` —— 玩家对麦克风说
  「请指导我 / 请帮帮我」(`hardware/speech/listen.py` 识别 → 桥接 → `Robot.guide_requested`)→ `LevelScene._run_guide`:小机回头到极限
  (`Robot.turn_to_limit`,方向存 `SaveManager.settings.robot_turn`)→ 0.8 s 后 `LevelSolutions.apply` 代解,`notify_solved(state, false)` 不庆祝;
  **3-1(l10)通关瞬间坏掉**:win cue = `panic`(坏掉是剧情节点,代解通关也演),`notify_solved` 随即置 `Robot.broken`;
  l11 起 `broken` —— 任何 cue 都映射成故障三连(`RobotLink.commands_for`);**结局才修好**:「感谢游玩」黑屏时 `broken=false` + `calm`(`ui/story_scene.gd _play_thanks`)。
- 关卡与笔记 .tres 由 `tools/gen_levels.gd` 从表生成,重跑会覆盖(对话字段除外:重跑原样保留现有 intro/outro 台词)。

**背景音乐**:autoload `Bgm`(`game/bgm.gd`)按槽位播:`TRACKS` 槽位 → `music/<槽位>.mp3`,各场景 `_ready` 报自己的槽位(标题/选关/开发者信息 = `title`;故事界面与关内 = 该章 `level_N`)。同槽位不重启,换槽位两个播放器交叉淡化,槽位没曲子淡出到静音。没有音量 UI(美术文档没有),音量是常量 `VOLUME_LINEAR`;各曲响度不一用 `GAIN_DB` 按文件填 dB 修正(量法见 `music/音乐bgm位置.md`)。槽位表与补曲步骤见 `music/音乐bgm位置.md`。

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

### 3.3 美术包接入(2026-08-29,严格按 `information/art_spec_20260829/游戏样式美化.md`)

| 改动 | 落点 | 备注 |
|---|---|---|
| 逻辑视口 3840×2160,PNG 原尺寸 | `project.godot [display]`、`gui/theme/default_theme_scale=2` | 美术:不改图片大小与长宽比;窗口开局最大化(`size/mode=2`,适配 1920×1080 等任意屏),取消最大化还原 1440×810,整体等比缩放。所有像素常量都是 4K 坐标 |
| 站酷小薇体 + 纯文字按钮悬停变浅 | `theme/main_theme.tres`(FontVariation + 系统字体兜底;Button 四态 StyleBoxEmpty) | 字体没有 ☠📌▶✓∧∨→⊥ 等符号,UI 字面量全部去符号(`tests/test_theme.gd` 扫) |
| 标题页 / 选关页 / 开发者信息页 | `ui/main_menu.gd`、`ui/level_select.gd`、`ui/credits_scene.gd` | 标题页恰好四个选项、重置点击即清档;选关/开发者页左上角「返回主界面」(`ui/back_button.gd`),Esc 也回;关名「第N纹」 |
| 故事界面换图 | `ui/story_scene.gd`、`narrative/story_art.gd`、`DialogueLine` 新字段、`tools/import_dialogue.gd` | 删地点铭牌与 `DialogueRes.location_title/background`、`DialogueLine.side_right/portrait` |
| 关内界面 | `board/palette_panel.gd`(固定 7 格)、`ui/level_scene.gd`(绝对布局、工具条按钮)、`narrative/notebook_ui.gd`(图片抽屉) | 删 HUD 关名/目标文字、节点端口 Label、`MachineGuidePanel`/`RuleGuide*`、`LevelDef.notebook_unlocks`、`SaveManager.notebook` |
| 测试 | `visual_smoke_ui.gd` 重写(`push_input(ev, true)`:视口≠窗口时坐标要按视口给)、新增 `test_story_art/test_dialogue_import/test_theme` | 81/81 + 三 smoke 全绿 |

### 3.4 审查后修掉的 bug(值得记住的坑)

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
| 改台词/场景/立绘/表情 | 改剧情 xlsx(`剧情文件及美术补充/`)→ `python3 tools/xlsx_to_csv.py` → `tools/import_dialogue.gd`(列定义见 `docs/CONTENT_INTERFACE.md`);或关卡 .tres 的 `intro_dialogue` / `outro_dialogue`(Inspector) |
| 加角色/表情/场景图 | PNG 按命名规则放 `assets/art/story/` + `narrative/story_art.gd` 表补一行(`tests/test_story_art.gd` 会查文件存在) |
| 加/删关卡或章节 | `tools/gen_levels.gd`(`LEVELS`/`CH_*` 表;关名自动「第N纹」)→ 重跑生成器 → 删孤儿 .tres → 改 `tests/test_levels.gd`、`visual_smoke_m3.gd` 计数 → 在 `levels/level_solutions.gd` 加脚本化解法(含 `p` 钉) |
| 调关卡顺序/难度、加新关选题 | 先看 `docs/LEVEL_DESIGN.md`(15 关逐关总结、难度曲线诊断、25 关重设计表 + 已验证解法附录),再按上一行改数据 |
| 加一台仪器 | `logic/rules.gd` 一行链式定义(自由变量所在口标 `pinnable`)→ `CH_RULES` 放进某章 → 测试 `test_describe_rule_metadata` 的台数 → 解法 |
| 改"钉"的规则(哪些口可钉) | 只改 `rules.gd` 的 `pinnable` 标记;`_port_free_meta` 要求可钉口恰有一个自由变量 |
| 改求解语义 | `logic/proof_graph.gd solve()` + `logic/unifier.gd match_into`;先看 `tests/test_graph.gd` 末尾的正向语义测试和 `test_unifier.test_match_into_is_one_way` |
| 改纹样画法/幽灵透明度 | `api/pattern_view.gd`(`layout()` 是纯函数,`test_pattern_layout` 盯着;`GHOST_ALPHA`) |
| 改节点外观/钉按钮/右键行为 | `board/machine_node.gd`;连线与整板行为在 `board/proof_board.gd` |
| 删除机器 | 左键点节点选中 → 按删除键(`ui_graph_delete`,GraphEdit 内置);也可右键点节点体(`machine_node.gd _gui_input`)。**Mac 坑**:笔记本的"delete"是 Backspace,`project.godot [input]` 已把 KEY_BACKSPACE 一并绑进 `ui_graph_delete`,否则点选后按 delete 删不掉 |
| 诺拉的笔记抽屉 | `narrative/notebook_ui.gd`(夹子「笔记/继续工作」切换 + Tween 划出收回 / 「翻页」循环);`open(nb, unlocked)` 严格过滤(`unlocked` = 本关 allowed_rules,条目 id = rule_id,传空则一条不显示);位置常量见 `docs/ART_INTERFACE.md` §3。竖排 CJK 用逐字换行 |
| 笔记条目(= 仪器说明) | `tools/gen_levels.gd` `RULE_GUIDE` 表(顺序同仪器架)→ 重跑生成器 → `narrative/data/notebook.tres` |
| 仪器架按钮/顺序/显隐 | `board/palette_panel.gd`(`SLOT_ORDER`、`SLOT_IMAGE`、位置常量);本关 `allowed_rules` 之外不显示,可见按钮紧凑重排 |
| 棋盘滚动条/画布大小 | `board/proof_board.gd _ready`(滚动条 modulate 隐形 + 两个角标 GraphElement 撑画布;中键拖动是引擎内置) |
| 改错误徽章文字/颜色 | `board/wire_overlay.gd BADGE/BADGE_COLOR`(纯文字,不用符号) |
| 改故事界面布局(底图/插图/立绘框/文字区) | `ui/story_scene.gd` 顶部常量(见 `docs/ART_INTERFACE.md` §3) |
| 改标题页/选关页/开发者信息页布局 | `ui/main_menu.gd`、`ui/level_select.gd`、`ui/credits_scene.gd` 顶部常量 |
| 改关卡布局/工具条按钮/快捷键/发呆提示 | `ui/level_scene.gd`(`PALETTE_POS`/`BOARD_RECT`;按钮经 `ProofBoard.add_toolbar_item`) |
| 测试开答案 | 棋盘工具条「示答」按钮(`level_scene.gd _on_show_answer`):重置后按 `levels/level_solutions.gd` 自动摆出本关答案。仅 `OS.is_debug_build()` 且本关有解法数据时出现 |
| 改进关流程 / 结局流程 | `game/game.gd start_level/enter_board`;结局 `play_ending/finish_ending` + `ui/story_scene.gd _play_thanks`(黑屏时长/字号在 StoryScene 顶部常量)+ `ui/credits_scene.gd` 淡入 |
| 背景音乐 / 换曲加曲 | `game/bgm.gd`(`TRACKS` 槽位表、`play(槽位)`、`VOLUME_LINEAR`/`FADE_SEC`)+ `music/音乐bgm位置.md`;场景报槽位在各 `ui/*.gd _ready` |
| 机器人动作/语音 | `game/robot_link.gd`(cue → 命令表 `commands_for`)+ `docs/ROBOT_API.md`;改台词 `hardware/make_voice.sh <名字> "<台词>"` 后用「小机维护」刷入 |
| 「请指导我」代解 / 坏掉时点 | `ui/level_scene.gd` `_on_guide_requested/_run_guide`、`game/game.gd robot_mode/BREAK_LEVEL/notify_solved`、`game/robot_link.gd broken/turn_to_limit`;提示文案 `GUIDE_HINT` |
| 「小机不动」模式(舵机坏/展示静音动作) | `game/robot_link.gd stationary/STILL_CMDS/set_stationary`(send 层统一拦 gimbal/anim/cal_look,其余照常);开关在维护面板「小机动作」,存 settings |
| 小机维护面板(接入 / 刷固件 / 校准 / 回头方向) | `ui/robot_maint_ui.gd`(开发者信息页「小机维护」按钮、标题页 F9);脚本 `hardware/run_robot.sh` `stop_robot.sh` `flash_robot.sh` |
| 语音识别 | `hardware/speech/listen.py`(Vosk 离线,语法只认两句;`get_model.sh` 下载模型);桥接 `bridge.js` 把带 evt 的客户端消息广播给游戏 |

## 5. 改完怎么验证

```bash
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . --import                              # 新 class_name/字段后重建缓存
"$GODOT" --headless --path . --script res://tests/run_tests.gd     # 102 例,退出码 = 失败数
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
- `tests/visual_smoke_ui.gd` — 真实输入(`push_input(ev, true)`,坐标按 3840×2160 视口给):故事界面的场景/立绘/遮罩切换,
  名字/正文/屏幕角/立绘/插图六个落点点击与任意键推进,不显示场景名;无对话关直进棋盘;工具条无撤销/重做、不显示关名;
  仪器架 7 格顺序与置灰、点置灰不放置;节点内无公式字母;右键在标题/纹样/spacer/「已钉」/几何中心都能删,
  拖动中右键不删,线轴/目标不删,Delete 键、Ctrl+Z/Ctrl+Shift+Z;钉按钮→色块编辑器→钉住→「已钉」;
  幽灵态切换;欠定/冲突纯文字徽章与断线;重置;笔记抽屉划出/变「继续工作」/翻页循环/收回;
  标题页恰好四项、开始→选关、继续游戏、重置即清档、开发者信息 Esc/点击返回;选关页全显示只一关可点、Esc 返回、点「第一纹」进关;示答。
- `tests/test_story_art.gd` / `test_dialogue_import.gd` / `test_theme.gd` — 立绘登记表文件存在、CSV 导入解析与校验、主题字体与 UI 字面量符号扫描。
- `tests/test_res_paths.gd` — Windows/导出包可移植性:所有 res:// 字面量与动态拼接路径(StoryArt/Bgm)逐段核对磁盘精确大小写
  (mac/Windows 文件系统大小写不敏感,开发期写错不报错;导出 PCK 严格区分,一到导出版才炸)。
- `tests/test_robot_logic.gd` — 语音命中、章节→模式、故障态 cue 映射、回头目标角、settings 过 wipe;
  `visual_smoke_ui.gd` R 段直接注入 `{"evt":"speech"}`:坏掉前代解且不庆祝、方向左右、3-1 通关瞬间坏掉(panic)、坏掉后不代解只故障(无真机也跑)。
  真机:`bash hardware/run_robot.sh` 后 `tests/robot_smoke.gd`;语音自测看 `hardware/.run/speech.log` 的「命中」行。
- `tests/visual_smoke_m3.gd` / `m2.gd` — 端到端流程与三个代表性证明。
