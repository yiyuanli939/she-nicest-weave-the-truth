# 内容更新指南(策划:改台词/关卡/机器人演出,全程 Inspector,零代码)

当前所有台词为 `[占位]` 测试稿,结构已定,直接替换文字即可。

## 改台词

1. Godot 打开 `levels/data/lXX_*.tres`,Inspector 展开 `intro_dialogue → lines`。
2. 每行 `DialogueLine`:`speaker`(名牌)/ `text`(BBCode 可用)/ `side_right`(名牌/立绘靠右,小机=on)/
   **`robot_cue`**(播到该行触发实体小机演出,可填:`greet celebrate confused hint panic glitch calm think sleep idle`,留空=无)/
   `portrait`(立绘贴图,留空=按 speaker 着色的剪影占位)。
3. `intro_dialogue` 本体还有场景级字段:`location_title`(全屏对话左上的地点铭牌,空=用关卡标题)、
   `background`(背景插图,留空=羊皮纸色块占位)。
4. 保存即生效。开场对话在**进关前的全屏对话场景**播放:点击任意处推进
   (打字中点击=整句显示,显示完点击=下一句),最后一句后再点即进棋盘,无跳过键。

## 改/加关卡

- 关卡字段见 `levels/level_def.gd` 注释。公式格式:`&`=∧ `|`=∨ `>`=→(右结合) `false`=⊥,如 `"A & B > C"`。
- `robot_cue_on_enter` / `robot_cue_on_win`:进关/通关的小机演出(当前没有关卡设 on_enter,留给策划)。
- `allow_bot`:纹样编辑器是否解锁焦纹笔刷(第四章起 on)。
- **设计关卡时注意求解是严格正向的**:仪器输出只由输入 + 玩家钉的纹样决定,不会从目标反推。
  用到封程机(假设 P)、岔纹机(另一支)、溃散机(织出什么)的关,玩家必须点标题栏"钉纹样/钉上口/钉下口"
  给自由纹样赋值;关卡 `atoms` 要包含玩家需要钉的原子。脚本化解法在 `tests/level_solutions.gd` 的 `p` 数组。
- 新增关卡:复制一个 .tres 改字段 → 在 `levels/data/catalog.tres` 对应章节的 `levels` 数组里加进去。顺序即解锁顺序(全线性)。
- 批量重生成(会覆盖!):改 `tools/gen_levels.gd` 的表后跑
  `godot --headless --path . --script res://tools/gen_levels.gd`

## 笔记本

`narrative/data/notebook.tres`:条目 id/标题/正文(BBCode)/示例公式。
关卡 `notebook_unlocks` 填条目 id,通关即解锁。

## 仪器介绍卡(点选机器时弹出)

`narrative/data/rule_guide.tres`:每台仪器一条 `RuleGuide`(rule_id/展示名/一句话 summary/详解 body(BBCode)/示例公式)。
玩家在关卡里点选某台仪器,左下角就弹出对应介绍卡(和棋盘/求解解耦,改文案不碰代码)。
批量改走 `tools/gen_levels.gd` 的 `RULE_GUIDE` 表后重跑生成器;单条改直接在 Inspector 编辑 .tres。

**文案守则(介绍卡/教学页/引导对话通用)**:只讲机器行为与操作,用纺织语汇(并纹/岔纹/迭层纹/焦纹/封单/借丝);
**不得出现直接的逻辑提示**——逻辑符号(∧ ∨ → ⊥)、逻辑术语(合取/蕴含/放电/爆炸原理)、
规则陈述("已有其一便可宣称二者有其一")、解法提示,一律不写。
逻辑同构只在**通关后解锁**的笔记条目(notebook_and/imp/or/bot)里揭示——那是奖励,不是提示。

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
godot --headless --path . --script res://tests/run_tests.gd     # 数据校验(公式可解析、规则存在等)
godot --path . --script res://tests/visual_smoke_m3.gd          # 全 15 关自动通关回归
```
