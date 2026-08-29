#!/bin/zsh
# 接入小机(幂等):拉起串口↔ws 桥接(node bridge.js)与语音助手(python speech/listen.py)。
# pid/日志在 hardware/.run/。游戏「小机维护」面板的「接入小机」按钮就是跑这个脚本。
HW="$(cd "$(dirname "$0")" && pwd)"
RUN="$HW/.run"
mkdir -p "$RUN"
alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

if alive "$RUN/bridge.pid"; then
	echo "桥接已在运行(pid $(cat "$RUN/bridge.pid"))"
else
	if [ ! -d "$HW/bridge/node_modules" ]; then
		echo "安装桥接依赖…"
		(cd "$HW/bridge" && npm install --silent) || { echo "FAIL: npm install 失败"; exit 1; }
	fi
	# exec 让子 shell 直接变成 node,pid 文件里才是 node 本身(否则 stop 只杀掉壳,node 变孤儿继续占串口)
	(cd "$HW/bridge" && exec nohup node bridge.js >> "$RUN/bridge.log" 2>&1) &
	echo $! > "$RUN/bridge.pid"
	echo "桥接已启动(pid $(cat "$RUN/bridge.pid"))"
fi

if alive "$RUN/speech.pid"; then
	echo "语音助手已在运行(pid $(cat "$RUN/speech.pid"))"
elif [ ! -f "$HW/speech/model/graph/HCLr.fst" ]; then
	echo "语音模型缺失:先跑 hardware/speech/get_model.sh(不影响桥接)"
elif [ ! -x "$HW/.venv/bin/python" ]; then
	echo "缺 hardware/.venv(pip install vosk sounddevice)"
else
	(cd "$HW" && exec nohup .venv/bin/python speech/listen.py >> "$RUN/speech.log" 2>&1) &
	echo $! > "$RUN/speech.pid"
	echo "语音助手已启动(pid $(cat "$RUN/speech.pid"))"
fi
