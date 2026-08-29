# 内容更新指南(策划:改台词/关卡/机器人演出,零代码)

当前所有台词为 `[占位]` 测试稿,结构已定。正式剧情按美术约定用 **Excel 表**交付,另存 CSV 后一条命令灌入。

## 改台词(推荐:Excel → CSV 导入)

表头(列顺序随意,按名字识别):`关卡id, 发言人, 场景, 左侧人物, 左侧表情, 诺拉表情, 台词, 小机动作`

| 列 | 取值 |
|---|---|
| 关卡id | `l01` … `l15`(同一关的行按出现顺序成为该关开场对话) |
| 发言人 | 显示名,如 `诺拉·拉弗蒂` / `莉娅` / `亚瑟·威客利夫`;登记角色写短名会自动补全名 |
| 场景 | `工坊` / `宿舍` / `街景`;空 = 沿用上一句 |
| 左侧人物 | `莉娅` / `亚瑟`;空 = 左侧无人(主角诺拉恒在右侧) |
| 左侧表情 / 诺拉表情 | `默认` / `苦恼` / `严肃` / `惊讶`(只填美术已给图的组合;空 = 默认) |
| 台词 | 支持 BBCode;含逗号/换行用引号包住(Excel 另存 CSV 会自动做) |
| 小机动作 | `greet celebrate confused hint panic glitch calm think sleep idle` 之一或空 |

```bash
"$GODOT" --headless --path . --script res://tools/import_dialogue.gd            # 默认读 information/dialogue.csv
"$GODOT" --headless --path . --script res://tools/import_dialogue.gd -- 路径.csv
```
非法的场景/人物/表情整行跳过并报错;表里没出现的关卡不动。可用角色/表情/场景在 `narrative/story_art.gd`。

也可以在 Godot 里直接改:打开 `levels/data/lXX_*.tres`,Inspector 展开 `intro_dialogue → lines`,每行字段同上。
故事界面不显示场景名;两人同在时非发言者自动叠 50% 遮罩;点击任意处或按任意键推进,无跳过键。

## 改/加关卡

- 关卡字段见 `levels/level_def.gd` 注释。公式格式:`&`=∧ `|`=∨ `>`=→(右结合) `false`=⊥,如 `"A & B > C"`。
- **关名不要自己取**:美术规定按章内序号叫「第一纹」「第二纹」…;章名 `第一章 并纹 / 第二章 叠层纹 / 第三章 岔纹 / 第四章 焦纹`。
- `robot_cue_on_enter` / `robot_cue_on_win`:进关/通关的小机演出。现在 l10 进关 `panic`(第三章开头小机当场坏掉)、l13 进关 `calm`(第四章开头修好),
  其余进关为空、通关一律 `celebrate`。**第三章整章是故障态**:这三关里策划挂的任何 cue(含对话行 robot_cue、通关 celebrate)都会变成故障演出(故障脸 + 乱动 + 故障声)。
  `allow_bot`:纹样编辑器是否解锁焦纹笔刷(第四章起 on)。
- 小机「请指导我 / 请帮帮我」(玩家对麦克风说):第一二章小机回头到极限后**直接代解本关**(不庆祝不鼓励),第三章只故障,第四章只回头看你。
  关内提示文案在 `ui/level_scene.gd` `GUIDE_HINT`(只在一二章显示);语音识别与小机维护见 docs/ROBOT_API.md。
- **设计关卡时注意求解是严格正向的**:仪器输出只由输入 + 玩家钉的纹样决定,不会从目标反推。
  用到封程机(假设 P)、岔纹机(另一支)、溃散机(织出什么)的关,玩家必须点标题栏"钉纹样/钉上口/钉下口"
  给自由纹样赋值;关卡 `atoms` 要包含玩家需要钉的原子。脚本化解法在 `levels/level_solutions.gd` 的 `p` 数组。
- 新增关卡:复制一个 .tres 改字段 → 在 `levels/data/catalog.tres` 对应章节的 `levels` 数组里加进去。顺序即解锁顺序(全线性)。
- 批量重生成(会覆盖!):改 `tools/gen_levels.gd` 的表后跑
  `godot --headless --path . --script res://tools/gen_levels.gd`
- 仪器架固定显示 7 台(顺序按美术图),本关 `allowed_rules` 之外的置灰。

## 诺拉的笔记(= 七台仪器的说明)

`narrative/data/notebook.tres`:每台仪器一条(id = 仪器 rule_id,顺序同仪器架),标题 + 正文(BBCode),先仅文字。
全量常驻、不解锁;关内点右缘「笔记」划出,「翻页」循环。
批量改走 `tools/gen_levels.gd` 的 `RULE_GUIDE` 表后重跑生成器;单条改直接在 Inspector 编辑 .tres。

**文案守则**:只讲机器行为与操作,用纺织语汇(并纹/岔纹/迭层纹/焦纹/封单/借丝);
**不得出现直接的逻辑提示**——逻辑符号(∧ ∨ → ⊥)、逻辑术语(合取/蕴含/放电/爆炸原理)、
规则陈述、解法提示一律不写;也不要用字体没有的符号(见 docs/ART_INTERFACE.md §1)。

## 机器人语音台词

`hardware/firmware/sounds/*.wav`(greet/win/encourage/panic/calm/hint),音色为微软 XiaoyiNeural(小智同款)。改词:
```bash
hardware/.venv/bin/edge-tts --voice zh-CN-XiaoyiNeural --text "新台词" --write-media t.mp3
afconvert -f WAVE -d LEI16@16000 -c 1 t.mp3 hardware/firmware/sounds/win.wav && rm t.mp3
hardware/.venv/bin/mpremote connect /dev/cu.usbmodem2101 fs cp hardware/firmware/sounds/win.wav :sounds/
hardware/.venv/bin/mpremote connect /dev/cu.usbmodem2101 reset   # 传完必须 reset,否则停在 REPL
```
(先停桥接;详见 docs/ROBOT_API.md。)

## 验证改动

```bash
godot --headless --path . --script res://tests/run_tests.gd     # 数据校验(公式可解析、规则存在、角色/场景名合法等)
godot --path . --script res://tests/visual_smoke_m3.gd          # 全 15 关自动通关回归
```
