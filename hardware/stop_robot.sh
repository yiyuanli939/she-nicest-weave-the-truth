#!/bin/zsh
# 停掉 run_robot.sh 拉起的桥接与语音助手(刷固件前必须:串口独占)。
HW="$(cd "$(dirname "$0")" && pwd)"
RUN="$HW/.run"
for name in bridge speech; do
	f="$RUN/$name.pid"
	if [ -f "$f" ] && kill -0 "$(cat "$f")" 2>/dev/null; then
		kill "$(cat "$f")" 2>/dev/null && echo "已停 $name(pid $(cat "$f"))"
	fi
	rm -f "$f"
done
# 手动起的(npm run bridge / python listen.py)也一并停掉:刷固件要独占串口
pkill -f "bridge.js" 2>/dev/null && echo "已停手动起的桥接"
pkill -f "speech/listen.py" 2>/dev/null && echo "已停手动起的语音助手"
exit 0
