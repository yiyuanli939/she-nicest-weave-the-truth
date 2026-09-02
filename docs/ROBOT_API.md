# 小机(实体机器人)操作手册与 API

板子:**小智 AI 桌面机器人**,ESP32-S3 N16R8(16MB flash / 8MB PSRAM),SKU `esp32-s3n16r8-emoji-dual`。
外设:SSD1306 OLED 128×64(I2C SDA=41 SCL=42)· 云台双舵机(水平=GPIO11,垂直=GPIO12)·
MAX98357A 功放(I2S BCLK=15 LRC=16 DIN=7)· PAJ7620U2 手势传感器(与 OLED 同 I2C,可能未装,缺失自动降级)·
BOOT 键=GPIO0。**板上没有麦克风**,语音识别在电脑侧做(见下)。

现固件:**MicroPython v1.29.0 + 本项目 `hardware/firmware/main.py`**(+ `paj7620.py`,语音 `sounds/*.wav`)。
原厂小智固件整片备份在 `hardware/backup/xiaozhi_flash_backup.bin`(16MB,可随时恢复)。

## 两个 USB-C 口(都接同一块 ESP32-S3,插哪个都能玩)

| 口 | 电脑上的名字 | 板上走的是 | 怎么用 |
|---|---|---|---|
| 原生 USB(丝印 USB) | `/dev/cu.usbmodem2101`(序列号随芯片变,换板后名字不同,如 `usbmodem5CBC0272971`) | S3 自带 USB(GPIO19/20)→ MicroPython USB-CDC | 桥接优先选它;刷写快。**TinyUSB 拉不了复位线,僵死只能按 RST** |
| UART(丝印 COM/UART) | `/dev/cu.usbserial-A5069RR4`(FTDI) | USB 转串口 → S3 的 UART0(GPIO43/44) | MicroPython 的 stdio 同时挂在 USB-CDC 和 UART0,这一路同样通;桥接/刷写脚本都会回退到它。FTDI 的 DTR/RTS 接着自动复位线:mpremote 每次开关串口都可能把板子复位一下,所以刷语音改成逐个文件拷 + 失败重试 |

**舵机供电(2026-08-30 排障结论)**:底板左上角有一个圆形 DC 电源座(印 `5-30Vin`),**舵机的 5V 只从这个座经底板稳压来,USB 不给舵机供电**。
只插 USB 时主控/屏幕/功放都正常、固件对 `gimbal` 照样 ack,但两只舵机完全不动、手推无阻力。给 DC 座接 5–12 V(≥2 A,5.5×2.1 圆头)后立刻恢复。
展示时 **USB(通信)和 DC 座(舵机电)两根都要插**。底板边上那个印 `5V` 的 Type-C **不能用来供电**(实测插充电头板子不亮),只认 DC 座 / 旁边的 5.5–30V 螺丝端子。
舵机只插底板上带 `1` / `2` 丝印的两个 3-pin 排针(拨动开关旁边;`1`→GPIO11 pan,`2`→GPIO12 tilt;黄=S 红=V 棕=G),**别插进模组的长母座**(`GND TX RX …` 那排是模组的座位)。

云台和这两个 USB 口无关:两只舵机由主控直接 PWM 驱动 —— GPIO11 = 水平 pan(底座转向,50 左 ~ 130 右;回头 / look_pc / shake 用它),
GPIO12 = 垂直 tilt(俯仰,70 抬头 ~ 110 低头;nod / celebrate 用它,动作一律**先仰(72)后低(100)**——壳子让头本来偏低)。
pan 改了脉宽映射后,板上存的「看电脑方向」角度含义变了,重新校准一次(小机维护 → 自动校准)。
实测(2026-08-30):pan 舵机脉宽推到 3300 / 50 µs 也不再多转,电气极限就是左右各 90°;手能拧到 270° 只是越过限位的空程。
想要中心左右各 135°(总 270°)得换 270° 舵机(9g 同尺寸的 MG90S/SG90 270° 版,500–2500 µs ↔ 270°),换完只改 `main.py` 里 pan 那一行的映射。
**别把舵机推过固件限位**:2026-08-30 一次超限试转让 pan 舵机堵转烧毁、内部短路,把两只舵机共用的 5V 拉死(两只都无阻力,板子正常)。
定位法:断电拔掉一只舵机的插头再上电,另一只有阻力/开机归中 → 拔掉的那只坏了。板上两个 3-pin 舵机插座插反的症状:发 `{"cmd":"gimbal","pan":130}` 时头抬/低而不是转。
固件收到 `gimbal` 会回 ack `{"evt":"gimbal","pan":..,"tilt":..}`,证明命令执行到了 PWM 写入;舵机有没有真的转,用下面的摄像头验证。

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

## 无机器人模式(`Robot.enabled = false`)

没有实体小机的机器(展示用 Windows 笔记本等)用这个模式:**一切指向实体小机的提示与入口都不出现** ——
关内不显示「有困难可以对小机说…」、发呆计时不跑、语音事件不代解;开发者信息页没有「小机维护」按钮;
退出游戏不等小机道晚安;`Robot` 不连桥接、不每帧轮询,`send/launch` 一律静默(`sent_log` 也不记)。剧情里的角色台词照常(那是剧情)。

开关(`game/robot_link.gd resolve_enabled`,优先级从高到低):

1. 启动参数 `--no-robot` / `--robot`(只管本次,不落盘;引擎可能吞掉 `--` 之前的未知参数,推荐写成 `she_nicest.exe -- --no-robot`);
2. `user://save.json` 的 `settings.robot_enabled`(维护面板「机器人:已启用 / 无机器人模式」按钮写入;「重置进度」不清);
3. 平台默认:macOS 开,其它平台关(桥接/语音脚本只在 macOS 能跑)。

切回有机器人:标题页按 **F9**(所有构建可用,界面上没有可见入口)打开维护面板 → 点「机器人:无机器人模式(点击切换)」;
关内提示 / 开发者信息页入口在下次进入场景时生效。测试:`tests/test_robot_logic.gd test_no_robot_mode`、`tests/visual_smoke_ui.gd` S 节。

## 小机维护面板(开发者信息页「小机维护」按钮,仅有机器人时显示;标题页 F9 同一面板,所有构建可用)

- 「机器人:已启用 / 无机器人模式(点击切换)」:见上节;无机器人模式下接入 / 刷入 / 生成语音 / 摄像头四个按钮置灰。

- 状态:桥接 / 串口(小机)/ 语音助手 是否在线。
- 「接入小机」:`run_robot.sh`。「刷入固件与语音」:`flash_robot.sh`(停桥接 → `mpremote fs cp main.py paj7620.py` + `fs cp -r sounds :` → 软复位 → 重新接入),进度日志实时显示。
- 「回头方向:右/左」:「请指导我」时底部云台往哪边转到极限(存 `user://save.json` 的 settings,「重置进度」不清);「试转一下」预览。
- 「小机动作:照常 / 保持不动」:**不动模式** —— 云台直控、云台动画、自动校准一律不发(`RobotLink.STILL_CMDS`),
  表情、语音、口型、屏幕全部照常;舵机坏了 / 展示怕动静时用。同样存 settings,「重置进度」不清。
- 小机声音:音色(微软中文神经语音,默认小艺 = 小智同款)/ 音量(wav 峰值 20–100%)/ 六句台词可直接改 →
  「保存并生成语音」写 `hardware/firmware/sounds/lines.json` 并跑 `make_voices.sh`(edge-tts,需联网)→ 「试听」本机播 → 「刷入固件与语音」送进小机。
  故障(3-1 通关起)**没有台词、不显示任何报警文字**,只放 `hardware/make_sfx.py` 合成的三段坏掉音效(峰值 0.45,比台词的 0.9 轻;想换音效/音量改那个脚本重跑);刷入时会把板上已不用的旧文件删掉。
  **台词称呼女主一律用「诺拉」。**
- 校准「看电脑方向」:自动(小机张望,正对屏幕时朝它挥手或按 BOOT)/ 手动微调 + 保存。结果存板上 `/look_cfg.json`。
- 「摄像头验证云台」:`hardware/cam_check.sh`(下详),用 MacBook 摄像头判定两根轴是否真的转了。
- 状态行还显示固件 `ready` 上报的屏幕 / 功放是否正常(OLED I2C 曾偶发 ENODEV)。

## 摄像头验证云台(`hardware/cam_check.py`)

```bash
bash hardware/cam_check.sh                    # 默认两轴;日志 hardware/.run/cam.log,截图 hardware/.run/cam/
hardware/.venv/bin/python hardware/cam_check.py --list        # 探测摄像头 0..3,存缩略图(iPhone 连续互通相机可能占 0)
hardware/.venv/bin/python hardware/cam_check.py --cam 1 --axis tilt
```
流程:开摄像头暖机 → `cam_preview.png`(**先看这张,小机必须在画面里,而且画面里别有人在动**)→ 桥接 ping/pong 确认固件在跑 →
云台归中抓 3 s 基线(学出 OLED 眨眼那块,判定时忽略)→ pan 130/50、tilt 70/110 各抓一帧比对。
判定:变化像素占比 > max(2%, 5×基线噪声) 才算动了;方向用变化区域内的光流中位数(pan 期望横向、tilt 期望纵向,只警告)。
结果:`cam_report.png`(2×2 带标注)、`cam_<axis>_A/B.png`、末行 `DONE` / `FAIL: …`。
「ack 有 + 没动」= 固件写了 PWM 但舵机没跟 → **先看 DC 座有没有接电**(舵机 5V 只从 DC 座来),再查插座;「没 pong」= 固件没在跑 → 按 RST。
摄像头权限归拉起进程的应用(终端 / Godot),第一次弹窗要允许;venv 里的 OpenCV 若 `import cv2` 为空,
`pip install --force-reinstall --no-deps opencv-contrib-python==5.0.0.93`。

## 剧情弧(按关卡序,`Game.robot_mode()`)

| 阶段 | 模式 | 玩家说「请指导我 / 请帮帮我」 | 其它 cue |
|---|---|---|---|
| l01–l11(第一章 ~ 3-1) | `guide` | 小机 think 脸、底部云台转到极限(方向可设)→ 0.8 s 后游戏**直接代解本关**(不庆祝不鼓励)→ 停 2.5 s 转回 | 照常 |
| l12–l16(3-2 起) | `broken` | 只故障(故障脸 + 乱动 + 坏掉音效,没有台词),不回头不代解 | **全部**变故障演出(sleep 除外) |

**坏掉时点 = 3-1(l11)通关瞬间**:l11 的 `robot_cue_on_win = "panic"`(小机代解通关也演,`Game.notify_solved` 随即置 `Robot.broken`);
**修好时点 = 结局**:l16 通关点「继续」→ 4-3 剧情播完 → 「感谢游玩」黑屏时 `broken = false` + `calm`(`ui/story_scene.gd _play_thanks`)。

关内坏掉前显示提示「有困难可以对小机说:「请指导我」或「请帮帮我」」(`ui/level_scene.gd GUIDE_HINT`);无机器人模式下不显示。

## 串口/WS 协议(行分隔 JSON)

### 下行(游戏→机器人)

| 命令 | 说明 |
|---|---|
| `{"cmd":"ping"}` | 心跳,回 `{"evt":"pong"}` |
| `{"cmd":"emote","name":N}` | 表情:`happy sad confused think glitch sleep idle` |
| `{"cmd":"anim","name":N}` | 云台动画:`celebrate`(欢呼摇摆) `panic`(乱动+故障脸) `nod`(点头) `shake`(摇头) `look_pc`(扭头看电脑→轻点头→转回);动画结束会回到开始时的角度 |
| `{"cmd":"say","name":N}` | 语音:播 `/sounds/N.wav`,播放中屏幕自动做**说话口型**。现有:`greet win encourage hint calm`(台词)+ `glitch1 glitch2 glitch3`(坏掉音效) |
| `{"cmd":"gimbal","pan":P,"tilt":T}` | 云台直控(瞬时到位,无速度参数;省略的轴保持不动)。pan **5(左)~175(右)**(2026-08-30 起换标准 SG90:500–2500 µs ↔ 180°,两端留 5° 余量;原装那只怪舵机是 100–2900 µs,已烧报废),tilt 70(抬头)~110(低头),中心 90/90。空闲时固件不会自己回正 |
| `{"cmd":"text","s":"..."}` | OLED 显示 ASCII 文本 3 秒(点阵字体不支持中文) |
| `{"cmd":"cal_look"}` | **屏幕方向校准(自动)**:云台扫描,正对屏幕时朝它挥手(PAJ7620)或按 BOOT 锁定;30s 超时 |
| `{"cmd":"cal_set"}` | 以当前云台角保存为"屏幕方向" |

| `{"cmd":"probe"}` | **侧口 GPIO4 当示波器**:回 `{"evt":"probe","high_us":H,"low_us":L}`。把舵机排针的 S 脚用跳线接到侧口 `4`,应读到 high ≈ 500–2900、low ≈ 17000–19500;`-2` = 没信号(底板走线没把 PWM 送到舵机座) |
| `{"cmd":"pwm4","us":1500}` / `{"on":false}` | **侧口 GPIO4 输出舵机脉冲**:舵机 S→`4`、红→`3.3`、棕→`GND` 可单独测一只舵机(3.3V 力弱但会动;`us` 500–2500) |

### 上行(机器人/桥接/语音助手 → 游戏)

`{"evt":"ready","fw":"she-nicest-bot 1.1","oled":bool,"audio":bool}` 开机(外设状态)· `{"evt":"pong"}` · `{"evt":"button","name":"boot"}` ·
`{"evt":"gimbal","pan":..,"tilt":..}`(每条 `gimbal` 命令的 ack)·
`{"evt":"cal_done","pan":..,"tilt":..}` · `{"evt":"cal_timeout"}` · `{"evt":"err","msg":...}` ·
`{"evt":"serial","open":true|false}`(桥接:串口连上/断开,连入时先发一次)·
`{"evt":"speech_ready"}` / `{"evt":"speech_alive"}`(语音助手启动 / 每 5 s 心跳,10 s 没心跳游戏判离线)·
`{"evt":"speech","text":"请指导我"}`(命中;3 s 去重)。

## 游戏侧高层 cue(Robot.cue("...") / 策划在 .tres 里填 robot_cue)

每个 cue = 表情 + 云台动作 + 语音(`game/robot_link.gd commands_for()`),定位是**引导伙伴:成功庆祝,失败鼓励**;台词以 `lines.json` 为准:

| cue | 触发点 | 行为 |
|---|---|---|
| `greet` | 进关 / 主菜单问候 | happy + 点头 + "欢迎回来,诺拉!" |
| `celebrate` | 通关(`robot_cue_on_win`;小机代解时不发) | happy + **俯仰轴连续点头**(不左右摇)+ "太棒了!织成了!" |
| `confused` | 接出冲突线(节流 8s;代解期间不发) | 困惑脸 + 摇头 + **鼓励**"别灰心,换个口试试,你可以的!" |
| `hint` | 发呆 45s(节流 15s) | 先 `look_pc` **装作看一眼电脑再转回来**,think 脸 + "要不要试试仪器架上的新机器?" |
| `panic` | l11 通关瞬间(3-1 打完小机坏掉,代解通关也演);故障态下任何 cue 都是这套 | 故障脸 + 云台乱动 + 随机一段**坏掉音效**(`glitch1..3.wav`,`hardware/make_sfx.py` 合成;**没有台词**,屏幕上也不显示任何报警文字) |
| `calm` | 结局「感谢游玩」黑屏(修好那一刻,`ui/story_scene.gd`) | happy + 点头 + "谢谢你,诺拉……" |
| `glitch` `think` `sleep` `idle` | 对话行 robot_cue 任意挂 | 单表情 |

未知 cue 会按 `emote` 原样下发,策划可直接扩展。故障态(`Robot.broken`)由 `Game.start_level` 按关卡序设置(l12 起;
l11 通关瞬间由 `notify_solved` 置真,结局黑屏由 `StoryScene._play_thanks` 置假),节流 6 s。

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

注意:原生 USB 口走 TinyUSB CDC,**DTR/RTS 拉线不能复位芯片**;卡死时按板上 RST/拔插 USB(2026-08-29 硬复位后僵死过一次,
flash 脚本与固件崩溃恢复都改成了软复位)。固件现在自愈:OLED/功放 I2C/I2S 出错只降级,崩溃 1.5 s 后软复位,不再落回 REPL。
**桥接也自愈**(`bridge.js`):板子若仍掉进 REPL(Ctrl-C、mpremote 拷完没复位、旧固件崩溃),我们发的 JSON 会被 REPL 当表达式吃掉并回显
`>>> {...}`;桥接一看到 `>>>` 就发 Ctrl-B + Ctrl-D 软复位重跑 main.py(广播 `{"evt":"repl_kick"}`),并且板子空闲 5 s 没输出就 ping 一次当看门狗,
让 REPL 状态一定暴露出来。不插真机也能回归:`bash hardware/bridge/selfheal_test.sh`(pty 模拟停在 REPL 的小机)。
另:`hardware/.run/bridge.log` 的时间戳是 **UTC**(本地 +8)。
先停桥接再用 mpremote(串口独占;`flash_robot.sh` 已包含,连手动起的 `npm run bridge` 也会停)。
`fs mkdir` 目录已存在会报错;语音逐个 `fs cp x.wav :sounds/x.wav`(别 `cp -r` 整个目录,会把 .import 也拷上去)。

## 换板 / 重刷 MicroPython

```bash
bash hardware/stop_robot.sh
PORT=$(ls /dev/cu.* | grep -E "usbmodem|usbserial" | head -1)
hardware/.venv/bin/python -m esptool --chip esp32s3 --port $PORT read-flash 0 0x1000000 hardware/backup/xiaozhi_flash_backup_<板名>.bin   # 先备份原厂(默认波特;921600 会中断)
hardware/.venv/bin/python -m esptool --chip esp32s3 --port $PORT erase-flash
hardware/.venv/bin/python -m esptool --chip esp32s3 --port $PORT --baud 921600 write-flash -z 0x0 hardware/firmware/ESP32_GENERIC_S3-20260824-v1.29.0.bin
bash hardware/flash_robot.sh      # 灌 main.py / paj7620.py / sounds,软复位,重起桥接
```
原厂固件走 USB-JTAG,esptool 能自动进下载模式;刷成 MicroPython(TinyUSB)后原生口不能自动复位,esptool 要按住 BOOT 点 RST,或走 UART 口。

## 实机验收清单

0. **USB 和 DC 座两根线都插上**(DC 座不接电舵机不动)。
1. 小机维护 → 接入小机 → 状态三行全部在线(语音助手第一次会弹麦克风权限)。
2. 「试转一下」云台转到一侧再回正;「试听」六句本机能播。
3. 刷入固件与语音 → 日志走到 DONE,小机重启后 `ready`。
4. `godot --headless --path . --script res://tests/robot_smoke.gd` → 六个 cue + 回头/回正依次实机演出;
   `tests/robot_turn_smoke.gd` 只测回头:右极限 → 回正 → 左极限 → 回正,每步等固件 ack(退出码 = 失败数)。
   `bash hardware/cam_check.sh` 用摄像头判定舵机真的转了(小机要在画面里)。
5. 进第一纹对麦克风说「请指导我」→ 小机回头 → 关卡自动织成、小机不欢呼 → 转回;3-1(l11)打完小机当场故障演出并坏掉;
   3-2 起说话只故障、不回头;打完 l16 点「继续」看完结局,「感谢游玩」黑屏时小机修好(calm)。
6. 拔掉 USB → 游戏无报错照常玩。
