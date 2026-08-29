#!/bin/zsh
# 摄像头验证云台:bash hardware/cam_check.sh [日志文件] [其它 cam_check.py 参数…]
HW="$(cd "$(dirname "$0")" && pwd)"
LOG="${1:-$HW/.run/cam.log}"; shift 2>/dev/null
mkdir -p "$(dirname "$LOG")"
exec "$HW/.venv/bin/python" "$HW/cam_check.py" --log "$LOG" "$@"
