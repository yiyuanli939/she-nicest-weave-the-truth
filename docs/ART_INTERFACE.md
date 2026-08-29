# 美术接口(2026-08-29 美术包已接入)

来源:美术微信包 `美术/`(说明文档存档在 `information/art_spec_20260829/游戏样式美化.md` + 6 张参考图)。
原则:**PNG 原尺寸、不改长宽比**——逻辑视口就是出图分辨率 3840×2160(`project.godot` `[display]`),
窗口本身默认开 1440×810 由引擎整体等比缩放(`stretch/aspect=keep`)。全部文字用站酷小薇体。

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
| 对话界面/对话界面底图.png(3835×2123) | `assets/art/story/base.png` | 故事界面固定底图 |
| 对话界面/场景(工坊/宿舍/街景).png(1942×1251) | `assets/art/story/scene_{workshop,dorm,street}.png` | 场景插图 |
| 对话界面/诺拉(默认/苦恼/严肃/惊讶).png(761×1721) | `assets/art/story/char_nora_{default,worried,serious,surprised}.png` | 主角立绘(恒右) |
| 对话界面/莉娅(默认/苦恼).png(821×1675) | `assets/art/story/char_lia_{default,worried}.png` | 配角立绘 |
| 对话界面/亚瑟(默认).png(801×1778) | `assets/art/story/char_arthur_default.png` | 配角立绘 |
| 对话界面/*遮罩.png | `assets/art/story/char_{nora,lia,arthur}_mask.png` | 非发言者 50% 遮罩 |

新加立绘/场景:按上面的命名规则放进目录,再在 `narrative/story_art.gd` 的 `CHARACTERS / EXPRESSIONS / SCENES` 表补一行。
所有 PNG 的导入都开了 mipmaps(`.import` 里 `mipmaps/generate=true`),窗口缩小显示不闪。

## 3. 位置调参表(给美术:在引擎里哪儿手动调图片位置)

坐标全是 3840×2160 逻辑像素,直接对应出图坐标。改常量、存盘、重开游戏即生效。

| 界面 / 元素 | 文件 → 常量 |
|---|---|
| 标题页:标题图左上角 | `ui/main_menu.gd` → `TITLE_POS` |
| 标题页:四个选项的水平中心 / 首项垂直中心 / 间距 / 字号 / 字距 | `ui/main_menu.gd` → `MENU_CENTER_X` `MENU_Y0` `MENU_PITCH` `MENU_FONT_SIZE` `MENU_GLYPH_SPACING` |
| 标题页:流光周期 / 宽度 / 强度 | `assets/shaders/title_sheen.gdshader` → `period` `band_width` `strength` |
| 选关页:章间距 / 章标题与按钮行间距 / 同行按钮间距 / 字号 / 颜色 | `ui/level_select.gd` → `CHAPTER_GAP` `TITLE_GAP` `ROW_GAP` `CHAPTER_FONT_SIZE` `LEVEL_FONT_SIZE` `*_COLOR` |
| 开发者信息页:文字与行距 | `ui/credits_scene.gd` → `LINES` `TEXT_FONT_SIZE` `LINE_GAP` |
| 故事界面:底图左上角 | `ui/story_scene.gd` → `BASE_POS` |
| 故事界面:场景插图矩形 | `ui/story_scene.gd` → `SCENE_RECT` |
| 故事界面:左 / 右立绘框(框外裁掉;立绘默认框内水平居中、底边贴框底) | `ui/story_scene.gd` → `LEFT_FRAME` `RIGHT_FRAME` |
| 故事界面:逐角色微调立绘位置 | `ui/story_scene.gd` → `PORTRAIT_NUDGE` |
| 故事界面:发言人名字位置 / 台词区矩形 | `ui/story_scene.gd` → `NAME_POS` `TEXT_RECT`;字号颜色在 `narrative/dialogue_box.gd` 顶部 |
| 故事界面:遮罩透明度 | `ui/story_scene.gd` → `MASK_ALPHA` |
| 关内:仪器架左上角 / 棋盘矩形 / 底色 | `ui/level_scene.gd` → `PALETTE_POS` `BOARD_RECT` `BG_COLOR` |
| 关内:仪器架 7 个按钮的 x / 首个 y / 间距 / 机名字号 | `board/palette_panel.gd` → `SLOT_X` `SLOT_Y0` `SLOT_PITCH` `NAME_FONT_SIZE` |
| 关内:笔记抽屉纵向位置 / 划出后 x / 收起时露出宽度 / 动画时长 | `narrative/notebook_ui.gd` → `DRAWER_Y` `OPEN_X` `CLOSED_PEEK` `SLIDE_SEC` |
| 关内:夹子「笔记/继续工作」按钮矩形 / 「翻页」矩形 / 纸面矩形与内边距 / 字号颜色 | `narrative/notebook_ui.gd` → `HANDLE_RECT` `FLIP_RECT` `CONTENT_RECT` `CONTENT_MARGIN` `*_FONT_SIZE` `*_COLOR` |
| 关内:线轴列 / 目标织机的初始摆位 | `ui/level_scene.gd` → `_layout_endpoints()` |
| 节点区:乳黄底 / 棕红描边 / 标题字 | `theme/main_theme.tres` → `GraphEdit/*` `GraphNode/*` `GraphNodeTitleLabel/*` |
| 节点区:端口颜色 / 纹样口尺寸 | `board/machine_node.gd` → `PORT_COLOR` `HYP_COLOR` `GOAL_COLOR` `BIG_VIEW` `PORT_VIEW` |

## 4. 主题与配色

`theme/main_theme.tres`(Project Settings → GUI → Theme 已指向它):
- 纯文字按钮:四态 `StyleBoxEmpty`,`font_hover_color` 比 `font_color` 浅(美术:悬停文字变浅、离开恢复);
  带图按钮(关卡按钮、仪器按钮)在各自脚本里用 `StyleBoxTexture` 覆盖,`modulate_color` 做悬停提亮 / 置灰。
- 配色(取自参考图):棕红描边 `#6B3B33` · 深棕文字 `#4A2F2A` · 红棕强调 `#A0463A` · 乳黄 `#F4ECD8` · 黄铜 `#C9A24E`。

## 5. 仍为程序化的部分(没有对应美术)

| 东西 | 文件与参数 |
|---|---|
| 命题纹样(节点口 / 编辑器 / 线轴 / 目标) | `api/pattern_view.gd`(LINEN / CHAR_BLACK / SPLIT_COLOR / BASE_LINE_W);原子配色在关卡 `atom_colors`,缺省表 `levels/level_def.gd DEFAULT_COLORS`(低饱和高明度:藕粉红/灰蓝/豆青/紫藕) |
| 选关/开发者页「返回主界面」 | `ui/back_button.gd`(RECT 左上角坐标 / FONT_SIZE) |
| 连线错误徽章(纯文字:冲突 / 欠定 / 成环 / 逃逸) | `board/wire_overlay.gd` BADGE / BADGE_COLOR |
| 纹样编辑器弹窗 | `pattern/pattern_editor.gd`(PREVIEW_SIZE / SWATCH_SIZE) |
| 胜利绿光 | `ui/level_scene.gd _on_win()` |
| 机器人 OLED 表情 | `hardware/firmware/main.py draw_face()` |
