#!/usr/bin/env python3
"""用电脑摄像头验证小机云台两根轴真的在动(OpenCV 抓帧比对,不看日志看像素)。

    hardware/.venv/bin/python hardware/cam_check.py [--axis pan|tilt|both] [--cam N] [--list] [--out DIR] [--log FILE]

流程:开摄像头暖机 → 存 cam_preview.png(人眼确认小机在画面里)→ 经桥接 ping/pong 确认固件在跑 →
云台归中抓基线(学出 OLED 眨眼/口型那块,判定时忽略)→ pan 130 / 50、tilt 70 / 110 各抓一帧比对。
判定:变化像素占比 > max(2%, 5×基线噪声) = 动了;方向用变化区域内 Farneback 光流中位数(pan 期望横向,tilt 期望纵向,只警告)。
日志逐行 [i/n] …,末行 DONE / FAIL: …;截图 cam_pan_A/B.png、cam_tilt_A/B.png、cam_report.png。
摄像头权限归拉起本进程的应用(终端 / Godot),第一次弹窗要允许;iPhone 连续互通相机在线时可能占到 index 0,用 --list 看缩略图后 --cam 选。
"""
import argparse
import json
import math
import os
import sys
import time

import cv2
import numpy as np

HW = os.path.dirname(os.path.abspath(__file__))
BRIDGE_URL = os.environ.get("BRIDGE_URL", "ws://127.0.0.1:9800")
PAN = {"A": 130, "B": 50, "C": 90}
TILT = {"A": 70, "B": 110, "C": 90}
LOG_FH = None


def say(msg: str) -> None:
    print(msg, flush=True)
    if LOG_FH:
        LOG_FH.write(msg + "\n")
        LOG_FH.flush()


def fail(msg: str, code: int = 1) -> int:
    say("FAIL: " + msg)
    return code


# ---- 摄像头 ----

def open_cam(index: int, retry_sec: float = 30.0):
    """第一次授权弹窗期间 isOpened() 会先 False:每秒重试。"""
    deadline = time.time() + retry_sec
    while True:
        cap = cv2.VideoCapture(index, cv2.CAP_AVFOUNDATION)
        if cap.isOpened():
            ok, _ = cap.read()
            if ok:
                return cap
        cap.release()
        if time.time() > deadline:
            return None
        time.sleep(1.0)


def warm_up(cap, out_dir: str):
    """读满 1 s 且连续 5 帧灰度均值稳定(最多 60 帧),存预览。"""
    means, frame, t0 = [], None, time.time()
    for _ in range(60):
        ok, f = cap.read()
        if not ok:
            continue
        frame = f
        means.append(float(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY).mean()))
        if time.time() - t0 > 1.0 and len(means) >= 5 and max(means[-5:]) - min(means[-5:]) < 1.0:
            break
    if frame is not None:
        cv2.imwrite(os.path.join(out_dir, "cam_preview.png"), frame)
    return frame


def grab(cap):
    for _ in range(3):
        cap.read()          # 丢掉缓冲里可能的旧帧
    ok, f = cap.read()
    return f if ok else None


def prep(f):
    return cv2.GaussianBlur(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY), (5, 5), 0)


def diff_mask(a, b, thr: int = 25):
    m = cv2.threshold(cv2.absdiff(a, b), thr, 255, cv2.THRESH_BINARY)[1]
    return cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))


# ---- 桥接 ----

class Bridge:
    def __init__(self, url: str):
        from websockets.sync.client import connect
        try:
            self.ws = connect(url, open_timeout=2, legacy=True)
        except TypeError:
            self.ws = connect(url, open_timeout=2)

    def send(self, obj: dict) -> None:
        self.ws.send(json.dumps(obj))

    def wait_evt(self, name: str, timeout: float):
        """等某个 evt(其它事件丢弃),超时返回 None。"""
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                raw = self.ws.recv(timeout=max(0.05, deadline - time.time()))
            except Exception:
                return None
            try:
                d = json.loads(raw)
            except Exception:
                continue
            if isinstance(d, dict) and d.get("evt") == name:
                return d
        return None

    def gimbal(self, **kw) -> bool:
        self.send({"cmd": "gimbal", **kw})
        return self.wait_evt("gimbal", 2.0) is not None

    def close(self) -> None:
        try:
            self.ws.close()
        except Exception:
            pass


# ---- 判定 ----

def measure(a, b, ignore):
    A, B = prep(a), prep(b)
    m = diff_mask(A, B)
    m[ignore > 0] = 0
    frac = float((m > 0).mean())
    dx = dy = 0.0
    if frac > 0.002:
        flow = cv2.calcOpticalFlowFarneback(A, B, None, 0.5, 3, 21, 3, 5, 1.2, 0)
        pts = flow[m > 0]
        if len(pts):
            dx, dy = (float(v) for v in np.median(pts, axis=0))
    return frac, dx, dy, m


def direction(dx: float, dy: float) -> str:
    if math.hypot(dx, dy) < 2.0:
        return "none"
    if abs(dx) > 2 * abs(dy):
        return "horizontal"
    if abs(dy) > 2 * abs(dx):
        return "vertical"
    return "mixed"


def label(img, text: str):
    out = img.copy()
    cv2.putText(out, text, (12, 36), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 0), 4, cv2.LINE_AA)
    cv2.putText(out, text, (12, 36), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (60, 220, 60), 2, cv2.LINE_AA)
    return out


def main() -> int:
    global LOG_FH
    ap = argparse.ArgumentParser()
    ap.add_argument("--axis", default="both", choices=["pan", "tilt", "both"])
    ap.add_argument("--cam", type=int, default=int(os.environ.get("CAM_INDEX", "-1")))
    ap.add_argument("--list", action="store_true", help="探测摄像头 0..3 并存缩略图")
    ap.add_argument("--out", default=os.path.join(HW, ".run", "cam"))
    ap.add_argument("--log", default="")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    if args.log:
        LOG_FH = open(args.log, "w", encoding="utf-8")

    if args.list:
        for i in range(4):
            cap = cv2.VideoCapture(i, cv2.CAP_AVFOUNDATION)
            ok, f = (cap.read() if cap.isOpened() else (False, None))
            if ok:
                cv2.imwrite(os.path.join(args.out, f"cam_list_{i}.png"), f)
                say(f"摄像头 {i}: {f.shape[1]}x{f.shape[0]} → cam_list_{i}.png")
            cap.release()
        say("DONE")
        return 0

    say("[1/6] 开摄像头(第一次会弹权限,请允许)")
    cap = None
    for idx in ([args.cam] if args.cam >= 0 else [0, 1, 2, 3]):
        cap = open_cam(idx, retry_sec=30.0 if args.cam >= 0 or idx == 0 else 2.0)
        if cap:
            say(f"    用摄像头 {idx}")
            break
    if cap is None:
        return fail("摄像头打不开(权限被拒?索引不对?用 --list 看;系统设置 → 隐私 → 摄像头)")
    warm_up(cap, args.out)
    say("    预览已存 cam_preview.png,确认小机在画面里")

    say("[2/6] 连桥接并 ping 固件")
    try:
        br = Bridge(BRIDGE_URL)
    except Exception as e:
        cap.release()
        return fail(f"连不上桥接 {BRIDGE_URL}(先 bash hardware/run_robot.sh):{e}")
    br.send({"cmd": "ping"})
    if br.wait_evt("pong", 2.0) is None:
        cap.release()
        return fail("固件没在跑(没 pong;可能停在 REPL,按小机 RST 或「刷入固件与语音」)")

    say("[3/6] 云台归中,抓基线(学出屏幕眨眼区域)")
    br.gimbal(pan=90, tilt=90)
    time.sleep(0.8)
    frames = []
    t0 = time.time()
    while time.time() - t0 < 3.0:
        f = grab(cap)
        if f is not None:
            frames.append(prep(f))
        time.sleep(0.25)
    if len(frames) < 4:
        cap.release()
        return fail("摄像头抓不到帧")
    masks = [diff_mask(frames[i], frames[i + 1]) for i in range(len(frames) - 1)]
    ignore = cv2.dilate(np.bitwise_or.reduce(masks), np.ones((9, 9), np.uint8))
    idle = max(float(((m > 0) & (ignore == 0)).mean()) for m in masks)
    ignore_frac = float((ignore > 0).mean())
    say(f"    基线噪声 {idle * 100:.2f}%(忽略区 {ignore_frac * 100:.1f}%)")
    if ignore_frac > 0.2:
        say("    注意:画面里大片区域在动(有人/有东西晃),判定会不准 —— 让画面静止,只留小机在镜头前")

    results = {}
    shots = {}
    axes = ["pan", "tilt"] if args.axis == "both" else [args.axis]
    step = 4
    for axis in axes:
        angles = PAN if axis == "pan" else TILT
        say(f"[{step}/6] {axis}:{angles['A']} → 抓 A,{angles['B']} → 抓 B,归中")
        step += 1
        acked = br.gimbal(**{axis: angles["A"]})
        time.sleep(0.9)
        a = grab(cap)
        acked = br.gimbal(**{axis: angles["B"]}) and acked
        time.sleep(0.9)
        b = grab(cap)
        br.gimbal(**{axis: angles["C"]})
        if a is None or b is None:
            cap.release()
            return fail("抓帧失败")
        frac, dx, dy, m = measure(a, b, ignore)
        moved = frac > max(0.02, 5 * idle)
        want = "horizontal" if axis == "pan" else "vertical"
        got = direction(dx, dy)
        verdict = "动了" if moved else "没动"
        note = "" if not moved or got == want else f"(方向 {got},期望 {want},摄像头可能歪着看)"
        say(f"    {axis}: 变化 {frac * 100:.2f}% 光流 dx={dx:.1f} dy={dy:.1f} → {verdict}{note} ack={'有' if acked else '无'}")
        results[axis] = {"moved": bool(moved), "frac": frac, "dx": dx, "dy": dy, "dir": got, "ack": bool(acked)}
        shots[axis] = (label(a, f"{axis} {angles['A']}"), label(b, f"{axis} {angles['B']}  {verdict} {frac * 100:.1f}%"))
        cv2.imwrite(os.path.join(args.out, f"cam_{axis}_A.png"), a)
        cv2.imwrite(os.path.join(args.out, f"cam_{axis}_B.png"), b)
    br.close()
    cap.release()

    say("[6/6] 拼接 cam_report.png")
    rows = [np.hstack(shots[ax]) for ax in axes]
    w = min(r.shape[1] for r in rows)
    report = np.vstack([r[:, :w] for r in rows])
    scale = 1600 / report.shape[1] if report.shape[1] > 1600 else 1.0
    if scale < 1.0:
        report = cv2.resize(report, None, fx=scale, fy=scale)
    cv2.imwrite(os.path.join(args.out, "cam_report.png"), report)
    say("RESULT " + json.dumps(results, ensure_ascii=False))
    bad = [ax for ax in axes if not results[ax]["moved"]]
    if bad:
        return fail(f"{'、'.join(bad)} 轴没动(看 cam_report.png;ack 有=固件写了 PWM 舵机没跟 → 查供电/接线)")
    say("DONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
