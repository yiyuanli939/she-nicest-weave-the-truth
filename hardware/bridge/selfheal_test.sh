#!/bin/zsh
# 桥接自愈回归(不用真机):pty 模拟一个停在 REPL 的小机 → 起一个测试桥接(9801 口)→ 期待它自动 Ctrl-D 拉起 main.py、
# 之后 gimbal 有 ack、空闲看门狗 ping 有 pong。退出码 = 失败数。用法: bash hardware/bridge/selfheal_test.sh
HW="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$HW/.run"; mkdir -p "$RUN"
PORT=9801; LOG="$RUN/selfheal_test.log"; PTYF="$RUN/selfheal_pty.path"
rm -f "$PTYF"; : > "$LOG"
"$HW/.venv/bin/python" "$HW/bridge/mock_robot.py" "$PTYF" > /dev/null 2>&1 &
MOCK=$!
for i in {1..20}; do [ -s "$PTYF" ] && break; sleep 0.2; done
PTY="$(cat "$PTYF")"
[ -n "$PTY" ] || { echo "FAIL: mock pty 没起来"; kill $MOCK 2>/dev/null; exit 1; }
(cd "$HW/bridge" && SERIAL_PORT="$PTY" BRIDGE_PORT=$PORT exec node bridge.js > "$LOG" 2>&1) &
BRIDGE=$!
sleep 2.5
(cd "$HW/bridge" && BRIDGE_PORT=$PORT node send.js '{"cmd":"gimbal","pan":120}' > "$RUN/selfheal_send.log" 2>&1)
sleep 7   # 等一轮空闲看门狗(5 s)
kill $BRIDGE $MOCK 2>/dev/null; wait $BRIDGE $MOCK 2>/dev/null
fails=0
chk() { if grep -q -- "$1" "$2"; then echo "✓ $3"; else echo "✗ $3"; fails=$((fails+1)); fi; }
chk '>>> {"cmd":"ping"}' "$LOG" "停在 REPL 的板子把开机 ping 回显了出来"
chk '小机停在 REPL' "$LOG" "桥接识别出 REPL 并发软复位"
chk '"evt": "ready"' "$LOG" "软复位后固件 ready"
chk '"evt": "gimbal", "pan": 120' "$RUN/selfheal_send.log" "自愈后 gimbal 命令有 ack"
chk '"evt": "pong"' "$LOG" "空闲看门狗 ping 有 pong"
echo "SELFHEAL_FAILS=$fails"; exit $fails
