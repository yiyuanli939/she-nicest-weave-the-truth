# 硬件部分

实体"小机"(小智 AI 桌面机器人,ESP32-S3)与游戏的联动。**总手册:`docs/ROBOT_API.md`**。

```
firmware/       MicroPython 固件(main.py + paj7620.py + sounds/*.wav 语音)
bridge/         串口↔WebSocket 桥接(node bridge.js;带 evt 的客户端消息广播给游戏;板子掉 REPL 自动 Ctrl-D 拉起 + 空闲 ping 看门狗)
                mock_robot.py + selfheal_test.sh:pty 模拟小机,不插真机回归桥接自愈
speech/         语音助手 listen.py(Vosk 离线中文,只认「请指导我 / 请帮帮我」)+ get_model.sh(模型不入库)
run_robot.sh    接入:拉起桥接 + 语音助手(幂等;pid/日志在 .run/)
stop_robot.sh   停掉上面两个
flash_robot.sh  刷固件与语音进小机(mpremote;会先停桥接)
make_voice.sh   生成/更新一句语音(edge-tts XiaoyiNeural → 16k 单声道 → 归一化);make_voices.sh 按 sounds/lines.json 整表重做
make_sfx.py     合成三段「坏掉」音效(第三章故障,不说话)
cam_check.sh    用 MacBook 摄像头验证云台两根轴真的在动(截图在 .run/cam/)
backup/         原厂小智固件整片备份(16MB,esptool 可恢复)
.venv/          esptool + mpremote + pyserial + vosk + sounddevice(不入库)
```

快速起步:插上机器人(**USB 通信 + DC 座 5–12V 给舵机供电,两根都要**)→ `bash hardware/speech/get_model.sh`(一次)→ 游戏里 开发者信息 → 小机维护 → 「接入小机」
(等价于 `bash hardware/run_robot.sh`)→ 第一关对麦克风说「请指导我」。
