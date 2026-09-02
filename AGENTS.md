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
7. **美术/策划文档严格照做**:文档没写的 UI 元素、确认步骤、规则一律不加;图片原尺寸用
   (逻辑视口 = 出图分辨率 3840×2160);所有文字用站酷小薇体,UI 字面量不得含该字体没有的符号。

## 代码地图(M0 已完成 ✅)

| 文件 | 职责 |
|---|---|
| `logic/formula.gd` | 命题 AST(不可变;`key()` 规范串 = 相等/哈希/序列化基础) |
| `logic/formula_parser.gd` | 公式文本 ↔ AST(递归下降;`to_text` 保证往返) |
| `logic/rule_schema.gd` | 仪器模式:端口模板 + 假设口(`is_hypothesis`/`scope_input`) |
| `logic/rules.gd` | 七台仪器规则表(id 与 incredible.pm 规则名对应;`pinnable` 标可钉口) |
| `logic/unifier.gd` | 一阶合一(occurs check;union-find 式 walk/resolve) |
| `logic/proof_graph.gd` | 棋盘模型 + solve 五步管线(方程→合一→环→辖域→胜负) |
| `logic/solve_result.gd` | solve 的输出:端口纹样、边状态、每条边搭载的未消去假设(`edge_hyps`,UI 画整条假设色)、缺口、胜负 |
| `board/machine_node.gd` `board/proof_board.gd` `board/wire_overlay.gd` | 棋盘视图(全项目仅此两处许用 GraphEdit API):节点端口自画(插头/插座/整圆)、纹样边框按模板元变量着色、钉纹样按钮进节点、封程机凹形(口位 `port_pos` + 板的热区/连线端点/曲线三个虚函数接管、图口号↔模型口号换算)、接错线 `BAD_WIRE_SEC` 自动断、假设线 `set_connection_activity` 染色、徽章与拖线插头叠加层 |
| `narrative/story_art.gd` | 故事界面美术登记表:中文角色/表情/场景名 → `assets/art/story/*.png` |
| `game/robot_link.gd` | autoload Robot:ws→桥接→小机;cue→命令表(`commands_for`,故障态映射)、`guide_requested`、`turn_to_limit`、`stationary` 不动模式(send 层拦云台/动画/校准)、拉起 `hardware/*.sh` |
| `game/bgm.gd` | autoload Bgm:背景音乐槽位表 `TRACKS`(title / level_1..4 → `music/<槽位>.mp3`);`play(槽位)` 同文件不重启、换曲交叉淡化、空槽位静音;`GAIN_DB` 按文件响度修正 × 玩家音量 `user_volume`(设置模块);各场景 `_ready` 报槽位 |
| `ui/settings_panel.gd` | 标题页「设置」弹窗(第五个选项点开,CanvasLayer 遮罩 + 居中面板):音乐音量滑条 / 全屏 / 小机联动(= 无机器人模式开关)/ 小机维护 / 关闭;落 `SaveManager.settings`(重置进度不清),启动时 `Bgm._ready` 读音量、`Game._apply_window_settings` 恢复全屏 |
| `narrative/step_guide.gd` | 关内操作指引(纯函数):按棋盘事实挑下一条要提示的操作(pin/place/wire;v1.1 删了 fix/notebook),做过一次记进 `SaveManager.steps`;文案表 `TEXT` |
| `levels/level_solutions.gd` | 16 关脚本化解法(示答 / 小机代解 / 测试共用;正式版也要,别放 tests/) |
| `tests/` | headless 测试,126 例(含 `test_solver_exhaustive.gd` 穷举/随机不变量、`test_theme.gd` 字体符号扫描、`test_res_paths.gd` res:// 大小写审计);`test_base.gd` 提供 `check`/`f("A & B")` |

## 踩过的坑(改这些地方前必读)

- **假设口的边不是依赖**:封程机假设口→子证明→回到本机输入口,在节点图上
  像环但不是循环论证。`_topo_order`/`_propagate_hyps` 已把假设边排除出依赖、
  开局直接赋 `{自己}`。改环检测或辖域检查时别破坏这一点(有测试盯着)。
- **JSON 往返会变类型**:整数→浮点、字典键→字符串。`ProofGraph.from_dict`
  里已统一 `int()` 转回;新增序列化字段时照做。
- **新 class_name 不生效**:命令行跑脚本前需 `--import` 重建缓存(编辑器开着
  的话它会自己扫)。
- **求解是严格正向的,禁止反推**:`solve()` 不再做全局对称合一,而是按边把上游
  纹样用 `Unifier.match_into` 灌进下游模板、只绑**这条边入口模板里**的元变量
  (按口不按机:汇路机支路口 R 会成为假设 P 的别名,允许整机元变量就能顺着别名
  反绑 P,有 `test_branch_cannot_bind_or_elim_hypothesis` 盯着)。仪器输出只由
  输入 + 钉纹样决定;自由元变量所在的口由 `RuleSchema.pinnable` **白名单**标记
  (不是"含自由变量即可钉",否则封程机 P→Q 口会重复出按钮)。`match_into` 的
  判断顺序有讲究(模板侧可钉先于值侧刚性跳过,occurs check 不能省),动它前看
  `test_unifier.test_match_into_is_one_way`。环检测在传播之前,环上的边不参与传播。
- **`--script` 的 `_initialize` 里 root 还没进树**:`SceneTree.initialize()` 先调脚本 `_initialize` 再 `root._set_tree`,
  此时 `add_child` 到 root 的节点 `is_inside_tree()` 为假(AudioStreamPlayer.play / create_tween 直接报错)。
  `run_tests.gd` 开头已 `await process_frame`;新写 SceneTree 脚本照做。
- **存档里的钉是外部边界**:`from_dict` 只收"可钉口 + 全染色"的钉;含 `?` 的钉值
  会让 `Unifier.walk` 追自己死循环。
- **`AudioStreamWAV` 运行时设 `loop_mode` 必须同时设 `loop_end`**:导入器只在 `.import` 选了 Forward 时才写循环点,
  「Detect From WAV」+ 无 smpl 块的 wav 导入后 `loop_end=0`,只开 `loop_mode` 会让混音在第 0 帧就碰到循环末尾、
  混 1 帧即停(关内无声,`playing` 下一帧翻 false;只查 `loop_mode`/`playing` 的测试看不出来)。循环统一走
  `Bgm.set_looping`(没有循环点就整曲循环),有测试盯。
- **低功耗模式(`run/low_processor_mode`)下画面没变化就不重绘**:每帧要动的东西要么走 Tween/属性变化(渲染服务器会知道),
  要么在 `_process` 里自己改属性;新加 `_process` 必须 `set_process` 门控(空闲时关掉)并加进 `tests/test_perf_settings.gd`
  的 `PROCESS_ALLOWED` 白名单,`_process` 里禁 `queue_redraw`。`max_fps=60` 是硬上限,别删(vsync 在混合显卡笔记本上可能失效)。
- **GraphNode 的口只能在节点左右边缘、左右缩进对称**(`port_h_offset` 一个数管全部口,y = slot 行中心),想把口挪到别处
  (封程机臂内沿)只能靠 GraphEdit 三个虚函数:`_is_in_input/output_hotzone`(mouse = 局部坐标/zoom,矩形要自己按主题
  inner/outer extent 算)、`_get_connection_line`(端点两种坐标:正式连线 `(position_offset+口位)*zoom`、拖线预览
  `position+口位*zoom`;实现后贝塞尔也要自己出)。**`_draw_port` 在 C++ 绘制阶段被调、早于脚本 `_draw`**,自画端口
  必须放在最后一个子 Node2D(`PortLayer`)上,`_draw_port` 只留空壳压掉默认圆点。
- **GraphEdit 的口号是按 slot 顺序数的,不等于模型口号**(封程机假设口排第一排):板内所有信号进出都过
  `MachineNode.graph_out_port/model_out_port`;脚本/测试直接连线走 `session.connect_wire`,别调 `board._on_connection_request`。
- **节点里的 Button 要 `mouse_filter = PASS`**:STOP 会把右键也吃掉(右键删机失效),PASS 下左键仍归按钮、其余穿透到 GraphNode;
  真实输入测试点节点"中央"前先看那里是不是按钮(`visual_smoke_ui` H/I 段改点纹样)。

## 当前进度

M0 引擎 ✅ → API(ProofSession/PatternView)✅ → M1 灰盒板 ✅ → M2 编辑器/全规则 ✅ →
M3 内容层(关卡+存档+对话+笔记本)✅ → 实体机器人联动(固件/桥接/语音/校准)✅ →
交互改版(进关前全屏开场对话 StoryScene、右键删节点、无跳过键点击推进、
连线只留错误徽章、未连线口幽灵纹样)✅ → 删第五章(4 章 15 关)+ 严格正向求解
(自由纹样一律由玩家钉)✅ → **美术包接入**(2026-08-29:站酷小薇体、3840×2160 逻辑视口 PNG 原尺寸、
标题/选关/开发者信息/故事界面/仪器架/笔记抽屉全部换成美术图,节点内无公式文字;严格按
`information/art_spec_20260829/游戏样式美化.md`)✅ → **小机剧情弧 + 语音求助**(玩家说「请指导我/请帮帮我」小机回头到极限后代解;
电脑麦克风离线识别 `hardware/speech/`;开发者信息页「小机维护」面板可接入/刷固件/校准/设回头方向)✅ → **背景音乐槽位系统 + 标题曲**(2026-08-29:autoload Bgm,
标题/选关/开发者信息共用 `music/title.mp3`,关内四章暂共用 `music/level.wav`;补曲只放文件 + 填 `TRACKS` 一行,见 `music/音乐bgm位置.md`)✅ →
**正式剧情灌入 + 结局流程 + 小机弧改点**(2026-08-30:策划表 `剧情文件及美术补充/静语纹_四章剧情_无旁白版_v2.xlsx` 经
`tools/xlsx_to_csv.py` + `tools/import_dialogue.gd` 灌入 15 段正式台词(别名表头/「章-节」关卡号/左位「无」与全名/注意事项行自动跳过);
**4-3 = l16 通关后剧情**(`LevelDef.outro_dialogue`):l16 通关点「继续」→ 全屏 4-3 → 「感谢游玩」黑屏 → 开发者信息页从黑淡入;
小机 **3-1(l11)通关瞬间坏掉**(win cue = panic,代解通关也演)、3-2 起整段故障、**结局黑屏才修好**(calm),「look 模式」删除;
新增莉娅严肃立绘 `char_lia_serious.png`、场景别名 伦敦街上/诺拉房间)✅ →
**笔记条目换整页图**(2026-08-30:七台仪器 `assets/art/level/notebook/<rule_id>.png`,3840×2160 全屏导出透明底、
与打开的抽屉对齐原尺寸摆放;引擎不再渲染笔记文字,NotebookEntry 只剩 id+image;源图存档 `笔记本页面补充/`)✅ →
**Web 发布管线**(2026-08-30:export_presets「Web」预设(nothreads、排除素材源目录、build/.gdignore)、
Noto 两字形回退子集 回/·(Web 无系统字体,test_theme 盯)、开局最大化;`butler push` → yiyuanli.itch.io/textrix-veritatis)✅ →
**性能/功耗整治 + 无机器人模式**(2026-09-02:Windows 导出版十分钟过热+啸叫 → `project.godot` 帧率上限 60 + 低功耗模式 + 显式 vsync +
Compatibility 渲染器(删 d3d12);每帧脚本工作收敛(徽章跟随缓存引用、各 `_process` 用 `set_process` 门控);8 张大图补 mipmap;
「Windows Desktop」导出预设入库;`Robot.enabled` 无机器人模式(命令行 > settings > 平台默认仅 macOS 开;求助提示/「小机维护」按钮/道晚安全消失,
不连桥接不轮询;切回入口:标题页「设置」弹窗「小机联动」/ F9 面板,所有构建);守门 `tests/test_perf_settings.gd` + UI smoke S/T 节)✅ →
**关卡编排调整**(2026-09-02:第一章加第三纹 `A & B ⊢ A`(裸拆股关、无剧情、直进棋盘),4 章 16 关、l03 起 id 后移一位;
仪器**按关上架逐关累计**(`gen_levels.gd` `LEVELS` 末列 = 本关新上架:l02 并织 · l03 拆股 · l06 引渡 · l07 封程 · l11 岔纹 · l12 汇路 · l14 溃散,l01 无);
第二章 2-2/2-3 只对调题目(2-2 = `⊢ A > A` 封程裸机)、剧情按章-节位置不动;3-1 = l11、4-3 = l16;策划 xlsx/CSV 第一章节号同步后移(原 1-3/1-4 = 现 1-4/1-5);
存档带 `layout` 版本、不符则丢弃旧棋盘保留通关记录;`test_levels` 新增上架表/编排/剧情表↔tres 逐句/存档版本四条)✅ →
**关内操作指引**(2026-09-02,用户要求、美术文档没有 → 先纯文字:`narrative/step_guide.gd` 按棋盘状态在棋盘左下(求助提示上一行,
`STEP_HINT_*` 常量)提示下一步操作 —— 接错线断开/拆机 → 钉纹样 → 放仪器 → 拉线 → 有新仪器翻笔记;每条做过一次记进存档 `steps` 不再显示,
重置进度清掉;`LevelCatalog.debut_rules` 判新上架;`test_step_guide` 5 例 + UI smoke S 段)✅。
**像素对齐审查**(2026-09-02:用位置参考.png 模板匹配 / base.png 扫框线 / 预览图互相关量出引擎常量的错位并逐一改正——
故事界面露灰边(垫白底 + 清屏色改乳黄)、场景插图右 8 下 3、立绘压地板线 10、莉娅严肃图矮 6 px(按遮罩画布定位)、
笔记抽屉 (21,48)→(17,27)、翻页/夹子字号 52→82/78 且夹子按参考排成两行行距 92、收起露出 480→350、标题图与四选项、仪器架与按钮;
翻页整页图进关时预热;`tools/shot_4k.gd` 出 1:1 截图对照,`tests/test_art_alignment.gd` 固化基准;数字在 ART_INTERFACE §3.5)✅ →
**v1.1 交互调整**(2026-09-02,策划说明 `v1.1交互调整说明/`:①端口图形 插头/插座/接上整圆、拖线插头随鼠标;②依赖未消去假设的线整条假设色
(`SolveResult.edge_hyps` → `set_connection_activity`);③错误徽章 64 号白描边、接错的线 0.5 s 自动断开、徽章停 1 s 淡出(欠定保留);
④节点内部:行距 32、纹样边框按模板元变量着色(P 金 / Q 棕 / R 青,岔纹机两口各自钉色)、汇路机两色分割线、封程机凹形(假设口/输入口在两臂内沿,
板的三个虚函数接管口位,图口号↔模型口号换算)、「钉纹样」按钮进节点带底色 + 未钉口蚂蚁线(删「已钉」)、弹窗照 image 13 重排(纹样绘制 /
点选笔刷进行绘制 / 三个线描结构笔刷 / 清空·取消·确认,清空 = 擦画布、空画布确认 = 取消钉住,删挖回孔);⑤首次上架仪器的笔记进关自动翻到它那页
(每次进关都弹),操作指引删 fix/notebook 只剩 钉/放/拉。所有尺寸按示意图以纹样宽 128 / 预览宽 720 为尺折算后逐项量测定值(ART_INTERFACE §3.6);
headless 126/126,ui 200/200,m3 59/59,m2 3/3;做法与踩坑见 TUTORIAL 3.6)✅ →
**标题页「设置」弹窗**(2026-09-02,用户要求、美术文档没有 → 纯文字 + 常量留位:标题页第五个选项「设置」(与四项同列同间距)点开
`ui/settings_panel.gd` 居中弹窗,标题页本身不放控件;音乐音量滑条(`Bgm.user_volume`,当场生效)/ 全屏开关(`DisplayServer` 窗口模式,启动恢复)/
小机联动开关(= 无机器人模式,Web 不显示)/ 小机维护入口 / 关闭(Esc 也关);
全部落 `settings`;`tests/test_settings.gd` + `test_bgm` 音量例 + UI smoke T/S 节;TUTORIAL 3.7)✅。
更新接口见 `docs/CONTENT_INTERFACE.md`、`docs/ART_INTERFACE.md`;机器人手册见 `docs/ROBOT_API.md`;整体设计与改法教程见 `docs/TUTORIAL.md`。
关卡逐关总结、难度曲线诊断与 25 关重设计提案见 `docs/LEVEL_DESIGN.md`(提案关卡已在引擎上验证可解)。
全流程回归:`tests/visual_smoke_m3.gd`(16 关自动通关 + 结局到开发者页);UI 交互矩阵(真实输入):`tests/visual_smoke_ui.gd`。
