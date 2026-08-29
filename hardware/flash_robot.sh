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
PORT="${SERIAL_PORT:-$(ls /dev/cu.usbmodem* /dev/cu.usbserial* 2>/dev/null | head -1)}"
[ -n "$PORT" ] || { say "FAIL: 没找到 /dev/cu.usbmodem* 或 /dev/cu.usbserial*(小机没插 USB?)"; exit 1; }

say "[1/5] 停桥接与语音助手(串口独占)"
bash "$HW/stop_robot.sh" >> "$LOG" 2>&1
# 等串口真正被释放(桥接退出需要一点时间),最多 8 秒
for i in {1..16}; do
	lsof "$PORT" "${PORT/cu./tty.}" >/dev/null 2>&1 || break
	sleep 0.5
done
sleep 1
say "[2/5] 刷 main.py / paj7620.py → $PORT"
"$MP" connect "$PORT" fs cp "$HW/firmware/main.py" :main.py >> "$LOG" 2>&1 \
	&& "$MP" connect "$PORT" fs cp "$HW/firmware/paj7620.py" :paj7620.py >> "$LOG" 2>&1 \
	|| { say "FAIL: 拷贝固件脚本失败(板子僵死请按 RST 或拔插 USB 再试)"; exit 1; }
say "[3/5] 刷语音 sounds/*.wav(一次会话拷完,少开关串口;失败整体重试;并删掉板上已不用的旧文件)"
"$MP" connect "$PORT" fs mkdir :sounds >> "$LOG" 2>&1   # 已存在会报错,忽略
CP_ARGS=()
for f in "$HW"/firmware/sounds/*.wav; do
	[ ${#CP_ARGS[@]} -gt 0 ] && CP_ARGS+=("+")
	CP_ARGS+=(fs cp "$f" ":sounds/$(basename "$f")")
done
ok=0
for try in 1 2 3; do
	if "$MP" connect "$PORT" "${CP_ARGS[@]}" >> "$LOG" 2>&1; then ok=1; break; fi
	say "    语音拷贝第 $try 次失败,3 s 后重试"; sleep 3
done
[ "$ok" = 1 ] || { say "FAIL: 拷贝语音失败(看日志;原生 USB 口挂了就按 RST,或改插 UART 口)"; exit 1; }
for f in $("$MP" connect "$PORT" fs ls :sounds 2>/dev/null | awk 'NF>=2 {print $2}'); do
	case "$f" in *.wav) [ -f "$HW/firmware/sounds/$f" ] && continue ;; esac
	"$MP" connect "$PORT" fs rm ":sounds/$f" >> "$LOG" 2>&1 && say "    删除板上旧文件 $f"
done
say "[4/5] 软复位小机并重跑 main.py(Ctrl-B + Ctrl-D;硬复位偶发把板子弄僵,mpremote soft-reset 又不跑 main.py)"
"$HW/.venv/bin/python" "$HW/soft_reset.py" "$PORT" >> "$LOG" 2>&1 || say "    没等到固件 ready(看日志;必要时按 RST)"
sleep 1
say "[5/5] 重新接入"
bash "$HW/run_robot.sh" >> "$LOG" 2>&1
say "DONE"
