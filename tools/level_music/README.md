# 关内曲候选(按乐理自作)

- `THEORY.md`:现学的乐理笔记,每条对应代码里的一个规则(功能和声语法、终止式、乐段 / 乐句结构、四部声部进行、旋律写作、配器、循环与响度)。
- `theory_compose.py`:作曲 + 渲染。乐句计划(16 小节平行乐段:前句 HC、后句 PAC,部分曲目重复一遍带变奏)→ music21 罗马数字取音 →
  四部排列动态规划(禁平行 / 反向 / 隐伏五八度、导音上行解决、七音下行解决、不重复导音、音域与间距、最小位移、高潮塑形)→
  高声部骨架 → 动机化旋律(基本乐思 + 复述 + 片段化延续 + 终止乐思;强拍和弦音、弱拍经过 / 辅助音;跳进 ≤ 小六度、无三全音、跳后反向)→
  配器(GM 音色:音乐盒 / 大键琴 / 钢琴 / 拨弦 / 钟琴 / 弦乐 / 大提琴 / 木鱼)→ mido 写 MIDI → FluidSynth + MuseScore_General.sf3 渲染
  → 取第二遍做无缝循环 → loudnorm -18 LUFS → `out/<id>.wav`(游戏用)+ `.mp3`(试听台)+ `.json`(逐小节和声、终止式、检查结果)。
  独立复核:music21 `VoiceLeadingQuartet` 数平行五八度必须为 0。
- `gen_workshop.py` + `workshop.tpl.html`:把 out/ 嵌成试听台页面(artifact「静语纹关内曲工坊」)。
- 音色库 `sf/MuseScore_General.sf3`(40 MB,MIT,不入库):`curl -L -o tools/level_music/sf/MuseScore_General.sf3 https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf3`;
  需要 `brew install fluidsynth`、venv 里 `pip install music21 mido`。
- 跑:`hardware/.venv/bin/python tools/level_music/theory_compose.py && hardware/.venv/bin/python tools/level_music/gen_workshop.py`。
- 用户在试听台给四章指派后贴回结果:把 `out/<id>.wav` 复制成 `music/level_N.wav`、填 `game/bgm.gd` `TRACKS`、量响度填 `GAIN_DB`。
`tools/` 不进导出包。

## level.wav 改版(不改旋律,只动速度 / 音高 / 明暗 / 空间感)

`level_remix.py` → `out_remix/<id>.wav` + `.mp3` + `level_remix.html`(artifact「level.wav 改版试听」)。7 个版本:原版(对照)、柔和(低通 + 轻混响)、
明亮(快 4% + 中高频提升 + 立体声加宽)、慢速(慢 10% 不变调)、暗调(降两个半音拉回原速 + 长回声)、升调(升两个半音拉回原速)、远处(低通 900 Hz + 大混响 -23 LUFS)、
脉动(按半拍颤音 + 合唱)。循环无缝:原曲循环三遍过滤镜后截中间一遍;响度 loudnorm 统一。用户选定后复制 `out_remix/<id>.wav` → `music/level_N.wav` 并填 `Bgm.TRACKS`。
