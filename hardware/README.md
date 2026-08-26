# 硬件部分

实体"小机"(小智 AI 桌面机器人,ESP32-S3)与游戏的联动。**总手册:`docs/ROBOT_API.md`**。

```
firmware/   MicroPython 固件(main.py + paj7620.py + sounds/*.wav 语音)
bridge/     串口↔WebSocket 桥接(npm run bridge)
backup/     原厂小智固件整片备份(16MB,esptool 可恢复)
.venv/      esptool + mpremote + pyserial(不入库)
```

快速起步:插上机器人 → `cd bridge && npm install && npm run bridge` → 开游戏即联动。
