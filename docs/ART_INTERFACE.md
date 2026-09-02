# 美术接口(2026-08-29 美术包已接入)

来源:美术微信包 `美术/`(说明文档存档在 `information/art_spec_20260829/游戏样式美化.md` + 6 张参考图)。
原则:**PNG 原尺寸、不改长宽比**——逻辑视口就是出图分辨率 3840×2160(`project.godot` `[display]`),
窗口开局最大化(铺满任意屏幕,含 1920×1080;取消最大化还原 1440×810),由引擎整体等比缩放(`stretch/aspect=keep`)。全部文字用站酷小薇体。

## 1. 字体

`assets/fonts/ZCOOLXiaoWei-Regular.ttf` → `theme/main_theme.tres` `default_font`(FontVariation,
系统字体只做缺字兜底),`default_font_size = 48`。
**该字体没有** ☠ ◌ ✂ 📌 ▶ ✓ 🔒 ∧ ∨ → ⊥ ← ↑ ↓ ① 等符号(`tests/test_theme.gd` 会扫 UI 源码字面量),
文案里别用;人名里的「·」允许走系统兜底。

## 2. 图片映射(中文原名 → 工程路径 → 用在哪)

| 美术原名 | 路径 | 用途 |
|---|---|---|
| 标题界面/标题界面背景.png(3840×2160) | `assets/art/title/bg.png` | 标题页整张背景 |
| 标题界面/标题.png(2682×497) | `assets/art/title/title.png` | 标题图(挂流光 shader) |
| 选关界面/选关&开发者信息底图.png(3840×2160) | `assets/art/select/bg.png` | 选关页 + 开发者信息页底图 |
| 选关界面/选关按钮(已解锁/未解锁).png(391×155) | `assets/art/select/level_unlocked.png` / `level_locked.png` | 关卡按钮 |
| 关卡与笔记/仪器架底图.png(687×2117) | `assets/art/level/palette_bg.png` | 关内左侧仪器架 |
| 关卡与笔记/仪器按钮(合取/蕴含/析取/矛盾类).png(526×182) | `assets/art/level/machine_{and,imp,or,bot}.png` | 并织/拆股 · 封程/引渡 · 岔纹/汇路 · 溃散 |
| 关卡与笔记/笔记底图.png(3798×2065) | `assets/art/level/notebook_bg.png` | 右缘笔记抽屉 |
| 笔记本页面补充/<机名>.png(3840×2160,透明底) | `assets/art/level/notebook/<rule_id>.png` | 笔记条目整页图(标题/正文画在图里);**按全屏导出**,抽屉划出到位时与屏幕对齐,引擎原尺寸摆放 |
| 对话界面/对话界面底图.png(3835×2123) | `assets/art/story/base.png` | 故事界面固定底图 |
| 对话界面/场景(工坊/宿舍/街景).png(1942×1251) | `assets/art/story/scene_{workshop,dorm,street}.png` | 场景插图 |
| 对话界面/诺拉(默认/苦恼/严肃/惊讶).png(761×1721) | `assets/art/story/char_nora_{default,worried,serious,surprised}.png` | 主角立绘(恒右) |
| 对话界面/莉娅(默认/苦恼).png(821×1675) | `assets/art/story/char_lia_{default,worried}.png` | 配角立绘 |
| 对话界面/亚瑟(默认).png(801×1778) | `assets/art/story/char_arthur_default.png` | 配角立绘 |
| 对话界面/*遮罩.png | `assets/art/story/char_{nora,lia,arthur}_mask.png` | 非发言者 50% 遮罩 |

新加立绘/场景:按上面的命名规则放进目录,再在 `narrative/story_art.gd` 的 `CHARACTERS / EXPRESSIONS / SCENES` 表补一行。
所有 PNG 的导入都开了 mipmaps(`.import` 里 `mipmaps/generate=true`),窗口缩小显示不闪;**新图导入必须也开**
(全局过滤器是 LINEAR_WITH_MIPMAPS,4K 整页图在 1080p 屏上 2× 缩小采样,没 mipmap 又抖又多读 4 倍纹理;`tests/test_perf_settings.gd` 盯着)。

## 3. 位置调参表(给美术:在引擎里哪儿手动调图片位置)

坐标全是 3840×2160 逻辑像素,直接对应出图坐标。改常量、存盘、重开游戏即生效。

| 界面 / 元素 | 文件 → 常量 |
|---|---|
| 标题页:标题图左上角 | `ui/main_menu.gd` → `TITLE_POS` |
| 标题页:四个选项的水平中心 / 首项垂直中心 / 间距 / 字号 / 字距 | `ui/main_menu.gd` → `MENU_CENTER_X` `MENU_Y0` `MENU_PITCH` `MENU_FONT_SIZE` `MENU_GLYPH_SPACING` |
| 标题页:流光周期 / 宽度 / 强度 | `assets/shaders/title_sheen.gdshader` → `period` `band_width` `strength` |
| 选关页:章间距 / 章标题与按钮行间距 / 同行按钮间距 / 字号 / 颜色 | `ui/level_select.gd` → `CHAPTER_GAP` `TITLE_GAP` `ROW_GAP` `CHAPTER_FONT_SIZE` `LEVEL_FONT_SIZE` `*_COLOR` |
| 开发者信息页:文字与行距 | `ui/credits_scene.gd` → `LINES` `TEXT_FONT_SIZE` `LINE_GAP` |
| 故事界面:底图左上角 / 底图外圈的白底 | `ui/story_scene.gd` → `BASE_POS` `BG_COLOR`(底图 3835×2123 比视口小,四边垫白;换场清屏色在 `project.godot` `default_clear_color`) |
| 故事界面:场景插图矩形 | `ui/story_scene.gd` → `SCENE_RECT` |
| 故事界面:左 / 右立绘框(框外裁掉;立绘默认框内水平居中、底边贴框底) | `ui/story_scene.gd` → `LEFT_FRAME` `RIGHT_FRAME` |
| 故事界面:逐角色微调立绘位置 | `ui/story_scene.gd` → `PORTRAIT_NUDGE` |
| 故事界面:发言人名字位置 / 台词区矩形 | `ui/story_scene.gd` → `NAME_POS` `TEXT_RECT`;字号颜色在 `narrative/dialogue_box.gd` 顶部 |
| 故事界面:遮罩透明度 | `ui/story_scene.gd` → `MASK_ALPHA` |
| 关内:仪器架左上角 / 棋盘矩形 / 底色 | `ui/level_scene.gd` → `PALETTE_POS` `BOARD_RECT` `BG_COLOR` |
| 关内:仪器架 7 个按钮的 x / 首个 y / 间距 / 机名字号 | `board/palette_panel.gd` → `SLOT_X` `SLOT_Y0` `SLOT_PITCH` `NAME_FONT_SIZE` |
| 关内:笔记抽屉纵向位置 / 划出后 x / 收起时露出宽度 / 动画时长 | `narrative/notebook_ui.gd` → `DRAWER_Y` `OPEN_X` `CLOSED_PEEK` `SLIDE_SEC` |
| 关内:夹子「笔 / 记」「继续 / 工作」两行字的中心 / 字号 / 行距 / 热区尺寸;「翻页」矩形与字号;整页图偏移 | `narrative/notebook_ui.gd` → `HANDLE_CENTER_CLOSED` `HANDLE_CENTER_OPEN` `HANDLE_FONT_SIZE` `HANDLE_LINE_PITCH` `HANDLE_SIZE`;`FLIP_RECT` `FLIP_FONT_SIZE`;`PAGE_OFFSET`(整页图全屏导出,默认负抽屉开位即对齐,不用动) |
| 关内:线轴列 / 目标织机的初始摆位 | `ui/level_scene.gd` → `_layout_endpoints()` |
| 关内:操作指引一行字(棋盘左下,求助提示上一行;暂为纯文字,美术要换图/挪位改这里)位置 / 字号 / 颜色 | `ui/level_scene.gd` → `STEP_HINT_POS` `STEP_HINT_FONT_SIZE` `STEP_HINT_COLOR`(求助提示同处 `GUIDE_HINT_POS` `GUIDE_HINT_FONT_SIZE`) |
| 节点区:乳黄底 / 棕红描边 / 标题字 | `theme/main_theme.tres` → `GraphEdit/*` `GraphNode/*` `GraphNodeTitleLabel/*` |
| 节点区:端口颜色 / 纹样口尺寸 / 行距 / 行内间距 | `board/machine_node.gd` → `PORT_COLOR` `HYP_COLOR` `GOAL_COLOR` `BIG_VIEW` `PORT_VIEW` `ROW_GAP` `CELL_GAP` |
| 节点区:端口图形(v1.1 §1:输出口 = 圆 + 朝右尖角的插头,输入口 = 缺口朝左的插座;接上后输入口整圆、输出口不画;拖线时插头跟着鼠标) | `board/machine_node.gd` → `PORT_R` `PORT_TIP` `PORT_NOTCH_DEG`(画法 `draw_plug/draw_socket`,拖线中的插头在 `board/wire_overlay.gd`) |
| 节点区:纹样边框按子命题着色(v1.1 §4.2) | `board/machine_node.gd` → `META_COLORS`(P 金 C9A24E / Q 棕 775241 / R 青 7B9B8B)`META_COLOR_OVERRIDES`(岔纹机两口 C2CAB9 / A8B9BE);线宽 `api/pattern_view.gd` `REGION_BORDER_W` |
| 节点区:「钉纹样」按钮底色 / 位置(默认纹样下方,岔纹机在纹样左侧)/ 字号 / 内边距 / 与纹样的间距;圆角 | `board/machine_node.gd` → `PIN_BG` `PIN_BG_BY_PORT` `PIN_BUTTON_SIDE` `PIN_FONT_SIZE` `PIN_MARGIN_H` `PIN_MARGIN_V` `PIN_GAP`;`ui/ui_styles.gd` → `RADIUS` |
| 节点区:未钉口的蚂蚁线(静态虚线)颜色 / 外扩 / 线宽 / 虚线段;可钉纹样离节点边缘的额外留白(蚂蚁线不压描边) | `board/machine_node.gd` → `ANT_COLOR` `ANT_INSET` `ANT_W` `ANT_DASH` `ANT_EDGE_INSET` |
| 节点区:汇路机三行分割线两色 / 线宽(v1.1 §4.3) | `board/machine_node.gd` → `DIVIDER_GOLD` `DIVIDER_CREAM` `DIVIDER_W` |
| 节点区:封程机凹形(v1.1 §4.4:缺口 spacer 宽 / 两臂顶端留白 / 左臂宽 / 右臂纹样两侧留白 / 缺口底到标题带 / 标题字号 / 底边距;底色 / 标题带色 / 描边 / 圆角;假设口与输入口在两臂内沿) | `board/machine_node.gd` → `IMP_NOTCH_W` `IMP_TOP_PAD` `IMP_ARM_L_W` `IMP_ARM_R_INSET` `IMP_BASE_PAD` `IMP_TITLE_FONT_SIZE` `IMP_BOTTOM_PAD`;`NODE_BG` `NODE_TITLE_BG` `NODE_BORDER` `NODE_BORDER_SELECTED` `NODE_BORDER_W` `NODE_RADIUS`(口位 `port_pos()`) |
| 连线:搭载未消去假设的线整条的颜色(v1.1 §2) | `theme/main_theme.tres` → `GraphEdit/colors/activity`(= `HYP_COLOR`) |
| 连线:错误徽章字号 / 白描边 / 停留与淡出时长;接错的线自动断开时长(v1.1 §3) | `board/wire_overlay.gd` → `BADGE_FONT_SIZE` `BADGE_OUTLINE` `BADGE_HOLD_SEC` `BADGE_FADE_SEC`;`board/proof_board.gd` → `BAD_WIRE_SEC` |
| 纹样绘制弹窗(v1.1 §4.6,照 image 13):标题带高 / 字号 / 缩进、预览尺寸、各行间距、笔刷尺寸与间距、按钮字号与内边距、底边距、外框描边圆角 | `pattern/pattern_editor.gd` → `TITLE_FONT_SIZE` `TITLE_BAND_PAD` `TITLE_INDENT` `PREVIEW_SIZE` `GAP_PREVIEW_HINT` `HINT_FONT_SIZE` `GAP_HINT_BRUSH` `SWATCH_SIZE` `BRUSH_GAP` `GAP_BRUSH_BUTTONS` `FONT_SIZE` `BUTTON_MARGIN_H` `BUTTON_MARGIN_V` `BOTTOM_PAD` `CONTENT_MARGIN` `FRAME_W` `FRAME_RADIUS` `BAND_LINE_W` `ICON_LINE_W` `ICON_COLOR` `BUTTON_BG` |

## 3.5 参考基准与实测值(2026-09-02 像素对齐审查)

引擎常量不是「居中」拍出来的,是对美术参考图量出来的。基准分三级,改常量前先看这一节:

| 基准 | 可信度 | 量法 |
|---|---|---|
| `笔记本页面补充/位置参考.png`(3840×2160) | 全分辨率,像素级 | 把 `notebook_bg.png` 不透明像素在参考图上逐偏移比均差,最小值尖锐(邻点差 3 倍) |
| `assets/art/story/base.png` 自己画的框线 | 全分辨率,像素级 | 沿多行多列扫暗线(灰度 <140),取内沿中位数 |
| `information/art_spec_20260829/image*.png` 六张预览 | 低清(1150–1550 宽,≈0.3×),±3 px 量化 + 比例误差,合计 ±5–10 px | 素材缩到预览比例做带遮罩归一化互相关;用同一素材的两处远端花纹做双锚点定比例 |

实测值(全部 4K 逻辑像素;引擎常量已按此设):

| 元素 | 参考实测 | 引擎常量 |
|---|---|---|
| 笔记底图划出位 | 位置参考:左上角 **(17, 27)** | `OPEN_X 17` `DRAWER_Y 27` |
| 「翻页」 | 墨迹 152×66(= 82 号),中心 (3299.5, 1631.5) | `FLIP_FONT_SIZE 82`,`FLIP_RECT` 中心抽屉内 (3282, 1604) |
| 「继续 / 工作」 | 两行两字,墨高 64(= 78 号),行距 92,中心 (363.5, 1046) | `HANDLE_FONT_SIZE 78` `HANDLE_LINE_PITCH 92` `HANDLE_CENTER_OPEN (346, 1019)` |
| 「笔 / 记」(收起) | 关内预览:中心 ≈(3744, 1084),夹子在 y≈63 → 相对夹子同高 | `HANDLE_CENTER_CLOSED (254, 1021)` |
| 笔记收起露出宽度 | 关内预览:抽屉 x≈3490 → 露出 ≈350 | `CLOSED_PEEK 350` |
| 故事:场景插图 | base.png 画框内沿 x 947..2887、y 86..1336 | `SCENE_RECT (946, 86, 1942, 1251)` |
| 故事:立绘区 | 内沿 x 88..902 / 2933..3747;地板线 y 2001;预览脚底 ≈1986 | `LEFT_FRAME (88,188,815,1800)` `RIGHT_FRAME (2933,188,815,1800)`(底边 1987) |
| 故事:台词框 | 内沿 x 948..2887、y 1451..2041 | `TEXT_RECT (1040,1590,1756,420)`(左右边距各 92) |
| 标题图 | 标题预览(bg 三锚点):左上角 (630, 1551) | `TITLE_POS (630, 1551)` |
| 标题四选项 | 墨高 65–67(= 78 号,字距 0),中心 x≈3580,首项 y≈940,间距 ≈197 | `MENU_FONT_SIZE 78` `MENU_GLYPH_SPACING 0` `MENU_CENTER_X 3580` `MENU_Y0 940` `MENU_PITCH 197` |
| 仪器架 | 关内预览(顶/底花纹双锚点):(27, 20);7 个按钮最小二乘 架内首个 y 248、间距 210.8 | `PALETTE_POS (27, 20)` `SLOT_Y0 248` `SLOT_PITCH 211` |

对照工具:`"$GODOT" --path . --script res://tools/shot_4k.gd` 在 3840×2160 的 SubViewport 里离屏渲染
标题 / 故事 / 关内 / 关内笔记划出 四张 1:1 截图到 `build/shots4k/4k_*.png`(冒烟截图随窗口缩放,肉眼对不准),
与参考图叠图或做模板匹配即可核对;`tests/test_art_alignment.gd` 把前两级基准固化成回归(抽屉开位、场景框、立绘区、
立绘/遮罩尺寸、收起时整页图不进屏)。

**待美术确认(两份参考互相矛盾,引擎按全分辨率的位置参考):**
1. 关内预览里**收起**的笔记在 y≈63,位置参考里**打开**的在 y=27,引擎两态同用 27(抽屉只横向划)。
2. 七张整页图的标题/正文比位置参考低 127 px(整页图是最终稿,引擎按屏幕对齐摆放,无需改)。
3. `莉娅（严肃）.png` 是 821×**1669**,比遮罩和其他表情(1675)矮 6 px;引擎已按遮罩画布定位不会跳动,但请按 821×1675 重导。

### 3.6 v1.1 示意图折算基准(2026-09-02)

策划的 14 张示意图(`v1.1交互调整说明/`)不是 4K 出图,每张比例都不同、且是手绘。量法:以**纹样宽 = 128 px**
(仪器口 `PORT_VIEW`)为尺,把每张图里的距离按 `128 / 图中纹样宽` 折算;弹窗以**预览宽 = 720 px** 为尺(image 13 预览 433 → ×1.663)。
连通域(`scipy.ndimage.label`)取纹样框 / 按钮 / 端口 / 文字墨迹的包围盒,多张图给出一个区间时取中值。
引擎值用 `tools/shot_4k.gd` 的 `4k_machines.png` / `4k_editor.png` 同法量回来核对。

| 元素 | 示意图折算(区间) | 引擎常量 → 实测 |
|---|---|---|
| 两列纹样间距 | 61–75(image 5–8) | `CELL_GAP` 23 × 3 = 69 |
| 纹样行距 | 31–38(image 4/5/6/8) | `ROW_GAP` 32 |
| 标题带总高(含描边)/ 标题墨高 | 83–92 / 40–43 | 86 / 42(48 号) |
| 端口圆直径 / 插头总宽 | 16–24(image 6–12) / 尖角 ≈ 直径 × 0.45(image 1) | `PORT_R` 10 → 20 / 29 |
| 钉纹样按钮 宽 × 高 / 墨高 / 与纹样间距 | 111–145 × 39–50 / 30–33 / 19–24(image 9/11/12) | 36 号 + 内边距 12/0 → 135 × 53 / ≈29 / `PIN_GAP` 22 |
| 蚂蚁线外扩 / 虚线段 | 11–15 / ≈8(image 9/11/12) | `ANT_INSET` 14 / `ANT_DASH` 8 |
| 汇路机分割线 | 金 ≈3 + 乳黄 ≈3(image 8) | `DIVIDER_W` 3 |
| 封程机:缺口宽 / 左臂宽 / 右臂宽 / 臂顶留白 / 假设→按钮 / 缺口底到标题带 / 标题带高 / 标题墨高 | 228 / 174 / 186 / 41–46 / 24 / 11 / 89 / 49(image 9) | 182 + 2 × 23 = 228 / 16 + 160 = 176 / 128 + 2 × 21 + 16 = 186 / 44 / 22 / 11 / 97 / 52 号 |
| 弹窗:标题带高(含 3 px 线)/ 标题墨高 / 标题缩进 | 178 / 63 / 37(image 13) | 174 / 74 号 / 37 |
| 弹窗:预览 / 左右边距 / 预览→提示 / 提示墨高 / 提示→笔刷 / 笔刷 / 笔刷间距 / 笔刷→按钮 / 按钮 / 底边距 | 720 × 421 / 18–22 / 58 / 27 / 17 / 100–116 × 76 / 15 / 76 / 106–128 × 58–61 / 48 | 720 × 420 / 20 / 58 / 33 号 / 17 / 110 × 76 / 15 / 76 / 122 × 61 / 48 |

逐图对比后修掉的图形问题:可钉纹样的蚂蚁线外扩后压在节点 6 px 描边上(image 12 纹样距边 30)→ 可钉纹样及其按钮再离边 `ANT_EDGE_INSET` 16(封程机左臂离左边 8);
封程机描边的闭合点落在圆角上露缝 → 闭合点挪到底边中点并首尾重叠;对角分割线的平头端帽戳出纹样角 → 两端各缩回半个线宽。
未照做的地方(示意图彼此矛盾或手绘偏差):image 9 里 P>Q 出口画在节点边缘内侧 12 px,其它图的口都压在边缘上,引擎统一压边缘;
各图的节点左右内边距 10–24 不一,引擎沿用 theme 的 16;钉按钮高 53 比示意图上限多 3 px(36 号字的行高下限)。

## 4. 主题与配色

`theme/main_theme.tres`(Project Settings → GUI → Theme 已指向它):
- 纯文字按钮:四态 `StyleBoxEmpty`,`font_hover_color` 比 `font_color` 浅(美术:悬停文字变浅、离开恢复);
  带图按钮(关卡按钮、仪器按钮)在各自脚本里用 `StyleBoxTexture` 覆盖,`modulate_color` 做悬停提亮 / 置灰;
  带底色按钮(v1.1:节点内「钉纹样」、纹样绘制弹窗的 清空/取消/确认)用 `ui/ui_styles.gd` `UiStyles.fill_button(按钮, 底色)`,悬停/按下底色变暗。
- 配色(取自参考图):棕红描边 `#6B3B33` · 深棕文字 `#4A2F2A` · 红棕强调 `#A0463A` · 乳黄 `#F4ECD8` · 黄铜 `#C9A24E`。

## 5. 仍为程序化的部分(没有对应美术)

| 东西 | 文件与参数 |
|---|---|
| 命题纹样(节点口 / 编辑器 / 线轴 / 目标) | `api/pattern_view.gd`(LINEN / CHAR_BLACK / SPLIT_COLOR / BASE_LINE_W);原子配色在关卡 `atom_colors`,缺省表 `levels/level_def.gd DEFAULT_COLORS`(低饱和高明度:藕粉红/灰蓝/豆青/紫藕) |
| 选关/开发者页「返回主界面」 | `ui/back_button.gd`(RECT 左上角坐标 / FONT_SIZE) |
| 连线错误徽章(纯文字:冲突 / 欠定 / 成环 / 逃逸;64 号白描边,接错的线 0.5 s 自动断、徽章停 1 s 淡出) | `board/wire_overlay.gd` BADGE / BADGE_COLOR / BADGE_FONT_SIZE / BADGE_OUTLINE / BADGE_HOLD_SEC / BADGE_FADE_SEC;`board/proof_board.gd` BAD_WIRE_SEC |
| 纹样绘制弹窗(标题带 / 预览 / 「点选笔刷进行绘制:」/ 色块 + 三个线描结构笔刷 / 清空·取消·确认) | `pattern/pattern_editor.gd`(PREVIEW_SIZE / SWATCH_SIZE / TITLE_* / HINT_* / BUTTON_BG / ICON_*) |
| 节点端口图形 / 纹样区域边框 / 钉按钮 / 蚂蚁线 / 汇路机分割线 / 封程机凹形 | `board/machine_node.gd` 顶部常量(§3 表);策划说明与示意图在 `v1.1交互调整说明/` |
| 胜利绿光 | `ui/level_scene.gd _on_win()` |
| 机器人 OLED 表情 | `hardware/firmware/main.py draw_face()` |
