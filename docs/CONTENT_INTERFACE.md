# 内容更新指南(策划:改台词/关卡/机器人演出,零代码)

正式剧情已按策划表灌入(源表:`剧情文件及美术补充/静语纹_四章剧情_无旁白版_v2.xlsx`)。改台词 = 改 xlsx 后两条命令重灌。

## 改台词(策划 Excel 表 → 一键导入)

```bash
python3 tools/xlsx_to_csv.py                                            # xlsx → information/dialogue.csv(只做格式转换)
"$GODOT" --headless --path . --script res://tools/import_dialogue.gd    # 校验并写进 levels/data/*.tres
```
换别的表:`python3 tools/xlsx_to_csv.py 新表.xlsx`;导入命令后接 `-- 路径.csv` 可换 CSV。
Windows 下第一条用 `py -3 tools/xlsx_to_csv.py`(转换器只用 Python 标准库,无需装任何包)。

表头(列顺序随意,按名字识别,新旧写法都认;表头行之前的注意事项行自动跳过):
`关卡|关卡id, 发言人, 场景, 左位人物|左侧人物, 左位人物表情|左侧表情, 主角表情|诺拉表情, 语句|台词, 小机动作(可省略)`

| 列 | 取值 |
|---|---|
| 关卡 | `1-1` … `4-3`(章-节,映射按关卡目录)或 `l01` … `l16`。**`4-3` 是通关后剧情**(表头注意事项②):写进 l16 的 `outro_dialogue`,l16 通关点「继续」才播,播完「感谢游玩」黑屏 → 开发者信息页;其余段落进关前播。表里出现的关,intro/outro 两个字段都会重写(缺的一侧清空) |
| 发言人 | 显示名,如 `诺拉·拉芙蒂` / `莉娅·科尔宾` / `亚瑟·威客利夫`;登记角色写短名会自动补全名 |
| 场景 | `工坊` / `诺拉房间`(=宿舍图)/ `伦敦街上`(=街景图);空 = 沿用上一句(每段首句必须给) |
| 左位人物 | `莉娅` / `亚瑟`(写全名也认);`无` 或空 = 左侧无人(主角诺拉恒在右侧) |
| 左位人物表情 / 主角表情 | `默认` / `苦恼` / `严肃` / `惊讶`(只填美术已给图的组合;空 = 默认,注意事项①) |
| 语句 | 支持 BBCode;含逗号/换行用引号包住(xlsx 转换器自动做) |
| 小机动作 | `greet celebrate confused hint panic glitch calm think sleep idle` 之一或空;正式表没有这列 = 台词行不带演出 |

非法的场景/人物/表情整行跳过并报错,**有任何错误一关都不写**;表里没出现的关卡不动。可用角色/表情/场景在 `narrative/story_art.gd`。

也可以在 Godot 里直接改:打开 `levels/data/lXX_*.tres`,Inspector 展开 `intro_dialogue → lines`(l16 是 `outro_dialogue`),每行字段同上。
故事界面不显示场景名;两人同在时非发言者自动叠 50% 遮罩;点击任意处或按任意键推进,无跳过键。

## 改/加关卡

- 关卡字段见 `levels/level_def.gd` 注释。公式格式:`&`=∧ `|`=∨ `>`=→(右结合) `false`=⊥,如 `"A & B > C"`。
- **关名不要自己取**:美术规定按章内序号叫「第一纹」「第二纹」…;章名 `第一章 并纹 / 第二章 叠层纹 / 第三章 岔纹 / 第四章 焦纹`。
- `robot_cue_on_enter` / `robot_cue_on_win`:进关/通关的小机演出。现在进关一律为空;通关一律 `celebrate`,只有 l11(3-1)是 `panic`——
  **小机在 3-1 通关瞬间坏掉**(剧情:淋雨),此后(3-2 起到第四章打完)整段故障态:这些关里策划挂的任何 cue(含对话行 robot_cue、通关 celebrate)都会变成故障演出(故障脸 + 乱动 + 故障声);
  **结局才修好**——l16 通关后 4-3 剧情播完的「感谢游玩」黑屏时 `calm`(在 `ui/story_scene.gd`)。
  `allow_bot`:纹样编辑器是否解锁焦纹笔刷(第四章起 on)。
- 小机「请指导我 / 请帮帮我」(玩家对麦克风说):坏掉前(l01–l11)小机回头到极限后**直接代解本关**(不庆祝不鼓励),坏掉后只故障演出。
  关内提示文案在 `ui/level_scene.gd` `GUIDE_HINT`(坏掉前才显示);语音识别与小机维护见 docs/ROBOT_API.md。
- **设计关卡时注意求解是严格正向的**:仪器输出只由输入 + 玩家钉的纹样决定,不会从目标反推。
  用到封程机(假设 P)、岔纹机(另一支)、溃散机(织出什么)的关,玩家必须点标题栏"钉纹样/钉上口/钉下口"
  给自由纹样赋值;关卡 `atoms` 要包含玩家需要钉的原子。脚本化解法在 `levels/level_solutions.gd` 的 `p` 数组。
- 新增关卡:复制一个 .tres 改字段 → 在 `levels/data/catalog.tres` 对应章节的 `levels` 数组里加进去。顺序即解锁顺序(全线性)。
- 批量重生成(会覆盖关卡字段!):改 `tools/gen_levels.gd` 的表后跑
  `godot --headless --path . --script res://tools/gen_levels.gd`
  (对话不会丢:重生成时原样保留现有 .tres 的 intro/outro 台词,不会被打回占位)
- 仪器架只显示本关 `allowed_rules` 上架的仪器(顺序按美术图,紧凑排列),未上架的不显示。
  **仪器按关上架、逐关累计**(2026-09-02):`tools/gen_levels.gd` `LEVELS` 表每行最后一列是本关新上架的仪器,
  之后的关自动带上。现网:l01 无 · l02 并织 · l03 拆股 · l06 引渡 · l07 封程 · l11 岔纹 · l12 汇路 · l14 溃散。
  改上架关 = 把 rule_id 挪到另一行,重跑生成器(解法只能用本关架上的仪器,`tests/test_levels.gd` 盯着)。
- **2026-09-02 编排**:第一章加了第三纹 `A & B ⊢ A`(无剧情,进关直接是棋盘),原第三/四纹后移为第四/五纹;
  第二章第二纹/第三纹**只对调题目**(2-2 = `⊢ A > A` 封程裸机,2-3 = `A > B, B > C ⊢ A > C`),剧情按「章-节」位置不动。
  策划表与 `information/dialogue.csv` 里第一章的节号已同步后移(原 1-3/1-4 = 现 1-4/1-5,现 1-3 无剧情);
  全局关卡 id 从 l03 起后移一位(3-1 = l11、4-3 = l16),`tests/test_levels.gd` 会逐句核对表与 .tres。

## 诺拉的笔记(= 七台仪器的整页图)

每台仪器一页整图 `assets/art/level/notebook/<rule_id>.png`(**3840×2160 全屏导出、透明底**,与打开的抽屉对齐,
内容画在纸面区;标题/正文全部在图里,引擎不再渲染任何条目文字;源中文命名图存档在 `笔记本页面补充/`)。
目录仍 7 条全量(`narrative/data/notebook.tres`,id = rule_id,顺序同仪器架);关内只显示本关上架仪器的页
(按 allowed_rules 过滤)。点右缘「笔记」划出,「翻页」循环。
- **改一页** = 用同规格 PNG 覆盖对应 `<rule_id>.png`(`--import` 后连 `.import` 一起提交)。
- **新增仪器的页** = 放图 + `tools/gen_levels.gd` `NOTEBOOK_IDS` 加一行,重跑生成器。
- **文案守则**(由美术在图里执行):只讲机器行为与操作,用纺织语汇(并纹/岔纹/迭层纹/焦纹/封单/借丝);
  不得出现直接的逻辑提示——逻辑符号(∧ ∨ → ⊥)、逻辑术语、规则陈述、解法提示一律不写。

## 机器人语音台词

`hardware/firmware/sounds/*.wav`(greet/win/encourage/panic/calm/hint),音色为微软 XiaoyiNeural(小智同款)。改词:
```bash
hardware/.venv/bin/edge-tts --voice zh-CN-XiaoyiNeural --text "新台词" --write-media t.mp3
afconvert -f WAVE -d LEI16@16000 -c 1 t.mp3 hardware/firmware/sounds/win.wav && rm t.mp3
hardware/.venv/bin/mpremote connect /dev/cu.usbmodem2101 fs cp hardware/firmware/sounds/win.wav :sounds/
hardware/.venv/bin/mpremote connect /dev/cu.usbmodem2101 reset   # 传完必须 reset,否则停在 REPL
```
(先停桥接;详见 docs/ROBOT_API.md。)

## 换 / 加背景音乐

槽位表与做法见 `music/音乐bgm位置.md`:换曲 = 覆盖 `music/<槽位>.mp3`;新槽位第一次填曲改 `game/bgm.gd` `TRACKS` 一行;
`--import` 后把 `.import` 一起提交。开发者信息页署名改 `ui/credits_scene.gd` `LINES`。关内四章暂共用 `music/level.wav`;新曲响度和现有曲不一致时在 `game/bgm.gd` `GAIN_DB` 按文件填 dB 修正。

## 验证改动

```bash
godot --headless --path . --script res://tests/run_tests.gd     # 数据校验(公式可解析、规则存在、角色/场景名合法等)
godot --path . --script res://tests/visual_smoke_m3.gd          # 全 16 关自动通关回归
```
