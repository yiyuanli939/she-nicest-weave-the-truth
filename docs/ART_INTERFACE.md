# 美术替换接口(当前全部为程序化占位)

原则:**代码只认 theme 与固定资产路径**;文件不存在就回退程序化占位。
美术把成品放进对应槽位 + 改 `theme/main_theme.tres`,零代码改动换装。
风格规范见 `plan.md` §7(黄铜三阶 #B08D57/#8C6F45/#5C4A2E + 墨 + 羊皮纸;128px 网格,2px 描边,九宫格 margin 24px)。

## 1. 全局主题

`theme/main_theme.tres` — 全部 Control 的字体/StyleBox/配色入口(Project Settings → GUI → Theme 已指向它)。
占位:程序化 StyleBoxFlat。替换:在该 .tres 里为 Button/Panel/GraphNode 等配 StyleBoxTexture(九宫格 SVG)。

## 2. SVG 槽位(plan.md §7.2 清单)

| 路径 | 内容 | 数量 | 现状 |
|---|---|---|---|
| `assets/svg/machines/<rule_id>.svg` | 八台仪器徽记(and_intro…tnd)+ spool(线轴)+ goal(目标织机) | 10 | 缺→节点只显中文名 |
| `assets/svg/badges/{conflict,underspec,cycle,escaped}.svg` | 骷髅/问号线轴/衔尾蛇/剪刀 | 4 | 缺→WireOverlay 文字徽章 |
| `assets/svg/ui/panel_parchment.svg` 等 | 羊皮纸面板/黄铜按钮三态/蜡封(未解+已解)/笔记本皮面/对话框 | ~8 | 缺→StyleBoxFlat |

导入设置:svg/scale=2.0 + mipmaps(见 plan.md §7 开头)。

## 3. 程序化视觉的调参点

| 东西 | 文件与参数 |
|---|---|
| 命题纹样配色 | 关卡 .tres 的 `atom_colors`;缺省表在 `levels/level_def.gd DEFAULT_COLORS`;hash 回退在 `api/pattern_view.gd atom_color()` |
| 纹样底色/焦纹/线宽 | `api/pattern_view.gd` 顶部常量(LINEN/CHAR_BLACK/SPLIT_COLOR/BASE_LINE_W) |
| 端口/假设口/目标配色 | `board/machine_node.gd` 顶部常量 |
| 错误徽章文字与颜色 | `board/wire_overlay.gd` BADGE/BADGE_COLOR(换 SVG 时改 `_make_chip`) |
| 胜利绿光 | `ui/level_scene.gd _on_win()` |
| 机器人 OLED 表情 | `hardware/firmware/main.py draw_face()`(128×64 单色点阵) |

## 4. 字体

`assets/fonts/` 放思源宋体 + EB Garamond(OFL),在 main_theme.tres 里设 default_font。当前用引擎默认字体。
