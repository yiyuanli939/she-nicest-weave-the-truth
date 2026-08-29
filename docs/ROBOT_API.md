# 小机(实体机器人)操作手册与 API

板子:**小智 AI 桌面机器人**,ESP32-S3 N16R8(16MB flash / 8MB PSRAM),SKU `esp32-s3n16r8-emoji-dual`。
外设:SSD1306 OLED 128×64(I2C SDA=41 SCL=42)· 云台双舵机(水平=GPIO11,垂直=GPIO12)·
MAX98357A 功放(I2S BCLK=15 LRC=16 DIN=7)· PAJ7620U2 手势传感器(与 OLED 同 I2C,可能未装,缺失自动降级)·
BOOT 键=GPIO0。**板上没有麦克风**,语音识别在电脑侧做(见下)。

现固件:**MicroPython v1.29.0 + 本项目 `hardware/firmware/main.py`**(+ `paj7620.py`,语音 `sounds/*.wav`)。
原厂小智固件整片备份在 `hardware/backup/xiaozhi_flash_backup.bin`(16MB,可随时恢复)。

## 链路

```
麦克风 → hardware/speech/listen.py(Vosk 离线中文,只认「请指导我 / 请帮帮我」)──┐ ws 客户端,发 {"evt":"speech"}
游戏(Godot autoload "Robot", game/robot_link.gd) ⇅ WebSocket ws://127.0.0.1:9800 ─┤
桥接(hardware/bridge/bridge.js, Node)  带 evt 的客户端消息只广播给其它客户端;其余下串口 ─┘
   ⇅ USB 串口 /dev/cu.usbmodem* 115200,行分隔 JSON
固件(hardware/firmware/main.py, MicroPython)
```

一键接入:游戏 **开发者信息 → 小机维护 → 「接入小机」**(= `bash hardware/run_robot.sh`,幂等拉起桥接 + 语音助手;
pid/日志在 `hardware/.run/`;`stop_robot.sh` 停掉)。没有桥接/机器人时游戏静默降级,一切照玩。

首次准备:`bash hardware/speech/get_model.sh`(下载 42MB 模型,不入库);venv 已含 vosk/sounddevice/mpremote/edge-tts。
麦克风权限归"拉起进程的应用":从 Dock 开的 Godot 拉起 → macOS 向 Godot 要权限;从终端跑 → 向终端要。第一次点「允许」。
导出正式版时导出预设要开 Audio Input 并填 microphone usage description(仓库还没有 export_presets.cfg)。

## 小机维护面板(开发者信息页「小机维护」按钮;标题页调试版 F9 同一面板)

- 状态:桥接 / 串口(小机)/ 语音助手 是否在线。
- 「接入小机」:`run_robot.sh`。「刷入固件与语音」:`flash_robot.sh`(停桥接 → `mpremote fs cp main.py paj7620.py` + `fs cp -r sounds :` → 软复位 → 重新接入),进度日志实时显示。
- 「回头方向:右/左」:「请指导我」时底部云台往哪边转到极限(存 `user://save.json` 的 settings,「重置进度」不清);「试转一下」预览。
- 小机声音:音色(微软中文神经语音,默认小艺 = 小智同款)/ 音量(wav 峰值 20–100%)/ 六句台词可直接改 →
  「保存并生成语音」写 `hardware/firmware/sounds/lines.json` 并跑 `make_voices.sh`(edge-tts,需联网)→ 「试听」本机播 → 「刷入固件与语音」送进小机。
  **台词称呼女主一律用「诺拉」。**
- 校准「看电脑方向」:自动(小机张望,正对屏幕时朝它挥手或按 BOOT)/ 手动微调 + 保存。结果存板上 `/look_cfg.json`。

## 剧情弧(按章节,`Game.robot_mode()`)

| 章 | 模式 | 玩家说「请指导我 / 请帮帮我」 | 其它 cue |
|---|---|---|---|
| 一、二 | `guide` | 小机 think 脸、底部云台转到极限(方向可设)→ 0.8 s 后游戏**直接代解本关**(不庆祝不鼓励)→ 停 2.5 s 转回 | 照常 |
| 三 | `broken` | 只故障(故障脸 + 乱动 + 故障声),不回头不代解 | **全部**变故障演出(sleep 除外);l10 进关 `panic` = 坏掉那一刻 |
| 四 | `look` | 只回头看你 1.5 s 再转回,不代解 | 照常;l13 进关 `calm` = 修好那一刻 |

关内一二章显示提示「有困难可以对小机说:「请指导我」或「请帮帮我」」(`ui/level_scene.gd GUIDE_HINT`)。

## 串口/WS 协议(行分隔 JSON)

### 下行(游戏→机器人)

| 命令 | 说明 |
|---|---|
| `{"cmd":"ping"}` | 心跳,回 `{"evt":"pong"}` |
| `{"cmd":"emote","name":N}` | 表情:`happy sad confused think glitch sleep idle` |
| `{"cmd":"anim","name":N}` | 云台动画:`celebrate`(欢呼摇摆) `panic`(乱动+故障脸) `nod`(点头) `shake`(摇头) `look_pc`(扭头看电脑→轻点头→转回);动画结束会回到开始时的角度 |
| `{"cmd":"say","name":N}` | 语音:播 `/sounds/N.wav`,播放中屏幕自动做**说话口型**。现有:`greet win encourage panic calm hint` |
| `{"cmd":"gimbal","pan":P,"tilt":T}` | 云台直控(瞬时到位,无速度参数;省略的轴保持不动)。pan 50(左)~130(右),tilt 70(抬头)~110(低头),中心 90/90。空闲时固件不会自己回正 |
| `{"cmd":"text","s":"..."}` | OLED 显示 ASCII 文本 3 秒(点阵字体不支持中文) |
| `{"cmd":"cal_look"}` | **屏幕方向校准(自动)**:云台扫描,正对屏幕时朝它挥手(PAJ7620)或按 BOOT 锁定;30s 超时 |
| `{"cmd":"cal_set"}` | 以当前云台角保存为"屏幕方向" |

### 上行(机器人/桥接/语音助手 → 游戏)

`{"evt":"ready",...}` 开机 · `{"evt":"pong"}` · `{"evt":"button","name":"boot"}` ·
`{"evt":"cal_done","pan":..,"tilt":..}` · `{"evt":"cal_timeout"}` · `{"evt":"err","msg":...}` ·
`{"evt":"serial","open":true|false}`(桥接:串口连上/断开,连入时先发一次)·
`{"evt":"speech_ready"}` / `{"evt":"speech_alive"}`(语音助手启动 / 每 5 s 心跳,10 s 没心跳游戏判离线)·
`{"evt":"speech","text":"请指导我"}`(命中;3 s 去重)。

## 游戏侧高层 cue(Robot.cue("...") / 策划在 .tres 里填 robot_cue)

每个 cue = 表情 + 云台动作 + 语音(`game/robot_link.gd commands_for()`),定位是**引导伙伴:成功庆祝,失败鼓励**;台词以 `lines.json` 为准:

| cue | 触发点 | 行为 |
|---|---|---|
| `greet` | 进关 / 主菜单问候 | happy + 点头 + "欢迎回来,诺拉!" |
| `celebrate` | 通关(`robot_cue_on_win`;小机代解时不发) | happy + 欢呼舞 + "太棒了!织成了!" |
| `confused` | 接出冲突线(节流 8s;代解期间不发) | 困惑脸 + 摇头 + **鼓励**"别灰心,换个口试试,你可以的!" |
| `hint` | 发呆 45s(节流 15s) | 先 `look_pc` **装作看一眼电脑再转回来**,think 脸 + "要不要试试仪器架上的新机器?" |
| `panic` | l10 进关(第三章开头坏掉);故障态下任何 cue 都是这套 | 故障脸 + 云台乱动 + "警告!推理核心过热!" |
| `calm` | l13 进关(第四章开头修好) | happy + 点头 + "谢谢你,诺拉……" |
| `glitch` `think` `sleep` `idle` | 对话行 robot_cue 任意挂 | 单表情 |

未知 cue 会按 `emote` 原样下发,策划可直接扩展。故障态(`Robot.broken`)由 `Game.start_level` 按章节设置,节流 6 s。

## 运维(命令行等价物)

```bash
bash hardware/run_robot.sh                 # 接入(桥接 + 语音助手)
bash hardware/stop_robot.sh                # 停
bash hardware/flash_robot.sh               # 刷固件与语音(会先停桥接;日志 hardware/.run/flash.log)
bash hardware/make_voice.sh win "太棒了!" [音色] [音量]   # 改一句语音
bash hardware/make_voices.sh               # 按 firmware/sounds/lines.json 整表重做
tail -f hardware/.run/speech.log           # 语音自测:说一句,看「命中」行

# 底层工具(均在 hardware/.venv)
hardware/.venv/bin/python -m esptool --port /dev/cu.usbmodem2101 flash-id   # 探测
hardware/.venv/bin/mpremote connect /dev/cu.usbmodem2101 fs cp hardware/firmware/main.py :main.py
hardware/.venv/bin/mpremote connect /dev/cu.usbmodem2101 reset               # 软复位(能用)

# 恢复原厂小智固件(整片写回)
hardware/.venv/bin/python -m esptool --port /dev/cu.usbmodem2101 erase-flash
hardware/.venv/bin/python -m esptool --port /dev/cu.usbmodem2101 write-flash 0x0 hardware/backup/xiaozhi_flash_backup.bin
```

注意:MicroPython 走 TinyUSB CDC,**DTR/RTS 拉线不能复位芯片**;卡死时按板上 RST/拔插 USB。
先停桥接再用 mpremote(串口独占;`flash_robot.sh` 已包含)。`fs mkdir` 目录已存在会报错,拷目录用 `fs cp -r sounds :`。

## 实机验收清单

1. 小机维护 → 接入小机 → 状态三行全部在线(语音助手第一次会弹麦克风权限)。
2. 「试转一下」云台转到一侧再回正;「试听」六句本机能播。
3. 刷入固件与语音 → 日志走到 DONE,小机重启后 `ready`。
4. `godot --headless --path . --script res://tests/robot_smoke.gd` → 六个 cue + 回头/回正依次实机演出。
5. 进第一纹对麦克风说「请指导我」→ 小机回头 → 关卡自动织成、小机不欢呼 → 转回;第三章进关小机故障、说话只故障;第四章进关平静、说话只回头。
6. 拔掉 USB → 游戏无报错照常玩。
