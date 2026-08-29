# 《She Nicest》完整开发计划 + Godot 实现教学

> 本文档是后续实现的执行蓝本兼团队 Godot 上手教材。
> 依据:`information/自然演绎游戏提案.pdf` + incredible.pm 机制调研 + Godot 4.7 stable API 核实。
> 已确认决策:节点编辑器基于 **GraphEdit**;逻辑范围含 **¬/⊥**;素材走**程序化 + SVG 手绘**。

---

## 0. 项目现状与目标

**现状**:空白 Godot 4.7 工程(Forward Plus)。`project.godot` 未设主场景;`main.gd` 为空 stub(可删)。

**目标**:复刻 The Incredible Proof Machine 的节点化自然演绎证明玩法,并按提案做概念换皮:

| 逻辑概念 | 游戏概念 | 视觉 |
|---|---|---|
| 原子命题 A | 静语丝(纯色) | 纯色矩形 |
| A ∧ B | 并织纹 | 矩形**竖分**(A 左 B 右) |
| A ∨ B | 岔纹 | 矩形**对角分**(A 左上三角,B 右下三角) |
| A → B | 迭层纹 | 矩形**横分**(A 上 B 下) |
| ⊥ | 焦纹(烧毁的布) | 焦黑底 + 破洞 |
| ¬A(= A→⊥) | 禁纹 | 自动涌现:A 在上、焦布在下 |
| 推理规则 | 黄铜仪器 | 见 §4.4 规则表 |
| 证明图 | 织机工作台 | GraphEdit 画布 |

**incredible.pm 核心机制拆解**(复刻对象):
- 侧栏方块(假设、规则、结论)拖到无限画布,输出口→输入口连线。
- 每台放置的规则方块 = 规则模式的**新实例**(元变量全局重命名,防跨实例捕获)。
- 每条连线 = 一条合一方程;全盘一阶合一推导每个端口的具体命题。
- 错误反馈:合一冲突(☠)、欠定(?)、环、未连输入、逃逸的局部假设。
- →I 与 ∨E 暴露**局部假设输出口**,只能在汇入本机对应前提输入口的子证明内使用(辖域检查)。
- 胜利判定:结论已连 + 其祖先子图完备、一致、无环、辖域正确、全部命题落地(无元变量)。
- 原版无独立否定规则:**¬A ≡ A→⊥**,只有 `falseE`(爆炸原理)与经典章节的 `TND`(排中律;本作已删,见下)。

**总体架构原则**:严格 Model/View 分离。`ProofGraph`(纯 GDScript 逻辑层,零场景依赖)是唯一 source of truth;GraphEdit 只是投影。每次编辑 → 改 model → `solve()` → view 按 `SolveResult` 刷新。保证 headless 测试、存档、撤销、后期换 UI 全部不受 UI 绑架。

---

## 1. Godot 速成 — 本项目会用到的全部引擎概念

> 面向没写过 Godot 的成员。只讲本项目用到的,配最小代码;每条都会在后面的里程碑里实际用上。

### 1.1 场景、节点、脚本

- Godot 的世界是**节点树**:一切东西(按钮、图片、逻辑容器)都是 Node 的子类。一棵保存好的节点树 = **场景**(`.tscn` 文件),场景可以互相**实例化**嵌套(类似 prefab)。
- **脚本**(`.gd`)挂在节点上扩展它:FileSystem 面板右键 → New Script,或在场景面板选中节点点"挂脚本"图标。脚本第一行 `extends 某节点类`;写 `class_name Foo` 则注册为全局类型,任何脚本可直接 `Foo.new()`——本项目逻辑层全部这样用,**不挂场景**。
- 生命周期回调:`_ready()`(入树时)、`_process(delta)`(每帧)、`_draw()`(重绘时,见 1.3)、`_gui_input(event)`(Control 收输入)。
- **信号 = 事件**。声明、发射、连接:

```gdscript
signal pattern_committed(f: Formula)      # 声明
pattern_committed.emit(formula)           # 发射
editor.pattern_committed.connect(_on_committed)   # 代码里连接(本项目统一用代码连,不用编辑器连线,便于审查)
```

- 常用语法:`@onready var lbl: Label = %Title`(`%` 引用场景里标了"唯一名称"的节点);`@export var speed := 1.0`(变量出现在 Inspector 面板,可视化调参)。

### 1.2 Control 与 UI 布局

- 2D 游戏 UI 全用 **Control** 系节点。布局靠**容器**自动排:`VBoxContainer`/`HBoxContainer`(纵横排)、`PanelContainer`(带底板)、`MarginContainer`(留白)、`ScrollContainer`。子节点的 `size_flags` 控制拉伸。**不要手摆坐标**,让容器排。
- 弹窗用 `PopupPanel`(纹样编辑器用):`popup_centered(Vector2i(400, 300))` 弹出,失焦自动收起。
- 富文本用 `RichTextLabel`(开 `bbcode_enabled`),对话打字机效果就是逐帧加 `visible_characters`。

### 1.3 自定义绘制(纹样渲染的核心手段)

任何 Control 覆写 `_draw()` 即可用画笔 API 自由绘制;数据变了调 `queue_redraw()` 请求重绘(引擎会在下一帧调 `_draw`):

```gdscript
func _draw() -> void:
    draw_rect(Rect2(0, 0, 64, 64), Color.RED)                    # 实心矩形
    draw_line(Vector2(0,0), Vector2(64,64), Color.BLACK, 3.0)    # 线段(宽 3px)
    draw_colored_polygon(PackedVector2Array([a, b, c]), color)   # 三角形(∨ 的对角分割用)
    draw_polyline_colors(points, colors, 2.0)                    # 折线(M4 丝带线用)
```

坐标原点是该 Control 左上角,`size` 是当前尺寸。命题纹样、连线丝带、错误徽章底全部用这套 API 程序化画出,**不需要任何图片文件**。

### 1.4 Resource 与 .tres(关卡/对话的数据格式)

- **Resource = 可保存成文件的数据对象**。自定义:脚本 `extends Resource` + `class_name` + `@export` 字段;然后在 FileSystem 右键 → New Resource → 选你的类 → 存成 `.tres`;双击即可在 Inspector 填字段(数组、嵌套 Resource、颜色都有现成编辑控件)。
- 这就是本项目的"关卡编辑器"和"对话配置器"——**不用自己写工具,Inspector 就是编辑器**。代码里 `load("res://levels/data/ch1/l01.tres")` 即得到类型化对象。
- `.tres` 是文本格式,git 友好。

### 1.5 Autoload、Tween、输入

- **Autoload = 全局单例**:Project Settings → Globals → Autoload,把 `game/game.gd` 注册为 `Game`,之后任何脚本直接写 `Game.current_level`。只给"游戏流程"这一个 autoload,逻辑层保持可 new。
- **Tween = 代码驱动的补间动画**:`create_tween().tween_property(node, "modulate:a", 1.0, 0.3)`。胜利绿光、打字机、翻页都用它,不用动画编辑器。
- 快捷键:Project Settings → Input Map 定义动作(如 `undo`),代码里 `Input.is_action_just_pressed("undo")` 或在 `_unhandled_input` 里查 `event.is_action_pressed("undo")`。

### 1.6 运行、调试、headless 测试

- 编辑器里 **F5** 跑主场景、**F6** 跑当前场景;`print()`/`push_error()` 输出在底部 Output 面板;运行中可在 Remote 树里实时看节点状态。
- 命令行(本项目 CI/测试的方式):

```bash
# macOS 下 godot 可执行文件通常是:
alias godot="/Applications/Godot.app/Contents/MacOS/Godot"
godot --path /Users/yiyuanli/she-nicest                 # 跑游戏
godot --headless --path . --script res://tests/run_tests.gd   # 无窗口跑测试,退出码=失败数
```

- 测试脚本骨架(不依赖任何插件):

```gdscript
# tests/run_tests.gd
extends SceneTree
func _initialize() -> void:
    var fails := 0
    for script_path in ["res://tests/test_formula.gd", ...]:
        var t = load(script_path).new()
        for m in t.get_method_list():
            if m.name.begins_with("test_"):
                if t.call(m.name) == false: fails += 1   # 约定: 失败返回 false
    quit(fails)
```

---

## 2. 目录结构与工程配置

```
res://
  logic/       formula.gd  formula_parser.gd  rule_schema.gd  rules.gd
               unifier.gd  proof_graph.gd  solve_result.gd
  pattern/     pattern_view.gd  pattern_editor.gd  pattern_editor.tscn
  board/       proof_board.gd/.tscn  machine_node.gd/.tscn
               wire_overlay.gd  pattern_chip.tscn  palette_panel.gd/.tscn
  levels/      level_def.gd  level_catalog.gd  data/ch1/*.tres ... data/ch5/*.tres
  narrative/   dialogue_res.gd  dialogue_line.gd  dialogue_box.gd/.tscn
               notebook_entry.gd  notebook_ui.gd/.tscn
  game/        game.gd (autoload "Game")  save_manager.gd  undo_stack.gd
  ui/          main_menu.tscn  level_select.gd/.tscn  level_scene.gd/.tscn
  assets/      svg/machines/  svg/ui/  fonts/  shaders/
  tests/       run_tests.gd  test_formula.gd  test_parser.gd  test_unifier.gd
               test_graph.gd  test_scope.gd  test_serialize.gd
  theme/       main_theme.tres
```

`project.godot` 增补:`run/main_scene = res://ui/main_menu.tscn`;autoload `Game`。删除根目录 `main.gd`。

---

## 3. M0 — 逻辑引擎(纯 RefCounted,headless 可测)

> 🔧 **Godot 指引**:本里程碑**完全不碰编辑器**——7 个 `.gd` 文件全部 `extends RefCounted` + `class_name`,不挂任何场景。RefCounted 是自动引用计数的轻量对象(相当于普通类),`Formula.new()` 即用。用 §1.6 的 headless 命令跑测试,写一条过一条。

### 3.1 `logic/formula.gd` — Formula AST

**决策:不可变 RefCounted 类 + 规范串 key**(而非嵌套 Array/Dictionary)。规范前缀式字符串一次解决结构相等、Dictionary 哈希、序列化三件事;不可变性消灭共享别名 bug。

```gdscript
class_name Formula extends RefCounted
enum Kind { ATOM, META, AND, OR, IMP, BOT }
var kind: int
var name: StringName          # ATOM: "A"; META: 全局唯一 "?17"
var left: Formula             # 二元结构子式(AND/OR/IMP)
var right: Formula
var _key: String = ""         # 惰性缓存规范串,如 "&(A,>(B,?3))"

static func atom(n: StringName) -> Formula
static func meta(n: StringName) -> Formula
static func conj(a: Formula, b: Formula) -> Formula   # 同理 disj / imp / bot()
func key() -> String                    # 规范串(缓存)
func equals(o: Formula) -> bool         # key() == o.key()
func is_ground() -> bool                # 不含 META
func metas() -> Array[StringName]
func contains_meta(m: StringName) -> bool
func subst(s: Dictionary) -> Formula    # {StringName: Formula} → 新树,不改自身
func rename_metas(map: Dictionary) -> Formula   # 实例化用
func depth() -> int                     # 渲染分割线粗细用
```

### 3.2 `logic/formula_parser.gd` — 解析器

递归下降,关卡文件、存档、测试共用一种文本格式:

```gdscript
class_name FormulaParser
# 语法: atom := [A-Za-z][A-Za-z0-9_]* ; "false"/"⊥" → BOT
# 优先级: & 最高, | 次之, > 最低且右结合; 括号任意
# parse("A & B > C | D") == imp(conj(A,B), disj(C,D))
static func parse(src: String) -> Formula      # 失败返回 null 并记录错误位置
static func to_text(f: Formula) -> String      # 带最少括号的人类可读输出
```

### 3.3 `logic/rule_schema.gd` — 规则模式

```gdscript
class_name RuleSchema extends RefCounted
var id: StringName            # &"imp_intro"
var cn_name: String           # "封程机"
var inputs: Array[PortSpec]
var outputs: Array[PortSpec]

class PortSpec:
    var template: Formula     # 用模式局部元变量 P,Q,R 写的模板
    var is_hypothesis: bool   # 局部假设输出口(仅 output)
    var scope_input: int = -1 # 该假设绑定到本机哪个输入口(index)
```

### 3.4 `logic/rules.gd` — 七台机器静态表

| id | 机器名 | 输入 | 输出 | 局部假设 |
|---|---|---|---|---|
| `and_intro` | 并织机 | P, Q | P∧Q | — |
| `and_elim` | 拆股机 | P∧Q | P, Q | — |
| `or_intro` | 岔纹机 | P | P∨Q₁, Q₂∨P | —(两输出口用**不同**元变量,独立可用) |
| `or_elim` | 汇路机 | P∨Q; R(散口1); R(散口2) | R | hyp P→输入1, hyp Q→输入2 |
| `imp_intro` | 封程机 | Q(散口0) | P→Q | hyp P→输入0 |
| `imp_elim` | 引渡机 | P→Q, P | Q | — |
| `false_elim` | 溃散机 | ⊥ | P | — |

(中文机器名沿用提案;溃散机为命名提案,可改。`tnd` 两仪机与第五章已删除:排中律在节点证明里对玩家过于诡异。)

**可钉口(pinnable)**:输出里不由任何输入决定的"自由元变量"由玩家用钉纹样窗口赋值——封程机假设口 P、
岔纹机上口的 Q / 下口的 R、溃散机的 P。汇路机的 P/Q/R 全由输入正向决定,无可钉口。

**实例化 = 元变量重命名(防捕获的关键)**:`ProofGraph` 持全局单调计数器;放置机器时对模式全部模板做 `rename_metas({P: ?n, Q: ?n+1, ...})`。两台并织机的 P 绝不重名。封程机假设口初始即新鲜元变量;玩家用纹样编辑器"钉住"后追加方程(§3.6)。

### 3.5 `logic/unifier.gd` — 一阶合一

```gdscript
class_name Unifier
# 按插入顺序逐条合一;失败方程记入 conflicts 后丢弃继续
# (冲突定位顺序稳定 → UI 标记不闪变;剩余方程仍尽量传播信息)
static func solve(eqs: Array) -> Dictionary
#   返回 { subst: Dictionary[StringName, Formula], conflicts: Array[int] }
static func unify_one(a: Formula, b: Formula, subst: Dictionary) -> bool
static func walk(f: Formula, subst: Dictionary) -> Formula    # META 追到代表元
static func resolve(f: Formula, subst: Dictionary) -> Formula # 递归完全代入
```

算法要点(三类经典 bug 各有专项测试):
1. `unify_one`:先 `walk` 两侧;同名 META → true;一侧 META → **occurs check**(对 `resolve(另一侧)` 做 `contains_meta`)后绑定;kind 不同 → false;ATOM 比名;BOT → true;二元结构递归左右。
2. **不做逐条回代**:绑定时不改已有绑定,读取时永远 `walk` 到底,最后 `resolve` 统一代入 — 规避代换合成顺序 bug(union-find 风格)。
3. occurs check 失败即冲突(`?a ≐ ?a∧B` 必败,防无限结构/栈溢出)。

### 3.6 `logic/proof_graph.gd` — 棋盘模型与求解管线

```gdscript
class_name ProofGraph extends RefCounted

class ProofNode:
    var id: int
    var kind: int                     # ASSUMPTION / GOAL / RULE
    var rule_id: StringName
    var port_in: Array[Formula]       # 实例化后的输入口命题
    var port_out: Array[Formula]      # 实例化后的输出口命题
    var pinned: Dictionary            # {hyp_port_idx: Formula}

# 边 = Vector4i(from_id, from_port, to_id, to_port) — 值类型可哈希,直接做 Dictionary key

func add_rule_node(rule_id: StringName) -> int
func add_assumption_node(f: Formula) -> int
func add_goal_node(f: Formula) -> int
func remove_node(id: int)                       # 连带删边
func add_edge(e: Vector4i) -> bool              # 拒绝:输入口已占用 / 自环
func remove_edge(e: Vector4i)
func pin_hypothesis(node_id: int, port: int, f: Formula)
func solve() -> SolveResult
func to_dict() -> Dictionary                    # 公式存 key() 串
static func from_dict(d: Dictionary) -> ProofGraph
```

**`solve()` 五步管线**(每次编辑后全盘重解;<100 节点毫秒级,无需增量化):

1. **钉纹样赋值**:每个 pinned 口把它的自由元变量直接写进 subst(`?k := 玩家纹样`)。
2. **严格正向传播到不动点**:反复遍历边,`Unifier.match_into(resolve(from口), to口模板, subst, 下游节点的元变量)`
   ——只绑下游自己的元变量,上游未定的部分刚性跳过;两侧具体结构对不上才标 `CONFLICT`。
   **绝不从下游反推上游**:仪器输出只由输入 + 钉纹样决定。绑定单调增,轮数有上界。
3. **环检测**:节点图 Kahn 拓扑排序;残余节点在环上,其边标 `CYCLE`。
4. **辖域检查(escaped hypothesis)— 前向传播 + 定点消除**:
   - `HypId = Vector2i(node_id, hyp_port_idx)`。
   - 沿拓扑序为每条边计算集合 `hyps(e)`:
     - 从假设口发出的边:`{该口的 HypId}`;
     - 从普通输出口发出的边:本节点全部输入边 hyps 之并——**但**进入节点 n 输入口 q 的边,先剔除满足 `h.node == n 且 h.scope_input == q` 的 h(= 在指定放行口封存)。
   - 该规则天然覆盖:多层封程机嵌套(每个 h 只在自己的 (node, scope_input) 处消除)、汇路机双假设互窜(P 假设流入 Q 的散口不消除,继续传播)、内层子证明合法使用外层假设(随流携带,最终在外层封存口消除)。环上节点跳过。
   - **报错**:进入 GOAL 的边 hyps ≠ ∅ → 标 `ESCAPED_HYP`。
5. **胜利判定**:从 GOAL 沿输入边反向 BFS 得祖先集;要求:GOAL 输入已连;祖先集内每台机器每个输入口有边;祖先集边无 CONFLICT/CYCLE/ESCAPED;所有端口 `resolve` 后 `is_ground()`;进入 GOAL 的边 hyps 为空。全满足 → `solved = true`。

### 3.7 `logic/solve_result.gd`

```gdscript
class_name SolveResult
var port_values: Dictionary   # Vector2i(node, port) -> Formula(resolve 后,可含 META)
var edge_status: Dictionary   # Vector4i -> OK | CONFLICT | UNDERSPEC | CYCLE | ESCAPED_HYP
var missing_inputs: Array     # 祖先链上未连输入口
var solved: bool
```
`UNDERSPEC` = 该边任一侧 resolve 后仍含 META("?"徽章,不算硬错误但阻断胜利;正向语义下通常意味着上游有可钉口没钉)。

**M0 验收**:headless 全绿;脚本化证明 `A∧B ⊢ B∧A` 与 `⊢ A→(B→A)`(含钉假设)通过。

---

## 4. M1 — 灰盒证明板(GraphEdit)

> 🔧 **Godot 指引:GraphEdit 怎么用**
> 1. 新建场景,根节点选 **GraphEdit**,挂 `proof_board.gd`(`extends GraphEdit`),存为 `board/proof_board.tscn`。
> 2. **GraphNode 是 GraphEdit 的孩子**:`add_child(machine_node)` 即出现在画布上,位置用 `position_offset`(画布坐标,非屏幕坐标)。
> 3. **端口 = GraphNode 的"行"**:GraphNode 的每个直接子 Control 是一行(slot);`set_slot(行号, 左口开关, 左类型, 左颜色, 右口开关, 右类型, 右颜色)` 决定这一行左右有没有接口。所以"一行 = 一个 HBoxContainer(标签 + 迷你 PatternView)",几行就有几个口。
> 4. **连线不会自己发生**:玩家拖线时 GraphEdit 只发 `connection_request(from, from_port, to, to_port)` 信号,**你自己决定**是否调 `connect_node(...)` 落地——这正好是我们把合法性交给 ProofGraph 裁决的挂点。`disconnection_request` 同理。
> 5. 开箱即得:框选、多选拖动、`zoom`、`minimap_enabled = true`、`right_disconnects`。记得 `add_valid_connection_type(0, 0)` 与 `add_valid_left_disconnect_type(0)`(允许从输入口摘线)。
> 6. **拖放**:palette 条目脚本覆写 `_get_drag_data(pos)`(返回 `{rule_id: ...}` 并 `set_drag_preview(小图)`);ProofBoard 覆写 `_can_drop_data`/`_drop_data`,落点换算画布坐标 `(pos + scroll_offset) / zoom`。

### 4.1 GraphEdit API 速查(已对 Godot 4.7 stable 文档核实)

| 需求 | API |
|---|---|
| 连线请求/断开 | `connection_request`、`disconnection_request`、`connection_to_empty/from_empty`、`connection_drag_started/ended` |
| 类型化端口 | `GraphNode.set_slot(...)` + `GraphEdit.add_valid_connection_type(0,0)` |
| 连线渲染 | `connection_lines_thickness/curvature`;virtual `_get_connection_line()`(重塑线形,M4 丝线下垂弧);`get_connection_line()` 取折线;`get_closest_connection_at_point()`;`set_connection_activity()` 流光 |
| 视图 | `minimap_enabled`、`zoom/zoom_min/zoom_max`、`snapping_enabled`、`scroll_offset(_changed)` |
| 删除 | `delete_nodes_request(Array[StringName])` |
| 端口定制 | `get_input/output_port_position/...`、virtual `_draw_port()`、`get_titlebar_hbox()` |
| **限制** | 连线本体不能贴纹理/挂控件(→ §4.2 WireOverlay);端口仅左入右出、水平流向(MVP 接受,美术把线画成下垂丝线) |

**GraphEdit 不强制、必须由 model 裁决的事**:单输入口多线(`connection_request` 里先断旧线)、自环、连接合法性。所有 GraphEdit 调用**收口在 `proof_board.gd` 单文件**,防 4.x API 漂移扩散。

### 4.2 `board/wire_overlay.gd` — 连线视觉叠加层

GraphEdit 的 full-rect 子 Control(`mouse_filter = MOUSE_FILTER_IGNORE`,置于连线层上):
- **M1**:每条连线中点放一枚 **PatternChip**(小 PatternView + 黄铜边框):位置取 `get_connection_line()` 折线中点;chip 显示 `SolveResult.port_values` 推得的纹样;错误徽章叠加(冲突=骷髅纹章、欠定=问号线轴、逃逸假设=剪刀、环=衔尾蛇圈)。
- 刷新时机:solve 后、`scroll_offset_changed`、zoom 变化、节点拖拽期间每帧重排(便宜)。
- **M4**:原生线调细弱化,`_draw()` 沿折线 `draw_polyline_colors` 画多股平行偏移"丝带";覆写 `_get_connection_line` 加悬垂控制点。交互仍全部白嫖 GraphEdit。

### 4.3 场景与节点

- `board/proof_board.gd/.tscn`(extends GraphEdit):持 `graph: ProofGraph`;信号转接 → model 操作 → `solve()` → `_refresh_view(result)`。GraphNode 命名 `"n%d"` 与 ProofNode id 双向映射。
- `board/machine_node.gd/.tscn`(extends GraphNode):按 RuleSchema 建 slot 行,每行迷你 PatternView 实时显示该口 `port_values`;假设口线轴图标 + 特殊 slot 色;封程机经 `get_titlebar_hbox()` 加"绘假设"按钮(M2 接编辑器)。
- 假设块 = 单输出 GraphNode(大 PatternView);结论块 = 单输入 + 金色目标框,solved 时全板绿光(Tween 调 modulate / shader 微光)。
- `board/palette_panel.gd/.tscn`:左侧栏按关卡 `allowed_rules` 列机器;拖放 + `popup_request` 右键菜单两种放置方式。
- `ui/level_scene.tscn`:board + HUD(目标纹样、重置、返回)组装;M1 硬编码一关。

**M1 验收**:鼠标拖放并织机/拆股机完成 `A∧B ⊢ B∧A`,胜利绿光;故意接错见骷髅徽章。

---

## 5. M2 — 全规则、纹样编辑器、辖域 UX、撤销

> 🔧 **Godot 指引**:纹样全靠 §1.3 的 `_draw()`;编辑器交互用 `_gui_input(event)` 收点击(`event is InputEventMouseButton and event.pressed`),配 `hit_path` 判断点在哪个子孔;弹窗用 PopupPanel;撤销栈就是普通 GDScript 数组存 Callable,没有引擎魔法。

### 5.1 `pattern/pattern_view.gd` — 递归纹样渲染(纯 procedural,零图像资产)

```gdscript
class_name PatternView extends Control
@export var atom_colors: Dictionary    # StringName -> Color,关卡注入;缺省 hash→HSV
var formula: Formula : set = _set_formula   # set 后 queue_redraw()

func _draw() -> void: _draw_f(formula, Rect2(Vector2.ZERO, size), 0)
# _draw_f 分派:
#   ATOM: draw_rect 纯色
#   META: "未染纱" — 亚麻底色 + 循环 draw_line 斜向织线(hatch)
#   BOT:  焦黑底 + 不规则破洞(固定种子预生成噪声点,draw_circle 挖洞色)
#   AND:  竖分,左 left 右 right,递归;中缝 draw_line
#   IMP:  横分,上 left(前件) 下 right(后件)
#   OR:   对角分:draw_colored_polygon 左上三角=left、右下三角=right,对角 draw_line
#   分割线宽 = max(1.0, base_w * pow(0.62, depth));depth > 6 画省略织纹止损
static func hit_path(f: Formula, rect: Rect2, point: Vector2) -> Array[int]
# 与绘制同一套递归几何 → 命中检测(返回子式路径),PatternEditor 用
```

### 5.2 `pattern/pattern_editor.gd/.tscn` — 挖孔式假设编辑器(绑定封程机)

初始一个"未染孔"(META 渲染);点任意孔 → 浮出小面板:本关原子色板 + 三种分割按钮(并织=∧ / 岔纹=∨ / 迭层=→,⊥ 解锁后出现);选分割则孔裂为两个子孔;点已染区域可重置为孔。内部维护一棵带 HOLE 叶的临时树,所见即所得。

```gdscript
class_name PatternEditor extends Control   # PopupPanel 内
signal pattern_committed(f: Formula)       # 全部孔填满才允许确认
func open_for(atoms: Array[StringName], initial: Formula = null)
```

提交 → `ProofGraph.pin_hypothesis()` → solve → 刷新。

### 5.3 辖域 UX 与其余规则

- 逃逸假设:`ESCAPED_HYP` 边红色 + 剪刀徽章;假设口 hover 高亮其合法汇入口(同机对应输入口)。
- 接入引渡机/岔纹机/汇路机/溃散机;汇路机双散口 slot 用不同强调色区分对应假设口。

### 5.4 `game/undo_stack.gd` — 撤销/重做

命令模式作用于 **ProofGraph 而非 GraphEdit**:自写 ~30 行栈,存 `{do: Callable, undo: Callable}`(AddNode / RemoveNode(含其边) / AddEdge / RemoveEdge / PinHypothesis / MoveNode);执行后 view 从 model 重同步。节点移动用 `begin_node_move`/`end_node_move` 信号定界,合并连续拖拽为单条命令。Input Map 注册 undo/redo(Ctrl+Z / Ctrl+Shift+Z)。

### 5.5 棋盘序列化

`ProofGraph.to_dict()/from_dict()` + view 层补充节点位置 `{id: Vector2}`;进关恢复。专项测试:序列化→反序列化→solve 结果一致。

**M2 验收**:完成 `⊢ A→(B→A)`(嵌套双封程)、`A∨B ⊢ B∨A`(汇路)、`⊥ ⊢ A`;假设逃逸见剪刀红标;撤销/重做全操作可用;重进关卡棋盘恢复。

---

## 6. M3 — 内容层:关卡、存档、对话、笔记本

> 🔧 **Godot 指引**:本里程碑主要练 §1.4 的自定义 Resource——`LevelDef`/`DialogueRes` 写好后,策划就在 Inspector 里配关卡和台词,不写代码。存档用 `FileAccess.open("user://save.json", FileAccess.WRITE)` + `JSON.stringify/parse_string`(`user://` 是引擎提供的跨平台可写目录)。

### 6.1 关卡资源

**决策:.tres Resource + 公式存规范串**(Inspector 可编辑、类型化、热重载;字符串由 FormulaParser 解析,与存档/测试同一格式)。

```gdscript
class_name LevelDef extends Resource
@export var id: StringName
@export var title: String
@export var assumptions: Array[String]        # ["A & B"]
@export var goal: String                      # "B & A"
@export var allowed_rules: Array[StringName]
@export var atom_colors: Dictionary           # {"A": Color(...)}
@export var intro_dialogue: DialogueRes
@export var notebook_unlocks: Array[StringName]
```

`LevelCatalog extends Resource`:`Array[SessionDef]`(章节名 + `Array[LevelDef]`)。数据放 `levels/data/ch*/*.tres`。

### 6.2 关卡表(≈16 关,按 incredible.pm session 1–5 递进;抓取自原版 sessions.yaml)

- **第一章·并织**(and_intro/and_elim):`A ⊢ A`(教学连线);`A, B ⊢ A∧B`;`A∧B ⊢ B∧A`;`A∧(B∧C) ⊢ (A∧B)∧C`
- **第二章·封程**(+imp):`A, A→B ⊢ B`;`A→B, B→C ⊢ A→C`;`⊢ A→A`(首次钉假设教学);`⊢ A→(B→A)`;`A∧B→C ⊢ A→(B→C)`(柯里化)
- **第三章·岔纹**(+or):`A ⊢ A∨B`;`A∨B ⊢ B∨A`;`(A→C)∧(B→C) ⊢ (A∨B)→C`
- **第四章·焦纹**(+false_elim):`⊥ ⊢ A`;`A→B ⊢ (B→⊥)→(A→⊥)`(逆否);`A∧(A→⊥) ⊢ B`
- ~~第五章·两仪(+tnd)~~ 已删除:排中律在节点证明里过于诡异,矛盾消除已够展开剧情。

叙事挂点:第一~二章工坊学艺 → 第三~四章档案室发现同构(笔记本揭示)→ 第四章末小机异常(glitch)收束。

### 6.3 `game/save_manager.gd` — 存档

`user://save.json`(JSON 而非 ConfigFile,因需嵌套棋盘结构):
`{ solved: [level_id...], boards: { level_id: graph.to_dict() + node_positions }, notebook_seen: [...] }`。

### 6.4 对话与笔记本(**自研,不用 Dialogic** — 需求仅线性对话,插件体量/版本迁移成本不值)

- `DialogueRes extends Resource`:`@export var lines: Array[DialogueLine]`;`DialogueLine`:speaker / text(BBCode) / portrait(Texture2D) / side(左右)。**引擎内配置器第一阶段 = Inspector 本身**;策划量大再补 `EditorInspectorPlugin` 表格化。
- `dialogue_box.tscn`:CanvasLayer,打字机(`RichTextLabel.visible_characters` + Tween),点击加速/跳过,`signal finished`;关卡入场由 `Game` autoload 播 `intro_dialogue`。
- 笔记本:`NotebookEntry`(id / title / body_bbcode / demo_formula: String — demo 用 PatternView 现场渲染);`notebook_ui.tscn` 皮面书翻页;后期"同构揭示"条目并排 PatternView 与符号推理(`A ∧ B ⊢ …`)。解锁由 `notebook_unlocks` 驱动,新条目角标。
- `ui/level_select.tscn`:章节页 + 关卡蜡封印章(已解=金印);`ui/main_menu.tscn` 极简。

**M3 验收**:主菜单→选关按章节推进 16 关全通;中途退出重进恢复;笔记本随章节解锁;入场对话可跳过。

---

## 7. M4 — 美术与素材制作方案(程序化 + SVG 手绘)

> **2026-08-29 更新**:美术已交付 PNG 美术包(站酷小薇体 + 标题/选关/故事/仪器架/笔记底图),
> 本节的 SVG 手绘方案作废;现行接口见 `docs/ART_INTERFACE.md`,逻辑视口改为 3840×2160、图片原尺寸使用。

> 🔧 **Godot 指引**:
> - **SVG 导入**:把 `.svg` 拖进 `assets/svg/`,Godot 自动导入为 Texture2D;选中文件 → Import 面板把 `svg/scale` 设 2.0(高分屏清晰)+ 开 mipmaps → Reimport。
> - **九宫格**:新建 `StyleBoxTexture`,指定贴图并把四边 margin 设 24px → 面板任意拉伸不糊角;GraphNode 的机身就是在 Theme 里覆写它的 `panel`/`titlebar` StyleBox。
> - **Theme**:新建 `theme/main_theme.tres`,在里面按控件类型统一配字体、StyleBox、颜色;Project Settings → GUI → Theme → Custom 指向它,全游戏生效,无需每个控件手调。
> - **canvas_item shader**(织物质感):材质里 New ShaderMaterial → shader 写 `shader_type canvas_item; void fragment() { COLOR = texture(TEXTURE, UV) * 经纬纹理(UV); }` 级别的小函数即可,叠在 PatternView 上。

### 7.1 程序化素材(代码生成,零图像文件)

| 素材 | 实现 |
|---|---|
| 命题纹样 | PatternView `_draw()` 递归(§5.1),四处复用(chip/机器口/编辑器/笔记本) |
| 连线丝带 | WireOverlay 沿 `get_connection_line()` 折线画多股平行偏移线;`_get_connection_line` 覆写加下垂弧 |
| 织物质感 | `assets/shaders/weave.gdshader`:细密经纬 + 布纹噪声 |
| 胜利/流光 | `set_connection_activity()` + 结论块金光 |
| 错误徽章底 | 简单 draw + SVG icon |

### 7.2 SVG 手绘清单(Inkscape)

| 类别 | 内容 | 数量 |
|---|---|---|
| 机器机身 | 黄铜九宫格面板:工坊木+黄铜 / 学院黄铜+墨 等变体 | 3 |
| 机器徽记 | 封程/引渡/并织/拆股/岔纹/汇路/溃散 + 线轴(假设)+ 目标织机 | 9 |
| 端口图标 | 普通口(梭子)、假设口(线轴) | 2 |
| 错误徽章 | 骷髅纹章、问号线轴、剪刀、衔尾蛇(环) | 4 |
| UI 主题 | 羊皮纸面板、黄铜按钮三态、蜡封印章(未解/已解)、笔记本皮面+纸页、对话框 | ~8 |

**制作规范**:128px 设计网格、2px 描边基准;命名 `assets/svg/machines/imp_intro.svg` 式;九宫格 margin 统一 24px;调色限定黄铜三阶(#B08D57/#8C6F45/#5C4A2E)+ 墨 + 羊皮纸。

### 7.3 字体与调色板

- 字体:思源宋体(CJK)+ EB Garamond(拉丁),OFL 许可,放 `assets/fonts/`。
- 原子调色板 6–8 色,**色觉友好**:亮度差为主通道(红/蓝为提案基准),后期可叠微织纹冗余编码;⊥ 焦黑独占。
- 人物立绘/背景:本阶段**剪影占位**,风格锚定提案情绪板,后续外包/另制,不阻塞主线。

**M4 验收**:全 UI 换装无默认灰;连线呈丝线感;截图气质符合提案美术关键词。

---

## 8. 测试与验证(贯穿各里程碑)

Headless 命令与 `run_tests.gd` 骨架见 §1.6。**必备用例**:

- formula:key 规范性、equals、subst 不可变性、depth
- parser:优先级、右结合、括号、⊥、错误定位、`parse(to_text(f)).equals(f)` 往返
- unifier:基本合一、occurs check(`?a ≐ ?a∧B` 必败)、双机模式变量隔离、方程顺序打乱后解一致、冲突定位稳定
- graph:`A∧B ⊢ B∧A` 全流程 solved、未连输入不胜利、环判定、`⊢ A→(B→A)` 嵌套封程
- scope:汇路机双假设各自辖域、假设扇出一支到 GOAL 一支正常封存(必须报 ESCAPED)、假设流入自己引入机的错误端口、多层封程嵌套合法使用外层假设(必须通过)
- serialize:to_dict → from_dict → solve 一致

UI 验证:每个里程碑 `godot --path .` 实跑对应验收清单(§4–§7 各节末)。

---

## 9. 风险与坑(实现时对照)

1. **GraphEdit 4.x API 漂移**:全部调用收口 `proof_board.gd`;引擎钉死 4.7。
2. **合一器三连 bug**:occurs check 漏判 / 实例间元变量捕获(必须放置时全局重命名,禁止直接引用 schema 模板对象)/ 代换合成错误(读时 walk、终局 resolve)。各有专项测试。
3. **冲突归因顺序依赖**:固定边插入序;UI 文案只说"此线冲突"不承诺唯一根因(原版同)。
4. **辖域检查**:统一"(node, scope_input) 定点消除 + 前向传播",**勿写特判**;四种刁钻情形各一条测试。
5. **GraphEdit 不强制的事**:单口多线、自环、非法连接全部由 model 裁决后才 `connect_node`。
6. **流向限制**:GraphNode 仅左入右出;MVP 接受左→右,下垂丝线补氛围;若美术期撞墙,因 Model/View 分离只需换 view 层为自绘画布。
7. **性能**:全盘重解毫秒级;拖节点不触发 solve;PatternView 深度 >6 止损。
8. **⊥/¬**:Kind 已含 BOT、渲染留分支、规则表加溃散机即无结构性改动;¬ 不做独立连接词。

---

## 10. 实施顺序总览

| 里程碑 | 内容 | 验收 |
|---|---|---|
| M0 | 逻辑引擎 7 文件 + 测试 | headless 全绿;脚本化证明两例通过 |
| M1 | GraphEdit 灰盒棋盘 + WireOverlay chip | 鼠标完成 `A∧B ⊢ B∧A` |
| M2 | 全部 8 机 + PatternEditor + 辖域 UX + undo + 序列化 | 三例通过 + 逃逸红标 + 恢复 |
| M3 | 关卡/存档/对话/笔记本 + 16 关 | 全流程通关、存档恢复、笔记本解锁 |
| M4 | Theme + SVG 素材 + 丝带线 + shader + 音效 | 全 UI 换装、气质达标 |
| 后期可选 | 引理折叠(自定义方块)、对话表格编辑器插件、更多章节 | — |

---
