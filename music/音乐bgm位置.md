# 背景音乐槽位表

引擎按槽位名读 `music/<槽位>.mp3`(也可 .ogg / .wav),自动循环;槽位在代码里的对应表是 `game/bgm.gd` 的 `TRACKS`。
同槽位切页不重启;换槽位交叉淡化 1.2 秒;槽位没曲子 = 该处静音。
进关前的故事界面(全屏开场对话)与结局对话**用标题曲**(2026-09-02 用户定):从选关进来它本来就在播,接着播不重启;
从棋盘进来(下一关的开场、l16 通关后的结局)关内曲淡出、标题曲淡入。关内曲只在棋盘起;结局黑屏与开发者信息页延续标题曲。

| 槽位 | 用在哪 | 文件 | 曲目 / 演奏 / 授权 |
|---|---|---|---|
| title | 进入游戏:标题页、选关页、故事界面(开场 / 结局对话)、开发者信息页(共用,切页不重启) | `music/title.mp3` | Schubert Piano Sonata in A Major, D.664 - II. Andante;演奏 Paul Pitman;License: CCPD(公有领域) |
| level_1 | 第一章 并纹:关内(棋盘) | `music/level_1.wav` | level.wav 柔和版(低通 1.8 kHz + 轻混响;`tools/level_music/level_remix.py` soft,2026-09-02 用户选定) |
| level_2 | 第二章 叠层纹:关内 | `music/level_2.wav` | level.wav 脉动版(半拍颤音 + 合唱;pulse) |
| level_3 | 第三章 岔纹:关内 | `music/level_3.wav` | level.wav 暗调版(降两个半音拉回原速 + 低通 + 长回声;dark) |
| level_4 | 第四章 焦纹:关内 | `music/level.wav` | 原版:原 guanka.wav(37 秒循环);李熠远 与 ChatGPT 共同生成(AI 生成) |

## 补曲 / 换曲

1. 文件放到 `music/<槽位>.mp3`(换曲直接覆盖同名文件;几章共用一首就在 `TRACKS` 里填同一个路径,换章不会重启)。
   某章要单独配曲:放 `music/level_N.mp3`,把 `TRACKS` 里那一章改成它。
2. 新槽位第一次填曲:`game/bgm.gd` `TRACKS` 里把该槽位的 `""` 改成 `"res://music/<槽位>.mp3"`;之后换曲不用改代码。
3. `godot --headless --path . --import` 生成 `.import`(和音频文件一起提交),再跑 `tests/run_tests.gd`(会检查表里的文件都存在)。
   wav 不用在 `.import` 里设循环:引擎运行时(`Bgm.set_looping`)把没有循环点的 wav 设成整曲循环;
   wav 自带 smpl 循环点(剪好首尾的无缝循环)会保留。
4. 在这张表里补上曲目 / 演奏 / 授权;开发者信息页的署名在 `ui/credits_scene.gd` `LINES`。

循环接缝:MP3 从头循环会有编码填充的小空隙,想无缝循环交剪好首尾的 OGG。

## 响度

各曲响度不一时在 `game/bgm.gd` `GAIN_DB` 按文件填 dB 修正,基准是标题曲(0)。量法(macOS):
`afconvert -f WAVE -d LEI16 x.mp3 x.wav` 后算 16-bit 样本的 RMS(dBFS)。
现值:`title.mp3` −24.0 dBFS(基准)、`level.wav` −18.5 dBFS → 修正 −5.5 dB;改版 `level_1/3.wav` −20.9 → −3.0,`level_2.wav` −19.9 → −4.0
(改版由 ffmpeg loudnorm 归一,重出后用 `ffmpeg -af volumedetect` 看 mean_volume 再填)。
