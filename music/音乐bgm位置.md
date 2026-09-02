# 背景音乐槽位表

引擎按槽位名读 `music/<槽位>.mp3`(也可 .ogg / .wav),自动循环;槽位在代码里的对应表是 `game/bgm.gd` 的 `TRACKS`。
同槽位切页不重启;换槽位交叉淡化 1.2 秒;槽位没曲子 = 该处静音。

| 槽位 | 用在哪 | 文件 | 曲目 / 演奏 / 授权 |
|---|---|---|---|
| title | 进入游戏:标题页、选关页、开发者信息页(三页共用,切页不重启) | `music/title.mp3` | Schubert Piano Sonata in A Major, D.664 - II. Andante;演奏 Paul Pitman;License: CCPD(公有领域) |
| level_1 | 第一章 并纹:进关前故事界面 + 关内 | `music/level.wav` | 原 guanka.wav(37 秒循环);李熠远 与 ChatGPT 共同生成(AI 生成) |
| level_2 | 第二章 叠层纹:故事界面 + 关内 | `music/level.wav`(同上,四章暂共用) | |
| level_3 | 第三章 岔纹:故事界面 + 关内 | `music/level.wav`(同上) | |
| level_4 | 第四章 焦纹:故事界面 + 关内 | `music/level.wav`(同上) | |

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
现值:`title.mp3` −24.0 dBFS(基准)、`level.wav` −18.5 dBFS → 修正 −5.5 dB。
