# 用 pty 模拟小机(不插机器人也能测桥接):开始停在 MicroPython REPL(回显 ">>> 行" 并求值),
# 收到 Ctrl-D 才"软复位"进 main.py 模式(ping 回 pong,gimbal 回 ack)。
#   hardware/.venv/bin/python hardware/bridge/mock_robot.py <把 pty 路径写到这个文件>
# 由 selfheal_test.sh 调用,验证 bridge.js 的掉 REPL 自愈与看门狗。
import os, pty, sys, json, time, select
m, s = pty.openpty(); path = os.ttyname(s)
open(sys.argv[1], "w").write(path); print("mock pty:", path, flush=True)
mode = "repl"; buf = b""
def w(t): os.write(m, t.encode())
while True:
    r, _, _ = select.select([m], [], [], 0.05)
    if not r: continue
    data = os.read(m, 1024)
    for b in data:
        c = bytes([b])
        if c == b"\x04":
            mode = "run"; buf = b""; w("MPY: soft reboot\r\n"); time.sleep(0.2)
            w('{"evt": "ready", "fw": "mock"}\r\n')
        elif c == b"\x02":
            if mode == "repl": w("\r\nMicroPython mock\r\n>>> ")
        elif c in (b"\r", b"\n"):
            line = buf.decode("utf-8", "replace").strip(); buf = b""
            if not line: continue
            if mode == "repl":
                w(">>> " + line + "\r\n")   # REPL 回显 + 求值
                try: w(repr(json.loads(line)) + "\r\n")
                except Exception: w("SyntaxError: invalid syntax\r\n")
            else:
                try: d = json.loads(line)
                except Exception: continue
                if d.get("cmd") == "ping": w('{"evt": "pong"}\r\n')
                elif d.get("cmd") == "gimbal": w(json.dumps({"evt": "gimbal", "pan": d.get("pan", 90), "tilt": d.get("tilt", 90)}) + "\r\n")
        else:
            buf += c
