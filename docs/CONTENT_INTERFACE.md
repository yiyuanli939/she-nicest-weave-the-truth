# 内容更新指南(策划:改台词/关卡/机器人演出,全程 Inspector,零代码)

当前所有台词为 `[占位]` 测试稿,结构已定,直接替换文字即可。

## 改台词

1. Godot 打开 `levels/data/lXX_*.tres`,Inspector 展开 `intro_dialogue → lines`。
2. 每行 `DialogueLine`:`speaker`(名牌)/ `text`(BBCode 可用)/ `side_right`(名牌靠右,小机=on)/
   **`robot_cue`**(播到该行触发实体小机演出,可填:`greet celebrate confused hint panic glitch calm think sleep idle`,留空=无)。
3. 保存即生效(对话在进关时播放,点击推进,右上跳过)。

## 改/加关卡

- 关卡字段见 `levels/level_def.gd` 注释。公式格式:`&`=∧ `|`=∨ `>`=→(右结合) `false`=⊥,如 `"A & B > C"`。
- `robot_cue_on_enter` / `robot_cue_on_win`:进关/通关的小机演出(第五章进关填 `panic`/`glitch`)。
- `allow_bot`:纹样编辑器是否解锁焦纹笔刷(第四章起 on)。
- 新增关卡:复制一个 .tres 改字段 → 在 `levels/data/catalog.tres` 对应章节的 `levels` 数组里加进去。顺序即解锁顺序(全线性)。
- 批量重生成(会覆盖!):改 `tools/gen_levels.gd` 的表后跑
  `godot --headless --path . --script res://tools/gen_levels.gd`

## 笔记本

`narrative/data/notebook.tres`:条目 id/标题/正文(BBCode)/示例公式。
关卡 `notebook_unlocks` 填条目 id,通关即解锁。

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
godot --path . --script res://tests/visual_smoke_m3.gd          # 全 17 关自动通关回归
```
