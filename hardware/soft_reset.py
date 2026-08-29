#!/usr/bin/env python3
"""软复位小机并重跑 main.py:发 Ctrl-B(退出 raw REPL 回友好 REPL)+ Ctrl-D(软复位 → boot.py/main.py)。
不重枚举 USB(硬复位偶发把原生 USB 口弄僵)。mpremote 自带的 soft-reset 停在 raw REPL、不跑 main.py,所以自己发。
用法: hardware/.venv/bin/python hardware/soft_reset.py <串口>   → 打印固件 ready 行,没等到退出码 1"""
import sys, time, serial
port = sys.argv[1]
s = serial.Serial(port, 115200, timeout=0.2)
s.write(b"\x02"); time.sleep(0.3)
s.write(b"\x04"); time.sleep(0.5)
buf = b""; t0 = time.time(); ok = False
while time.time() - t0 < 8:
    buf += s.read(4096)
    if b'"evt": "ready"' in buf or b'"evt":"ready"' in buf:
        ok = True; break
s.close()
txt = buf.replace(b"\x00", b"").decode("utf-8", "replace")
line = next((l for l in txt.splitlines() if '"ready"' in l), "")
print("ready:", line if ok else "没等到(8 s):" + txt[-300:])
sys.exit(0 if ok else 1)
