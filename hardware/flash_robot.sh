#!/bin/zsh
# 把固件与语音刷进小机:停桥接/语音助手(串口独占)→ mpremote 拷 main.py/paj7620.py/sounds → 软复位 → 重新接入。
# 用法: bash hardware/flash_robot.sh [日志文件]   (游戏「小机维护」面板的「刷入固件与语音」按钮就是跑这个)
# 日志逐行 [i/5] …,末行 DONE 或 FAIL: …;端口取 SERIAL_PORT 或第一个 /dev/cu.usbmodem*。
HW="$(cd "$(dirname "$0")" && pwd)"
LOG="${1:-$HW/.run/flash.log}"
mkdir -p "$(dirname "$LOG")"
: > "$LOG"
say() { echo "$1" | tee -a "$LOG"; }
MP="$HW/.venv/bin/mpremote"
[ -x "$MP" ] || { say "FAIL: 缺 $MP(hardware/.venv 未装 mpremote)"; exit 1; }
PORT="${SERIAL_PORT:-$(ls /dev/cu.usbmodem* 2>/dev/null | head -1)}"
[ -n "$PORT" ] || { say "FAIL: 没找到 /dev/cu.usbmodem*(小机没插 USB?)"; exit 1; }

say "[1/5] 停桥接与语音助手(串口独占)"
bash "$HW/stop_robot.sh" >> "$LOG" 2>&1
sleep 1
say "[2/5] 刷 main.py / paj7620.py → $PORT"
"$MP" connect "$PORT" fs cp "$HW/firmware/main.py" :main.py >> "$LOG" 2>&1 \
	&& "$MP" connect "$PORT" fs cp "$HW/firmware/paj7620.py" :paj7620.py >> "$LOG" 2>&1 \
	|| { say "FAIL: 拷贝固件脚本失败(板子僵死请按 RST 或拔插 USB 再试)"; exit 1; }
say "[3/5] 刷语音 sounds/"
(cd "$HW/firmware" && "$MP" connect "$PORT" fs cp -r sounds :) >> "$LOG" 2>&1 \
	|| { say "FAIL: 拷贝语音失败"; exit 1; }
say "[4/5] 复位小机"
"$MP" connect "$PORT" reset >> "$LOG" 2>&1
sleep 2
say "[5/5] 重新接入"
bash "$HW/run_robot.sh" >> "$LOG" 2>&1
say "DONE"
