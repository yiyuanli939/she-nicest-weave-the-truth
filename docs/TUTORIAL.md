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
game/        Game autoload(流程/存档/机器人 cue 转发)、SaveManager、RobotLink、Bgm(背景音乐槽位)、Sfx(操作音效槽位)
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
- `MachineNode`:每行一对(输入口,输出口)单元格,**只画纹样不写公式文字**(美术要求);端口图形自画
  (`PortLayer`:输出口插头 / 输入口插座 / 接上整圆),纹样边框按仪器模板的元变量着色,可钉口旁有带底色的「钉纹样」按钮、
  未钉时纹样外一圈虚线;封程机是凹形(假设口/输入口在两臂内沿,`port_pos()` + 板的三个虚函数接管;图口号 ≠ 模型口号,
  `graph_out_port/model_out_port` 换算);右键节点体 → `delete_requested` → 板转 `session.remove_machine`(线轴/目标模型层拒删)。
  详见 3.6。
  关卡必需按钮(重置/示答/选关)挂在 GraphEdit 自带工具条上(`ProofBoard.add_toolbar_item`);通关推进不在工具条上,是 `WinPopup` 弹窗(v1.2,见 3.8)。
- `PatternView`:哑控件,给 Formula 画纹样(AND 竖分 / IMP 横分 / OR 对角 / META 斜纹 / BOT 焦纹),`ghost` 用 `self_modulate` 调透明度。

### 2.5 流程与剧情

```
MainMenu(标题页:开始/继续游戏 · 重置进度 · 开发者信息 · 退出 · 设置(弹窗))→ LevelSelect → Game.start_level(lv)
                            ├─ 有 intro_dialogue → StoryScene(固定底图 + 场景插图 + 左右立绘 + 遮罩 + 对话区)
                            │                         播完 → Game.enter_board()
                            └─ 无 → enter_board() → LevelScene(仪器架 + 棋盘 + 右缘笔记抽屉)
LevelScene.proof_completed → Game.notify_solved(记档、robot_cue 庆祝)→ WinPopup「织成了」弹窗 → 「继续」→ start_level(next)
末关 l16 通关 → 弹窗「继续」→ Game.play_ending() → StoryScene 播 outro_dialogue(4-3,通关后剧情)
    → 「感谢游玩」黑屏淡入(此刻小机修好)→ Game.finish_ending() → CreditsScene 从黑淡入
CreditsScene(开发者信息,纯文字,Esc/点击返回)
```

- `DialogueBox`(Control,只管文字):打字机 + 点击/任意键推进(打字中=整句显示,显示完=下一句,最后一句后=关闭),没有跳过键;
  每行 `robot_cue` 转发给 `Game.robot_cue` → `RobotLink`(有实机才发)。
- 每句台词自带 `scene / left_char / left_expr / nora_expr`(中文名),`StoryArt` 登记表把中文名换成 `assets/art/story/` 的 PNG;
  主角诺拉恒在右侧,两人同在时非发言者叠 50% 遮罩;不显示场景名。正式台词从策划 xlsx 灌
  (`python3 tools/xlsx_to_csv.py` → `tools/import_dialogue.gd`;4-3 段写进 l16 的 `outro_dialogue`)。
- 诺拉的笔记 = 七台仪器整页图(`notebook.tres`,由 `gen_levels.gd` 的 `NOTEBOOK_IDS` 生成),关内按本关 allowed_rules 过滤显示;
  关内右缘抽屉划出/收回(`NotebookUI`,Tween),「翻页」循环。
- 小机剧情弧(`Game.robot_mode()` 按关卡序,分界 `Game.BREAK_LEVEL = l11`):坏掉前(l01–l11)`guide` —— 玩家对麦克风说
  「请指导我 / 请帮帮我」(`hardware/speech/listen.py` 识别 → 桥接 → `Robot.guide_requested`)→ `LevelScene._run_guide`:小机回头到极限
  (`Robot.turn_to_limit`,方向存 `SaveManager.settings.robot_turn`)→ 0.8 s 后 `LevelSolutions.apply` 代解,`notify_solved(state, false)` 不庆祝;
  **3-1(l11)通关瞬间坏掉**:win cue = `panic`(坏掉是剧情节点,代解通关也演),`notify_solved` 随即置 `Robot.broken`;
  l12 起 `broken` —— 任何 cue 都映射成故障三连(`RobotLink.commands_for`);**结局才修好**:「感谢游玩」黑屏时 `broken=false` + `calm`(`ui/story_scene.gd _play_thanks`)。
- **关内操作指引**(`narrative/step_guide.gd`,纯函数):每次 `board_updated` 由 `StepGuide.facts_of` 从 ProofSession 查事实
  (机器数/线数/未钉口/已钉/已通关),`newly_done` 把盘上已经做出来的操作(放/拉/钉)记进 `SaveManager.steps`,
  `next_step` 按 `ORDER`(pin → place → wire)取第一条没做过的显示在 `LevelScene._step_hint`
  (棋盘左下、求助提示上一行,`STEP_HINT_*` 常量)。已通关不显示;重置进度清 `steps`。v1.1 起删掉了「断线拆机」「翻笔记」两步:
  接错的线自己断、首次上架仪器的笔记进关自动弹出(`LevelScene._ready` → `NotebookUI.open_at`)。
  文案 `StepGuide.TEXT` 只讲操作(文案守则同笔记)。用户要求加、美术文档没有 → 先纯文字,美术要换图/挪位只动常量。
- 关卡与笔记 .tres 由 `tools/gen_levels.gd` 从表生成,重跑会覆盖(对话字段除外:重跑原样保留现有 intro/outro 台词)。
  仪器**按关上架**:`LEVELS` 每行末列是本关新上架的仪器,之后的关累计(l01 一台都没有);解法只能用架上仪器(`test_levels` 盯)。
  重排关卡 id 时先按新编号 `git mv` .tres(降序)再重生成,对话就按路径跟着搬;`information/dialogue.csv` 的章-节要同步改,`test_tres_dialogue_matches_csv` 逐句核对。

**背景音乐**:autoload `Bgm`(`game/bgm.gd`)按槽位播:`TRACKS` 槽位 → `music/<槽位>.mp3`,各场景 `_ready` 报自己的槽位(标题/选关/故事界面(开场 / 结局对话)/开发者信息 = `title`,从选关进对话不重启;关内棋盘 = 该章 `level_N`,关内曲只在棋盘起)。同槽位不重启,换槽位两个播放器交叉淡化,槽位没曲子淡出到静音。音量 = 基准常量 `VOLUME_LINEAR` × 玩家设置 `user_volume`(标题页设置模块的滑条,存 `settings.music_volume`,`Bgm._ready` 读;见 3.7);各曲响度不一用 `GAIN_DB` 按文件填 dB 修正(量法见 `music/音乐bgm位置.md`)。槽位表与补曲步骤见 `music/音乐bgm位置.md`。wav 的循环点由 `Bgm.set_looping` 运行时兜底(没有循环点就整曲循环,`.import` 不用改;只开 `loop_mode` 不设 `loop_end` 会混 1 帧即停,见 AGENTS 踩过的坑)。

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
| 标题页 / 选关页 / 开发者信息页 | `ui/main_menu.gd`、`ui/level_select.gd`、`ui/credits_scene.gd` | 标题页美术四个选项(+ 后加的第五项「设置」,见 3.7)、重置点击即清档;选关/开发者页左上角「返回主界面」(`ui/back_button.gd`),Esc 也回;关名「第N纹」 |
| 故事界面换图 | `ui/story_scene.gd`、`narrative/story_art.gd`、`DialogueLine` 新字段、`tools/import_dialogue.gd` | 删地点铭牌与 `DialogueRes.location_title/background`、`DialogueLine.side_right/portrait` |
| 关内界面 | `board/palette_panel.gd`(固定 7 格)、`ui/level_scene.gd`(绝对布局、工具条按钮)、`narrative/notebook_ui.gd`(图片抽屉) | 删 HUD 关名/目标文字、节点端口 Label、`MachineGuidePanel`/`RuleGuide*`、`LevelDef.notebook_unlocks`、`SaveManager.notebook` |
| 测试 | `visual_smoke_ui.gd` 重写(`push_input(ev, true)`:视口≠窗口时坐标要按视口给)、新增 `test_story_art/test_dialogue_import/test_theme` | 81/81 + 三 smoke 全绿 |

### 3.5 性能与功耗 + 无机器人模式(2026-09-02)

起因:Windows 笔记本跑导出的 exe,十分钟后持续过热 + 线圈啸叫。排查(全项目无循环 Tween/粒子/SubViewport,
贴图按需加载,语音/桥接进程 macOS-only)后定位在「没有帧率上限、静止画面也每帧全量重绘、Forward+/D3D12 是脚手架默认」。改法:

| 设置(`project.godot`) | 作用 |
|---|---|
| `application/run/max_fps=60` | 硬上限:驱动 vsync 失效(混合显卡笔记本常见)时不会飙到几千 fps 空转 |
| `application/run/low_processor_mode=true` | 画面没变化就不重绘,棋盘静止时 GPU≈0;Tween/文字/悬停/`TIME` 着色器都会自动触发重绘,不用管 |
| `display/window/vsync/vsync_mode=1` | 显式垂直同步(原先靠默认) |
| `rendering/renderer/rendering_method="gl_compatibility"`(+`.mobile`) | 纯 2D 用 Compatibility;Web 版本来就只能用它,视觉已验证;不再依赖 D3D12 |

低功耗模式的守则:**每帧要动的东西要么通过 Tween/属性变化让渲染服务器知道,要么用 `set_process` 门控** ——
`board/wire_overlay.gd`(有徽章才跟随,缓存节点引用零分配)、`ui/level_scene.gd`(发呆计时只在有机器人时跑)、
`ui/robot_maint_ui.gd`(面板打开才刷新)、`game/robot_link.gd`(无机器人模式不轮询)都已这样做;
`_process` 只许出现在这四个文件里,`tests/test_perf_settings.gd` 扫源码盯着(还盯 project.godot 三件套、贴图全开 mipmap、Windows 预设)。
`tests/visual_smoke_ui.gd` T 节实测:关内静止 1 s 重绘 ≤10 帧、标题页流光照常 ≥10 帧。

**无机器人模式**(`Robot.enabled`,见 `docs/ROBOT_API.md`「无机器人模式」):命令行 `-- --no-robot` > `settings.robot_enabled` > 平台默认(仅 macOS 开);
关内求助提示、开发者信息页「小机维护」按钮、退出时的道晚安都随之消失,`Robot` 不连桥接不轮询;切回入口是标题页设置模块「小机联动」(3.7;F9 面板也行,所有构建)。

Windows 发布:`export_presets.cfg`「Windows Desktop」预设(排除素材源目录,单文件 exe),
`"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/she_nicest.exe`(目录要先建好)。

### 3.6 v1.1 交互调整(2026-09-02,策划说明 `v1.1交互调整说明/`,md + 14 张示意图)

| 说明条目 | 做法与落点 |
|---|---|
| §1 端口形状:输出口 = 带尖角的圆(插头),输入口 = 缺口圆(插座);拖线时插头随鼠标;接上合成整圆 | `GraphNode._draw_port` 覆写为空压掉默认圆点,图形画在节点最后一个子节点 `PortLayer`(Node2D,不算 slot)上 —— `_draw_port` 在 C++ `NOTIFICATION_DRAW` 里、早于脚本 `_draw`,画在那里会被自画外形盖住。拖线中的插头由 `WireOverlay._input`(鼠标移动才重绘,不用 `_process`)画在鼠标处,`connection_drag_started/ended` 开关 |
| §2 依赖未消去假设的线整条粉红 | 模型:`_propagate_hyps` 的边→假设集存进 `SolveResult.edge_hyps`,`WireInfo.carries_hyp` / `get_wire_carries_hyp`;视图:GraphEdit 没有逐线颜色,用 `set_connection_activity(…, 1.0)` 把整条线插值到主题 `GraphEdit/colors/activity`(= HYP_COLOR) |
| §3 错误字放大 ≥2× + 白描边;接错的线 0.5 s 自动断开,提示停 1 s 淡出 | `WireOverlay`:64 号 + `outline_size 8`;徽章按线键缓存(同线同状态不重建、不重启计时),自动断开的三种状态(`AUTO_BREAK` = 冲突/成环/逃逸)的徽章建好即起 Tween(停 1 s → 0.3 s 淡出 → 释放);`ProofBoard._schedule_breaks` 每次 `board_updated` 给错线排 0.5 s 定时器,回调再核对状态才 `detach_chip` + `session.disconnect_wire(…, record_undo = false)`(示答/代解一帧内连完、终态 OK 的线不会被断)。自动断开**不记撤销步**,断开后棋盘若回到接线前那步也弹掉 —— 撤销历史里没有这条错线(否则 Ctrl+Z 只会复活它再断、还清空重做栈)。「欠定」不是接错,保留 |
| §4.1 纹样间距 | `MachineNode` `separation` 覆盖 = `ROW_GAP`(32,image 4 间距 ≈ 纹样高 × 0.45);纹样格 `SIZE_SHRINK_CENTER` 保证口在纹样中心 |
| §4.2 纹样边框按子命题着色 | `PatternView.region_borders`([{path, color}])+ `region_of_path()`(与 `layout()` 同一套切分);`MachineNode._borders_for` 按**仪器模板**结构走叶子,元变量查 `META_COLORS` / `META_COLOR_OVERRIDES`(岔纹机两口各自的钉色);描边在填色之后、分割线之前(分割处只剩灰条,同参考图);线轴/目标无 spec 照旧深色外框 |
| §4.3 汇路机分割线 | `MachineNode._draw` 在相邻两行间隙中点画金 + 乳黄两条 2 px 线 |
| §4.4 封程机凹形 | GraphNode 的口只能在左右边缘、左右缩进对称(`port_h_offset`),做不到"臂内沿";于是:行结构 [左臂 VBox(假设 P + 钉按钮) \| 缺口 spacer \| 右臂 Q] / [spacer \| P>Q] / [标题 Label],`title=""` + 顶部标题栏字号 1 + panel/titlebar 样式覆盖为空,U 形与底部标题带在 `_draw` 自画;口位 `port_pos()`,`ProofBoard` 覆写 `_is_in_input/output_hotzone`(热区矩形按主题 inner/outer extent 自算)与 `_get_connection_line`(端点命中引擎口位就换成 `port_pos`,再按引擎同款 `Curve2D` 贝塞尔出线;正式连线端点 = `(position_offset + 口位) * zoom`,拖线预览 = `position + 口位 * zoom`,两种都试)。引擎按 slot 顺序给右口编号,假设口在第一排 → 图口号 ≠ 模型口号,`graph_out_port/model_out_port` 换算;脚本/测试连线一律走 `session.connect_wire`(模型口号) |
| §4.5 钉纹样按钮进节点 + 蚂蚁线 | 按钮文字一律「钉纹样」,`UiStyles.fill_button` 底色(默认乳黄,岔纹机两口用各自钉色),位置 `PIN_BUTTON_SIDE`(默认纹样下方另起无口一行;岔纹机在纹样左侧同一行);`mouse_filter = PASS` 让右键穿透到节点(右键删机在按钮上也生效);未钉口 `_draw` 画静态虚线框(低功耗模式不做无限动画,`set_loops` 被测试禁止);「已钉」小字删除 |
| §4.6 弹窗改版 | `PatternEditor` 照 image 13 重排:标题带「纹样绘制」→ 预览 → 「点选笔刷进行绘制:」→ 色块 + 并织/迭层/岔纹线描图标(`BrushIcon`)[+ 焦纹图样(v1.2)] → 清空 / 取消 / 确认(带底色);删提示行与「挖回孔」;「清空」擦回一个孔不关窗,「确认」全染时钉住、整幅还是孔时 = 取消钉住(`pattern_cleared`);外框内容边距只留描边宽、标题带贴满上缘 |
| §5 笔记自动弹出 | `LevelScene._ready`:`debut_rules(lv)` 非空 → `NotebookUI.open_at(nb, allowed_rules, 首个新仪器)`(每次进关都弹);`StepGuide` 删 fix/notebook 两步。2026-09-02 用户加:新仪器的页纸左上角显示「新机器!」(`set_new_rules(debut)` → `_show_page` 按条目 id 显隐 `_new_label`;纯文字 + 常量 `NEW_LABEL_*`,纸面左上角 (411,278) 向内 (59,40),字号同「翻页」82、字色取整页图正文红 A3472E;`shot_4k` 的 4k_notebook 现在翻到新仪器页带标签) |

用户答复的歧义:「清空」= 清空画布、空画布「确认」= 取消钉住;弹窗完全照 image 13;笔记每次进关都弹。
自定的假设:端口/假设口颜色沿用;蚂蚁线静态;只有 冲突/成环/逃逸 自动断;提示计时从接线起;「焦纹」笔刷起初保留文字(v1.2 改成焦纹图样,见 3.8)。
对照截图:`tools/shot_4k.gd` 多出 `4k_machines.png`(七台仪器全摆上)与 `4k_editor.png`(弹窗;`SubViewport.gui_embed_subwindows = true` 才截得到 Window)。
像素对位:示意图各张比例不同,以纹样宽 128 / 预览宽 720 为尺折算后逐项量测,引擎常量按折算值定,数字表在 `docs/ART_INTERFACE.md` §3.6。
顺手修掉的 bug:左臂的假设纹样曾被同格更宽的钉按钮撑到 160 宽(VBox 子项默认 FILL)→ 纹样 `SIZE_SHRINK_BEGIN`;
凹形多边形在排版前一帧尺寸为零会自交、三角化报错 → `_draw_concave_shape` 先查几何退化再画;
逐图放大对比又修了三处:蚂蚁线压描边(可钉纹样离边再留 `ANT_EDGE_INSET`)、凹形描边闭合点在圆角露缝(闭合点挪到底边中点)、
对角分割线平头端帽戳出纹样角(`PatternView._draw` 两端缩半个线宽)。

### 3.4 审查后修掉的 bug(值得记住的坑)

| 问题 | 根因 | 修法 |
|---|---|---|
| 汇路机支路线能反绑假设 P,冲突徽章随接线顺序漂移 | `match_into` 的允许集给的是整机元变量;支路口 R 绑成 P 的别名后,`walk` 走到 P 就能绑 | 允许集改为**这条边入口模板里**的元变量(`solve()` 里的 `allowed_of`) |
| 坏存档钉了含 `?` 的纹样 → `Unifier.walk` 追自己死循环 | `from_dict` 只查可钉口,不查 ground | `from_dict` 只收"可钉口 + 全染色 + 自由变量唯一"的钉 |
| 真环上的边报 CONFLICT 而非 CYCLE | occurs check 先于环检测触发 | 环检测提前,环上的边不参与传播 |
| 点在对话面板/台词上不推进 | 面板是全屏捕捉层的兄弟,PanelContainer 默认 STOP 吃掉点击 | 去掉捕捉层,`DialogueBox._input` 在输入层截获左键(模态) |
| 右键节点正中不删、左键拖不动 | 行中间的 spacer `Control` 默认 STOP | spacer `mouse_filter = IGNORE` |
| 左键拖节点时按右键会误删手里的节点 | 右键事件发给鼠标焦点节点 | `_gui_input` 里 `button_mask` 含左键则忽略 |
| 旧档在新语义下"已通关但棋盘欠定",没有下一关按钮 | 按钮只在 `_on_win` 显示 | (v1.2 起已无此按钮:已通关的关重开一律拆掉目标线,玩家接回即通关弹窗;推进靠弹窗或「选关」) |

教训:UI 交互回归要走 `Window.push_input` 的真实输入管线(见 `visual_smoke_m3.gd` 的 `_click`),直接调 `_on_click/_gui_input` 测不出 mouse_filter 这类问题。

### 3.7 标题页设置模块(2026-09-02,用户要求;美术文档没有 → 先纯文字,常量留位)

标题页第五个选项「设置」(与美术的四项同列同间距,`_add_option(4, …)`)点开 `ui/settings_panel.gd`(`SettingsPanel`,CanvasLayer 50:
半透明遮罩挡住标题页 + 居中主题乳黄面板;标题页本身不放任何控件):
「设置」→ 音乐音量滑条(0–100%,`Bgm.set_user_volume` 当场生效,松手落 `settings.music_volume`)→ 「全屏:开/关」
(`DisplayServer.window_set_mode`,关 = 回工程默认最大化,Web 上 = 窗口模式(浏览器只认 WINDOWED 退出全屏,MAXIMIZED 是空操作);落 `settings.fullscreen`,
下次启动 `Game._apply_window_settings` 恢复;无头 / Web 启动不碰窗口;Web 的 `window_get_mode` 要等浏览器回调,按钮文字先按请求的状态显示)
→ 「小机联动:开/关」(= 无机器人模式开关,`Robot.set_enabled`,与维护面板同一开关;Web 版 `robot_possible()` 为假不显示)
→ 「小机维护」(联动开着才显示,打开 `RobotMaintUI`(层 60,压在弹窗上);F9 仍直通面板)→ 「关闭」(Esc 也关,面板压着时不管)。
维护面板关掉时 `refresh()` 同步文字;文字按钮沿用主题(无底、悬停变浅),滑条按色板自画(乳黄轨 / 黄铜已填段 / 棕红圆钮 `GradientTexture2D` 径向渐变)。
「重置进度」不清 settings。1:1 截图 `tools/shot_4k.gd` → `build/shots4k/4k_settings.png`。
测试:`tests/test_settings.gd`(映射 / 文案 / 往返 / 无 autoload 建弹窗开关)、`test_bgm.test_user_volume_scales_playback`、UI smoke T 节(第五项位置、
标题页无控件、弹窗居中、遮罩挡点击、点滑条正中 = 50%、联动开关、小机维护开面板、关闭 / Esc)与 S 节(无机器人模式下文字同步)。

### 3.9 操作音效(2026-09-02,用户要求:所有操作都配音效、不要刺耳)

autoload `Sfx`(`game/sfx.gd`,`class_name SoundFx`)照 `Bgm` 的路子做**槽位表**:`CLIPS` 槽位 → `assets/sfx/<槽位>.ogg`(`""` = 静音),
换音效只换文件或改一行;`GAIN_DB` 按槽位修正响度 × `BASE_VOLUME`(-6 dB,峰值 -1 dB 的片段修正后不削波)× 玩家「音效音量」`user_volume`
(设置弹窗第二条滑条,与音乐滑条同一模板 `_slider_row`,落 `settings.sfx_volume`,`Sfx._ready` 读回;滑条每动一档响一声 slider = 试听)。
播放:8 个一次性 `AudioStreamPlayer` 池,取空闲的、都忙抢最早的;**同一帧同槽位只响一次**(多选删除 / 多条线同时断 / 多枚徽章)。
**静音计数** `push_mute/pop_mute`:`LevelScene` 在载入旧棋盘、代解、示答前后包住;`ProofBoard._on_board_rebuilt` 整段(撤销/重做/重置重建节点与徽章);
自动断线在排队时记下当时是否静音(`_pending_breaks[key]`),载入旧档时排的 0.5 s 后不响。
**按钮不逐个接**:`_ready` 里 `get_tree().node_added` 凡 `BaseButton` 就连 `pressed` → 播 meta `"sfx"`(默认 `click`;`set_meta(&"sfx", &"")` 不响;
有自己动作音的按钮 —— 仪器架 / 钉纹样 / 笔记夹子与翻页 / 「设置」/ 「重置」/ 弹窗「关闭」 —— 都设成不响,免得两声叠一起)、`mouse_entered` → `hover`。
其余挂点每处一行 `SoundFx.hit(self, &"槽位")`(静态,找不到 autoload 就静默,测试不用 mock);完整槽位表与挂点在 `assets/sfx/音效位置.md`。
坑:GraphEdit 没有缩放信号 → `draw` 时比对 `zoom`;`connection_request` 先于 `connection_drag_ended` → 用 `_wired_this_drag` 区分「接上」与「空放」;
`_on_connection_request` 原来丢掉 `connect_wire` 的返回值,现在按它决定响不响;徽章 `rebuild` 只在新建 chip 分支响(沿用的不响)。
素材:Kenney CC0(`assets/sfx/LICENSE-kenney.txt`)起步;「不刺耳」量化为频谱质心 / 4 kHz 以上能量占比 / 峰值因子(`tools/sfx_audit.py`),
候选方案(freesound CC0 / Sonniss 样例)按此筛过放 `assets/sfx/候选/`,试听后整套或单个覆盖。
**合成版(候选 D,2026-09-02,用户要求「用 Godot 的 Audio 模块自己做一版,不下载」)**:`tools/sfx_synth.gd` 纯 GDScript 用 `AudioStreamWAV`
拼 16 bit PCM(`save_to_wav` 落盘),每个槽位一份配方 = 材质层按时间 `_add` 叠加:黄铜轻击 `_brass`(基频 + 2.4 / 4.1 倍非谐分音)/ 木叩 `_knock`
(低频正弦 30 ms 滑落 + 噪声瞬态)/ 木琴 `_wood`(正弦 + 4 倍泛音)/ 小铃 `_bell`(1 / 2.0 / 2.98 / 4.2 倍)/ 织物纸张 `_noise`(带通噪声扫频,RBJ 双二阶)。
不刺耳从源头保证:无方波锯齿、分音 ≥ 3.8 kHz 不加、噪声带通 ≤ 3.5 kHz、整体 6 kHz 四阶低通、起音 ≥ 1 ms 首尾淡入淡出;响度统一 —— 按峰值 -60 dB 去尾后
RMS 归 -18 dBFS、峰值封顶 -1 dBFS(与 `sfx_audit.py` 同口径,所以这套的 GAIN_DB 建议值都在 0 附近)。`tools/gen_sfx.gd` 出
`assets/sfx/候选/D_合成/<槽位>.wav`(34 配方 + 4 别名复制;全套 1 s;每条打印时长 / 峰值 / RMS / 峰值因子 / >4k 占比,越界退出码非零);
噪声以槽位名做种,逐样本可重现。`tests/test_sfx_synth.gd` 三例:配方覆盖 CLIPS 全部槽位 / 每条不刺耳有界 / 可重现且磁盘文件 = 当前配方(改配方没重出就红)。
**选定装入(2026-09-02)**:用户在试听台逐槽位挑定(33 段 freesound CC0 + 2 段 Kenney:unplug、loom = 原翻页音 `scroll_003` 挪到选定一关,
翻页改纸声;进入选关页先也响 loom,用户听过 Web 版后改为纸翻页 page、「开始游戏」按钮本身静音),要求「保证音效声音的一致性」「保留音效的授权」→ `tools/sfx_normalize.py` 就地统一:解码成单声道 44.1 kHz,起始静音(峰值 -40 dB 以下)
裁到 5 ms、尾部(-60 dB 以下)裁到 20 ms、2 ms 淡入 / 10 ms 淡出,软限幅(峰值包络、1 ms 前瞻、30 ms 释放,迭代到收敛)把峰值因子压到 ≤ 21 dB
(木击 / 金属开关的攻击尖峰削 2–8 dB,音色不动;单遍不够 —— 压掉瞬态后整段 RMS 也降,所以要迭代),RMS 归 -18 dBFS 且峰值 ≤ -1 dBFS,落 16 bit WAV
(ffmpeg 没 libvorbis,且有损再压一遍伤音质;35 个共 1.8 MB),CLIPS 后缀改 .wav、删旧 .ogg + .import;再 `sfx_apply.py <空文件> --test` 做
`--import` + GAIN_DB 重算 + 全量测试。授权:全部 CC0 不要求署名,但每段的标题 / 作者 / 链接 / 许可都记在 `assets/sfx/音效位置.md`「现用文件与来源」表,
换文件必须同步补表。
**复核(2026-09-02,用户「check 可能让人觉得奇怪的音效以及硬 bug」)**:`tools/sfx_trace.gd` 按真实输入走全流程、每步打印计数差,
另在 Chrome 里给 Web 版打 `AudioBufferSourceNode.start` 补丁核对送进 Web Audio 的缓冲(时长 / 响度 / 过零率都与文件一致,Web 走 sample 播放、48 kHz 重采样,
没播错文件)。查出并改掉四处:①`_unhandled_input` 先判 ui_undo —— `is_action_pressed` 默认不精确匹配修饰键,真实按 Ctrl+Shift+Z 走了撤销分支,
重做快捷键从来按不出来(UI 冒烟原来用 `InputEventAction` 发 ui_redo 所以看不见;现在先判 ui_redo,冒烟补真实组合键);②钉纹样弹窗 Esc / 点外面关闭无声,
只有「取消」按钮 meta 响 —— 改为 `popup_hide` 统一响 close,「确认」关的不响(`_confirming` 标记);③从已接的入口拖起线改接,引擎同帧发
disconnection_request + connection_drag_started,连响 unplug + pick,松手再 drop —— 同帧拖线开始不再叠 pick;④换场景 / 弹窗出现时按钮正好落在光标底下,
`mouse_entered` 也发、悬停音自己响(启动到标题页、Esc 回标题都会) —— `Sfx._input` 记鼠标移动帧,`HOVER_MOTION_FRAMES` 内没动过不响。
核过没问题、按设计保留的:进关瞬间 hint + 首次上架的笔记 drawer_open 同时响;故事界面立绘出现响 portrait;接错线 plug → 同帧 error → 0.5 s 后 snap;
撤销 / 重做 / 重置 / 载入 / 代解 / 示答期间静音计数进出成对(没有 await 夹在中间,换场景不会漏 pop);点节点不动鼠标不响 move。
坑:内嵌 `class` 里别起 `_set`(撞 Object 虚方法签名,整个脚本解析错);`floor()` 返回 Variant,`:=` 推不出类型要用 `floorf`;`SceneTree` 脚本的
`_initialize` 里一出错就走不到 `quit()`,headless 进程永远挂着 —— 新脚本先 `--check-only`,跑的时候套个 `perl -e 'alarm 60; exec @ARGV'`。
测试:`tests/test_sfx.gd`(表与时长 / 播放器池与同帧去重 / 静音计数与音量公式 / 按钮钩子 meta / 静态 hit 安全),`test_settings` 加 sfx_volume,
`test_res_paths` 走一遍 `CLIPS`,UI 冒烟在 D/F/G/U/L/T/N 各节断言 `Sfx.last_slot` / `counts`(放·钉·徽章·断线·删·撤销·拿起·接上·空放·抽屉·翻页·
弹窗开关·音效滑条·示答全程静音)。

### 3.8 通关弹窗 + 已通关关卡重开「差一步」+ 焦纹图样笔刷(2026-09-02,策划说明 `v1.2背景/`)

- **通关弹窗**:工具条「下一关」删掉,`proof_completed` → `_on_win` 记档/庆祝后 `_win_popup.open()`(`ui/win_popup.gd`,`CanvasLayer` 70,
  遮罩 + `CenterContainer` 真居中,面板就是美术图 `TextureRect`(`STRETCH_KEEP`,默认 `EXPAND_KEEP_SIZE` 最小尺寸 = 纹理尺寸,容器给它原尺寸 1174×816,
  左上角恰是 (1333, 672));「继续」按锚点钉在图内坐标 `CONTINUE_CENTER`,`GROW_DIRECTION_BOTH` 以锚点为中心长,不用量尺寸。
  `open()` 先 `gui_release_focus()`:遮罩只挡鼠标,GraphEdit 保有焦点时 Delete 会删弹窗后面的节点;`LevelScene._unhandled_input` 弹窗开着时也不收撤销/重做。
  「继续」= `_on_continue`:有下一关 → `start_level`;末关有 `outro_dialogue` → `play_ending()`;都没有(目录外注入的关)→ `goto_select()`。
  这里不再 `store_board`(`notify_solved` 已存过通关盘)。小机代解通关也弹(原来「下一关」也会出现)。`current == null`(m2 冒烟注入)不弹。
- **已通关的关重开**:`ProofSession.load_state(d, detach_goal)` —— `detach_goal` 时在快照与求解**之前**拆掉所有 `to_id == goal_id` 的边:
  不进撤销栈(Ctrl+Z 不能一键回到通关再触发庆祝)、载入时不重发 `proof_completed`、`_initial_state` 就是拆线后的盘。
  放会话层而不是 UI 层去动 `saved.graph.edges`,是不让存档格式漏出 `ProofGraph`。`LevelScene._ready` 按 `save.is_solved(lv.id)` 决定拆不拆;
  玩家接回最后一根线 = 正常通关(弹窗 + 重记档 + 庆祝;l11 会再演一次坏掉,与重玩语义一致)。`_restoring` 只剩「载入中不叫小机」的用途。
- **焦纹笔刷**:`PatternEditor._make_bot_button` —— 同 `SWATCH_SIZE` 的 toggle 按钮里嵌一个 `PatternView`(`formula = Formula.bot()`,四边缩 6 让按钮描边露出),
  与棋盘上的 ⊥ 同一画法(焦黑 + 破洞);文字只在 tooltip。
- 测试:`test_session.test_load_state_detach_goal`;m3 冒烟改为真实点击弹窗「继续」推进 16 关、l16/l04 重开断言差一步态、l16 接回目标线 → 弹窗 → 结局
  (`_reconnect_goal` 按解法表最后一根线接,机器 id 升序 = 摆放顺序);UI 冒烟 N 段(弹窗矩形 (1333,672,1174,816)、「继续」在空白带、遮罩挡「重置」、无「下一关」)、
  E 段(焦纹图样)、S 段;`tools/shot_4k.gd` 出 `4k_win.png`(直接 `open()`,不走通关以免写存档)与 `4k_editor_bot.png`(解锁焦纹的笔刷行)。

## 4. 想改 X,去哪改

| 想做的事 | 去哪 |
|---|---|
| 改台词/场景/立绘/表情 | 改剧情 xlsx(`剧情文件及美术补充/`)→ `python3 tools/xlsx_to_csv.py` → `tools/import_dialogue.gd`(列定义见 `docs/CONTENT_INTERFACE.md`);或关卡 .tres 的 `intro_dialogue` / `outro_dialogue`(Inspector) |
| 加角色/表情/场景图 | PNG 按命名规则放 `assets/art/story/` + `narrative/story_art.gd` 表补一行(`tests/test_story_art.gd` 会查文件存在) |
| 加/删关卡或章节 | `tools/gen_levels.gd`(`LEVELS` 表,末列 = 本关新上架仪器;`CH_OF_LEVEL`/`CH_TITLES`;关名自动「第N纹」)→ 重跑生成器 → 删孤儿 .tres → 改 `tests/test_levels.gd`、`visual_smoke_m3.gd` 计数 → 在 `levels/level_solutions.gd` 加脚本化解法(含 `p` 钉) |
| 调关卡顺序/难度、加新关选题 | 先看 `docs/LEVEL_DESIGN.md`(§0.5 现网 16 关编排表、旧 15 关逐关总结、难度曲线诊断、25 关重设计表 + 已验证解法附录),再按上一行改数据 |
| 加一台仪器 | `logic/rules.gd` 一行链式定义(自由变量所在口标 `pinnable`)→ 在 `LEVELS` 里它裸机关那行的上架列加进去 → 测试 `test_describe_rule_metadata` 的台数 → 解法 |
| 改"钉"的规则(哪些口可钉) | 只改 `rules.gd` 的 `pinnable` 标记;`_port_free_meta` 要求可钉口恰有一个自由变量 |
| 改求解语义 | `logic/proof_graph.gd solve()` + `logic/unifier.gd match_into`;先看 `tests/test_graph.gd` 末尾的正向语义测试和 `test_unifier.test_match_into_is_one_way` |
| 改纹样画法/幽灵透明度 | `api/pattern_view.gd`(`layout()` 是纯函数,`test_pattern_layout` 盯着;`GHOST_ALPHA`) |
| 改节点外观/钉按钮/右键行为 | `board/machine_node.gd`(顶部常量:端口图形、行距、`META_COLORS` 边框配色、钉按钮底色/位置、蚂蚁线、汇路机分割线、封程机凹形);连线与整板行为在 `board/proof_board.gd`(口位热区/连线端点接管、`BAD_WIRE_SEC` 自动断线、假设线 activity 染色) |
| 改端口形状 / 拖线中的插头 | `board/machine_node.gd draw_plug/draw_socket`、`PortLayer`;鼠标处的插头 `board/wire_overlay.gd begin_plug/_input/_draw` |
| 改封程机凹形 / 口位 | `board/machine_node.gd _build_concave/_draw_concave_shape/port_pos`;板侧 `board/proof_board.gd _in_hotzone/_get_connection_line/_remap_port_point`(见 3.6) |
| 改纹样绘制弹窗(标题/提示/笔刷/按钮) | `pattern/pattern_editor.gd`(`TITLE_TEXT` `HINT_TEXT` `STRUCT_BRUSHES` `BrushIcon`;`clear_canvas/_on_confirm` 语义) |
| 笔记自动弹出的时机 | `ui/level_scene.gd _ready` 末尾(`debut_rules` → `NotebookUI.open_at`) |
| 删除机器 | 左键点节点选中 → 按删除键(`ui_graph_delete`,GraphEdit 内置);也可右键点节点体(`machine_node.gd _gui_input`)。**Mac 坑**:笔记本的"delete"是 Backspace,`project.godot [input]` 已把 KEY_BACKSPACE 一并绑进 `ui_graph_delete`,否则点选后按 delete 删不掉 |
| 诺拉的笔记抽屉 | `narrative/notebook_ui.gd`(夹子「笔记/继续工作」切换 + Tween 划出收回 / 「翻页」循环);`open(nb, unlocked)` 严格过滤(`unlocked` = 本关 allowed_rules,条目 id = rule_id,传空则一条不显示),`open_at(nb, unlocked, rule_id)` 翻到指定仪器(进关自动弹出用);位置常量见 `docs/ART_INTERFACE.md` §3(实测基准在 §3.5)。夹子两行字用 `FontVariation` 的 spacing_top/bottom 把行距垫到参考的 92(Button 自然行距 79) |
| 笔记条目(= 仪器整页图) | 覆盖 `assets/art/level/notebook/<rule_id>.png`(3840×2160 全屏导出、透明底,标题/正文画在图里);新增仪器页改 `tools/gen_levels.gd` `NOTEBOOK_IDS` → 重跑生成器 |
| 仪器架按钮/顺序/显隐 | `board/palette_panel.gd`(`SLOT_ORDER`、`SLOT_IMAGE`、位置常量);本关 `allowed_rules` 之外不显示,可见按钮紧凑重排 |
| 棋盘滚动条/画布大小 | `board/proof_board.gd _ready`(滚动条 modulate 隐形 + 两个角标 GraphElement 撑画布;中键拖动是引擎内置) |
| 改错误徽章文字/颜色/字号/描边/停留时长;接错的线多久断 | `board/wire_overlay.gd BADGE/BADGE_COLOR/BADGE_FONT_SIZE/BADGE_OUTLINE/BADGE_HOLD_SEC/BADGE_FADE_SEC/AUTO_BREAK`(纯文字,不用符号);`board/proof_board.gd BAD_WIRE_SEC` |
| 改故事界面布局(底图/插图/立绘框/文字区) | `ui/story_scene.gd` 顶部常量(见 `docs/ART_INTERFACE.md` §3) |
| 改标题页/选关页/开发者信息页布局 | `ui/main_menu.gd`、`ui/level_select.gd`、`ui/credits_scene.gd` 顶部常量;「设置」弹窗 `ui/settings_panel.gd` 顶部常量 |
| 改关卡布局/工具条按钮/快捷键/发呆提示 | `ui/level_scene.gd`(`PALETTE_POS`/`BOARD_RECT`;按钮经 `ProofBoard.add_toolbar_item`) |
| 通关弹窗(图 / 「继续」位置字号字色 / 遮罩 / 推进去向)、已通关重开的「差一步」 | `ui/win_popup.gd` 常量;`ui/level_scene.gd` `_on_win` `_on_continue`;`api/proof_session.gd` `load_state(d, detach_goal)`;测试 `test_session` + m3 / UI 冒烟 N 段 |
| 关内操作指引(文案 / 触发条件 / 优先级 / 位置;v1.1 起只剩 钉/放/拉 三步) | `narrative/step_guide.gd`(`TEXT`、`ORDER`、`_applies`、`newly_done`)+ `ui/level_scene.gd` `STEP_HINT_*`;记忆在 `SaveManager.steps`;测试 `tests/test_step_guide.gd` + `visual_smoke_ui.gd` S 段 |
| 测试开答案 | 棋盘工具条「示答」按钮(`level_scene.gd _on_show_answer`):重置后按 `levels/level_solutions.gd` 自动摆出本关答案。仅 `OS.is_debug_build()` 且本关有解法数据时出现 |
| 改进关流程 / 结局流程 | `game/game.gd start_level/enter_board`;结局 `play_ending/finish_ending` + `ui/story_scene.gd _play_thanks`(黑屏时长/字号在 StoryScene 顶部常量)+ `ui/credits_scene.gd` 淡入 |
| 背景音乐 / 换曲加曲 | `game/bgm.gd`(`TRACKS` 槽位表、`play(槽位)`、`VOLUME_LINEAR`/`FADE_SEC`)+ `music/音乐bgm位置.md`;场景报槽位在各 `ui/*.gd _ready` |
| 操作音效 / 换音效 / 给某个操作加音 | `game/sfx.gd`(`CLIPS` 槽位表、`GAIN_DB`、`BASE_VOLUME`)+ `assets/sfx/音效位置.md`;某按钮换音 `set_meta(&"sfx", &"槽位")`;新挂点一行 `SoundFx.hit(self, &"槽位")`;不该响的区间 `push_mute/pop_mute` |
| 音效不想用下载素材、想改合成配方 | `tools/sfx_synth.gd`(`_r_<槽位>` 配方、材质函数、`NAMES`/`ALIASES`)→ `tools/gen_sfx.gd` 重出 `assets/sfx/候选/D_合成/` → `tests/test_sfx_synth.gd` 盯文件 = 配方 |
| 想知道某个操作实际响了几声 / 哪些槽位 | `godot --path . --script res://tools/sfx_trace.gd`(真实输入走全流程,每步打印计数差;弹窗内按钮走 `pressed.emit`) |
| 打 Web 包 / 传 itch.io | `export_presets.cfg`「Web」预设(nothreads 免 SharedArrayBuffer;排除 hardware/tests/素材源目录;`build/` 有 `.gdignore` 防被引擎扫描)→ `"$GODOT" --headless --path . --export-release "Web" build/web/index.html` → `butler push build/web yiyuanli/textrix-veritatis:html5`。缺字兜底靠打包的 Noto 两字形子集(Web 无系统字体,见 `test_theme`) |
| 机器人动作/语音 | `game/robot_link.gd`(cue → 命令表 `commands_for`)+ `docs/ROBOT_API.md`;改台词 `hardware/make_voice.sh <名字> "<台词>"` 后用「小机维护」刷入 |
| 「请指导我」代解 / 坏掉时点 | `ui/level_scene.gd` `_on_guide_requested/_run_guide`、`game/game.gd robot_mode/BREAK_LEVEL/notify_solved`、`game/robot_link.gd broken/turn_to_limit`;提示文案 `GUIDE_HINT` |
| 「小机不动」模式(舵机坏/展示静音动作) | `game/robot_link.gd stationary/STILL_CMDS/set_stationary`(send 层统一拦 gimbal/anim/cal_look,其余照常);开关在维护面板「小机动作」,存 settings |
| 小机维护面板(接入 / 刷固件 / 校准 / 回头方向 / 无机器人模式开关) | `ui/robot_maint_ui.gd`(标题页「设置」弹窗与开发者信息页的「小机维护」按钮仅有机器人时显示、标题页 F9 所有构建可用);脚本 `hardware/run_robot.sh` `stop_robot.sh` `flash_robot.sh` |
| 无机器人模式(提示/入口全消失) | `game/robot_link.gd enabled/resolve_enabled/set_enabled`;隐藏点:`ui/level_scene.gd _robot_on`、`ui/credits_scene.gd`、`ui/main_menu.gd` |
| 帧率上限 / 低功耗 / 渲染器 | `project.godot` `[application] run/max_fps、run/low_processor_mode`、`[rendering] renderer/rendering_method`;守门 `tests/test_perf_settings.gd`(见 3.5) |
| 语音识别 | `hardware/speech/listen.py`(Vosk 离线,语法只认两句;`get_model.sh` 下载模型);桥接 `bridge.js` 把带 evt 的客户端消息广播给游戏 |

## 5. 改完怎么验证

```bash
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path . --import                              # 新 class_name/字段后重建缓存
"$GODOT" --headless --path . --script res://tests/run_tests.gd     # 126 例,退出码 = 失败数
"$GODOT" --path . --script res://tests/visual_smoke_m3.gd          # 16 关自动通关 + 对话点击回归 + 截图
"$GODOT" --path . --script res://tests/visual_smoke_m2.gd          # 封程嵌套 / 岔纹汇路 / 溃散 三场景
"$GODOT" --path . --script res://tests/visual_smoke_ui.gd          # UI 交互矩阵(真实输入管线)
"$GODOT" --path .                                                  # 实跑看手感(--print-fps 看帧率:标题页 ~60,关内静止个位数)
"$GODOT" --path . -- --no-robot                                    # 无机器人模式实跑(标题页「设置」里「小机联动」/ F9 面板可切换)
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/she_nicest.exe   # Windows 单文件 exe(先 mkdir -p build/windows)
```

改 `logic/` 必跑 headless;改 UI 看 `tests/screenshots/` 的截图对比;改关卡数据两者都跑。
改图片位置/字号:跑 `"$GODOT" --path . --script res://tools/shot_4k.gd` 出 3840×2160 的 1:1 截图(`build/shots4k/`)与美术参考图叠图核对,
基准与实测数字见 `docs/ART_INTERFACE.md` §3.5;`tests/test_art_alignment.gd` 盯着抽屉开位 / 故事框线 / 立绘遮罩尺寸。

**测试分层**(想知道"某种情况有没有被测到"先看这里):
- `tests/test_solver_exhaustive.gd` — 穷举/随机:七台机器两两每个口互接、每台机自环、每个可钉口钉每种纹样;
  300 张固定种子随机图跑不变量(每口有纹样、OK 边两侧全染色相等、欠定边含未染纱、CYCLE 边在环上、
  钉值不被改写、**摘掉下游普通线上游出口不变(禁反推)**、重解确定、JSON 往返不变、接线乱序胜负一致);
  每关解法"完整通关 / 少任一钉不通关 / 少任一线不通关 / 4 种接线顺序仍通关 / 要钉的原子本关可用";
  存档残留 l16/l17/notebook_tnd 无害;ProofSession 随机操作序列 undo 全回初态、redo 全回终态。
- `tests/visual_smoke_ui.gd` — 真实输入(`push_input(ev, true)`,坐标按 3840×2160 视口给):故事界面的场景/立绘/遮罩切换,
  名字/正文/屏幕角/立绘/插图六个落点点击与任意键推进,不显示场景名;无对话关直进棋盘;工具条无撤销/重做、不显示关名;
  仪器架 7 格顺序与置灰、点置灰不放置;节点内无公式字母;右键在标题/纹样/spacer/几何中心(钉按钮上)都能删,
  拖动中右键不删,线轴/目标不删,Delete 键、Ctrl+Z/Ctrl+Shift+Z;钉按钮→纹样绘制弹窗(清空/取消/确认、三个图标笔刷)→确认→蚂蚁线消失;
  幽灵态切换;欠定徽章常驻、冲突线 0.5 s 自动断 + 徽章冻结淡出(64 号白描边);重置;
  U 段(v1.1):插座/插头/整圆端口状态,真实拖线中鼠标处的插头,封程机从臂内沿口位真实拖线接上、引擎默认口位拖不出线,
  假设线 `carries_hyp`,弹窗「清空」+「确认」= 取消钉住;S 段:l02/l07 进关笔记自动翻到新仪器那页、该页纸左上角「新机器!」在整页图之上且不出纸 / 不压标题墨迹 / 不压夹子、翻到别的页隐藏、翻回再现;笔记抽屉划出/变「继续工作」/翻页循环/收回;
  标题页四项 + 「设置」弹窗(居中、遮罩挡点击、滑条改音量当场生效并落档、小机联动开关、小机维护开面板、关闭/Esc)、开始→选关、继续游戏、重置即清档、开发者信息 Esc/点击返回;选关页全显示只一关可点、Esc 返回、点「第一纹」进关;示答 → 通关弹窗(居中原尺寸、「继续」在中下、遮罩挡「重置」、无「下一关」);焦纹图样笔刷。
- `tests/test_story_art.gd` / `test_dialogue_import.gd` / `test_theme.gd` — 立绘登记表文件存在、CSV 导入解析与校验、主题字体与 UI 字面量符号扫描。
- `tests/test_res_paths.gd` — Windows/导出包可移植性:所有 res:// 字面量与动态拼接路径(StoryArt/Bgm)逐段核对磁盘精确大小写
  (mac/Windows 文件系统大小写不敏感,开发期写错不报错;导出 PCK 严格区分,一到导出版才炸)。
- `tests/test_robot_logic.gd` — 语音命中、章节→模式、故障态 cue 映射、回头目标角、settings 过 wipe;
  `visual_smoke_ui.gd` R 段直接注入 `{"evt":"speech"}`:坏掉前代解且不庆祝、方向左右、3-1 通关瞬间坏掉(panic)、坏掉后不代解只故障(无真机也跑)。
  真机:`bash hardware/run_robot.sh` 后 `tests/robot_smoke.gd`;语音自测看 `hardware/.run/speech.log` 的「命中」行。
- `tests/visual_smoke_m3.gd` / `m2.gd` — 端到端流程与三个代表性证明。
