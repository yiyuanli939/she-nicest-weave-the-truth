# 小机(实体机器人)操作手册与 API

板子:**小智 AI 桌面机器人**,ESP32-S3 N16R8(16MB flash / 8MB PSRAM),SKU `esp32-s3n16r8-emoji-dual`。
外设:SSD1306 OLED 128×64(I2C SDA=41 SCL=42)· 云台双舵机(水平=GPIO11,垂直=GPIO12)·
MAX98357A 功放(I2S BCLK=15 LRC=16 DIN=7)· PAJ7620U2 手势传感器(与 OLED 同 I2C,可能未装,缺失自动降级)·
BOOT 键=GPIO0。

现固件:**MicroPython v1.29.0 + 本项目 `hardware/firmware/main.py`**(+ `paj7620.py`)。
原厂小智固件整片备份在 `hardware/backup/xiaozhi_flash_backup.bin`(16MB,可随时恢复)。

## 链路

```
游戏(Godot autoload "Robot", game/robot_link.gd)
   ⇅ WebSocket ws://127.0.0.1:9800
桥接(hardware/bridge/bridge.js, Node)
   ⇅ USB 串口 /dev/cu.usbmodem* 115200,行分隔 JSON
固件(hardware/firmware/main.py, MicroPython)
```

启动桥接:`cd hardware/bridge && npm install && npm run bridge`。
没有桥接/机器人时游戏静默降级,一切照玩。

## 串口/WS 协议(行分隔 JSON)

### 下行(游戏→机器人)

| 命令 | 说明 |
|---|---|
| `{"cmd":"ping"}` | 心跳,回 `{"evt":"pong"}` |
| `{"cmd":"emote","name":N}` | 表情:`happy sad confused think glitch sleep idle` |
| `{"cmd":"anim","name":N}` | 云台动画:`celebrate`(欢呼摇摆) `panic`(乱动+故障脸) `nod`(点头) `shake`(摇头) `look_pc`(扭头看电脑→轻点头→转回) |
| `{"cmd":"say","name":N}` | 语音:播 `/sounds/N.wav`,播放中屏幕自动做**说话口型**。现有:`greet win encourage panic calm hint` |
| `{"cmd":"gimbal","pan":P,"tilt":T}` | 云台直控。pan 50(左)~130(右),tilt 70(抬头)~110(低头),中心 90/90 |
| `{"cmd":"text","s":"..."}` | OLED 显示 ASCII 文本 3 秒(点阵字体不支持中文) |
| `{"cmd":"cal_look"}` | **屏幕方向校准(自动)**:云台扫描,正对屏幕时朝它挥手(PAJ7620)或按 BOOT 锁定;30s 超时 |
| `{"cmd":"cal_set"}` | 以当前云台角保存为"屏幕方向" |

### 上行(机器人→游戏)

`{"evt":"ready",...}` 开机 · `{"evt":"pong"}` · `{"evt":"button","name":"boot"}` ·
`{"evt":"cal_done","pan":..,"tilt":..}` · `{"evt":"cal_timeout"}` · `{"evt":"err","msg":...}`

屏幕方向存 `/look_cfg.json`,断电不丢。

## 游戏侧高层 cue(Robot.cue("...") / 策划在 .tres 里填 robot_cue)

每个 cue = 表情 + 云台动作 + 语音,定位是**引导伙伴:成功庆祝,失败鼓励**:

| cue | 触发点 | 行为 |
|---|---|---|
| `greet` | 进关 | happy + 点头 + "欢迎回来,织者!" |
| `celebrate` | 通关(`robot_cue_on_win`) | happy + 欢呼舞 + "太棒了!织成了!" |
| `confused` | 接出冲突线(节流 8s) | 困惑脸 + 摇头 + **鼓励**"别灰心,换个口试试,你可以的!" |
| `hint` | 发呆 45s(节流 15s) | 先 `look_pc` **装作看一眼电脑再转回来**,think 脸 + "要不要试试仪器架上的新机器?" |
| `panic` | 第五章失控(`robot_cue_on_enter`) | 故障脸 + 云台乱动 + "警告!推理核心过热!" |
| `calm` | 第五章通关 | happy + 点头 + "谢谢你,织者……" |
| `glitch` `think` `sleep` `idle` | 对话行 robot_cue 任意挂 | 单表情 |

未知 cue 会按 `emote` 原样下发,策划可直接扩展。

## 校准"看电脑方向"

游戏主菜单 → **校准小机**:
- 自动:小机左右张望,正对屏幕时朝它挥手(没装手势传感器就按它的 BOOT 键)。
- 手动:←→↑↓ 微调 + 保存。
结果持久化,之后 `hint` 的"看电脑"就朝这个方向。

## 手势遥操模式(深度学习,可开关)

Mac 摄像头 + MediaPipe(21 手部关键点 + DL 手势分类)→ 隔空玩游戏,小机同步跟手当体感伙伴。

**开关**:主菜单或关卡 HUD 的「手势操控」按钮(需桥接在跑);也可命令行:
```bash
hardware/.venv-teleop/bin/python hardware/teleop/teleop.py            # 摄像头模式
hardware/.venv-teleop/bin/python hardware/teleop/teleop.py --preview  # 带关键点预览窗
hardware/.venv-teleop/bin/python hardware/teleop/teleop.py --test     # 合成手,无摄像头验证链路
```
首次运行 macOS 会弹摄像头授权;模型文件首跑自动下载(hardware/teleop/gesture_recognizer.task)。

**映射**(游戏内 + 小机;遥操不触发语音):

| 手势 | 游戏 | 小机 |
|---|---|---|
| 手移动 | 虚拟光标跟随(EMA 平滑) | 云台跟手(≤10Hz) |
| 捏合(拇指-食指) | 左键按下/抬起 → 点击、拉线、拖节点 | — |
| 握拳 Closed_Fist | 右键 → GraphEdit 拖过线=断线 | glitch 表情 |
| 竖大拇指 Thumb_Up | — | happy+点头 |
| 比 V Victory | — | happy+欢呼舞 |
| 张开手掌 Open_Palm | — | think |
| 无手 >0.6s | 光标隐藏(自动松开按键) | 3s 后回中+idle |

实现链:`teleop.py`(映射表在文件顶部 GESTURE_CMDS 可改)→ 桥接路由(含 `cmd`→串口,其余→广播)→
游戏 `Robot.teleop_hand` → `game/gesture_input.gd` 合成鼠标事件(全部 UI 免改可用)。
**环境**:mediapipe 在 mac 需 py3.12(`hardware/.venv-teleop`,uv 创建);遥操与游戏动画共用舵机属预期。
自动化回归:`godot --path . --script res://tests/teleop_smoke.gd`(bridge 需在跑)。

## 运维

```bash
# 工具(均在 hardware/.venv)
hardware/.venv/bin/python -m esptool --port /dev/cu.usbmodem2101 flash-id   # 探测
hardware/.venv/bin/mpremote connect /dev/cu.usbmodem2101 fs cp hardware/firmware/main.py :main.py  # 更新固件脚本
hardware/.venv/bin/mpremote connect /dev/cu.usbmodem2101 reset

# 语音重生成(微软神经语音 XiaoyiNeural,小智同款音色;需联网)
hardware/.venv/bin/edge-tts --voice zh-CN-XiaoyiNeural --text "文本" --write-media t.mp3
afconvert -f WAVE -d LEI16@16000 -c 1 t.mp3 hardware/firmware/sounds/x.wav && rm t.mp3
# (生成后建议做峰值归一化,离线备选:say -v Tingting/Meijia)

# 恢复原厂小智固件(整片写回)
hardware/.venv/bin/python -m esptool --port /dev/cu.usbmodem2101 erase-flash
hardware/.venv/bin/python -m esptool --port /dev/cu.usbmodem2101 write-flash 0x0 hardware/backup/xiaozhi_flash_backup.bin
```

注意:MicroPython 走 TinyUSB CDC,**DTR/RTS 拉线不能复位芯片**;卡死时按板上 RST/拔插 USB。
先停桥接再用 mpremote(串口独占)。

## 实机验收清单

1. `npm run bridge` → 日志出现"串口已连"。
2. `node hardware/bridge/send.js '{"cmd":"ping"}'` → 回 pong。
3. `send.js '{"cmd":"say","name":"win"}'` → 扬声器出声 + 屏幕口型动。
4. `godot --headless --path . --script res://tests/robot_smoke.gd` → 六个 cue 依次实机演出。
5. 游戏内通一关 → 小机欢呼;故意接错 → 摇头鼓励;发呆 45s → 看一眼电脑回头给提示。
6. 拔掉 USB → 游戏无报错照常玩。
