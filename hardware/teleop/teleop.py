#!/usr/bin/env python3
# 手势遥操服务:Mac 摄像头 → MediaPipe(21 关键点 + DL 手势分类) → 桥接 ws://127.0.0.1:9800
#   * {"teleop": {...}}  → 桥接广播给游戏(虚拟光标:移动/捏合=左键/握拳=右键)
#   * {"cmd": gimbal/emote} → 桥接写串口(小机云台跟手 + 手势表情反应;不发语音)
# 用法:
#   python teleop.py                # 摄像头模式(首次 macOS 会弹摄像头授权)
#   python teleop.py --preview      # 带关键点预览窗口
#   python teleop.py --test         # 合成手模式:无摄像头验证全链路(8 字扫动+周期捏合/手势)
#   python teleop.py --camera 1 --duration 20
import argparse
import json
import math
import os
import sys
import time
import urllib.request

BRIDGE = os.environ.get("BRIDGE_URL", "ws://127.0.0.1:9800")
MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/gesture_recognizer/"
             "gesture_recognizer/float16/latest/gesture_recognizer.task")
MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gesture_recognizer.task")

# 手势 → 小机演出(可改;不发 say,按用户要求遥操不带语音)
GESTURE_CMDS = {
    "Thumb_Up":    [{"cmd": "emote", "name": "happy"},  {"cmd": "anim", "name": "nod"}],
    "Victory":     [{"cmd": "emote", "name": "happy"},  {"cmd": "anim", "name": "celebrate"}],
    "Closed_Fist": [{"cmd": "emote", "name": "glitch"}],
    "Open_Palm":   [{"cmd": "emote", "name": "think"}],
}
GESTURE_COOLDOWN = 2.0     # 同一手势最小间隔(秒)
PAN_RANGE = (50, 130)      # 云台角(与固件一致)
TILT_RANGE = (70, 110)
PINCH_ON, PINCH_OFF = 0.32, 0.42   # 捏合滞回阈值(拇指-食指距离 / 手掌尺度)


class Link:
    """到桥接的 WS,断线自动重连。"""

    def __init__(self, url):
        import websocket
        self._mod = websocket
        self.url = url
        self.ws = None
        self._last_try = 0.0

    def send(self, obj):
        line = json.dumps(obj)
        if self.ws is None:
            if time.time() - self._last_try < 2.0:
                return
            self._last_try = time.time()
            try:
                self.ws = self._mod.create_connection(self.url, timeout=2)
                print("[teleop] 已连桥接", self.url)
            except OSError:
                self.ws = None
                return
        try:
            self.ws.send(line)
        except OSError:
            print("[teleop] 桥接断开,重连中…")
            self.ws = None


class Sender:
    """节流后的下发:teleop 包 ~20Hz;gimbal 变化≥2°且≥100ms;手势 2s 冷却。"""

    def __init__(self, link):
        self.link = link
        self._last_teleop = 0.0
        self._last_gimbal = (90, 90, 0.0)
        self._gesture_at = {}

    def hand(self, seen, x=0.5, y=0.5, pinch=False, fist=False, gesture=""):
        now = time.time()
        if now - self._last_teleop >= 0.05:
            self._last_teleop = now
            self.link.send({"teleop": {"seen": seen, "x": round(x, 4), "y": round(y, 4),
                                       "pinch": pinch, "fist": fist, "gesture": gesture}})
        if seen:
            pan = round(PAN_RANGE[1] - (PAN_RANGE[1] - PAN_RANGE[0]) * x)
            tilt = round(TILT_RANGE[0] + (TILT_RANGE[1] - TILT_RANGE[0]) * y)
            lp, lt, lat = self._last_gimbal
            if (abs(pan - lp) >= 2 or abs(tilt - lt) >= 2) and now - lat >= 0.1:
                self._last_gimbal = (pan, tilt, now)
                self.link.send({"cmd": "gimbal", "pan": pan, "tilt": tilt})
        if gesture in GESTURE_CMDS and now - self._gesture_at.get(gesture, 0) >= GESTURE_COOLDOWN:
            self._gesture_at[gesture] = now
            for c in GESTURE_CMDS[gesture]:
                self.link.send(c)

    def bye(self):
        self.link.send({"cmd": "emote", "name": "idle"})
        self.link.send({"cmd": "gimbal", "pan": 90, "tilt": 90})


def run_test(sender, duration):
    """合成手:Lissajous 扫动 + 每 4s 捏合 0.6s + 每 6s 一个 Thumb_Up。"""
    print("[teleop] --test 合成手模式,时长", duration if duration > 0 else "∞")
    t0 = time.time()
    while duration <= 0 or time.time() - t0 < duration:
        t = time.time() - t0
        x = 0.5 + 0.35 * math.sin(t * 0.9)
        y = 0.5 + 0.25 * math.sin(t * 1.7)
        pinch = (t % 4.0) < 0.6
        gesture = "Thumb_Up" if (t % 6.0) < 0.1 else ""
        sender.hand(True, x, y, pinch, False, gesture)
        time.sleep(0.05)
    sender.bye()


def ensure_model():
    if os.path.exists(MODEL_PATH):
        return
    print("[teleop] 下载手势模型…")
    urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
    print("[teleop] 模型就绪", MODEL_PATH)


def run_camera(sender, camera, preview, duration):
    import cv2
    import mediapipe as mp
    from mediapipe.tasks import python as mp_tasks
    from mediapipe.tasks.python import vision

    ensure_model()
    rec = vision.GestureRecognizer.create_from_options(vision.GestureRecognizerOptions(
        base_options=mp_tasks.BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=vision.RunningMode.VIDEO, num_hands=1))
    cap = cv2.VideoCapture(camera)
    if not cap.isOpened():
        print("[teleop] 打不开摄像头", camera, "(检查系统设置-隐私-摄像头授权)")
        sys.exit(2)
    print("[teleop] 摄像头就绪,对镜头挥手;Ctrl-C 退出")
    pinch = False
    t0 = time.time()
    ts = 0
    try:
        while duration <= 0 or time.time() - t0 < duration:
            ok, frame = cap.read()
            if not ok:
                time.sleep(0.05)
                continue
            frame = cv2.flip(frame, 1)   # 镜像:手往右光标往右
            img = mp.Image(image_format=mp.ImageFormat.SRGB,
                           data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
            ts += 33
            res = rec.recognize_for_video(img, ts)
            if res.hand_landmarks:
                lm = res.hand_landmarks[0]
                # 掌心 = 腕(0)与四指根(5/9/13/17)均值;手掌尺度 = 腕到中指根距离
                cx = sum(lm[i].x for i in (0, 5, 9, 13, 17)) / 5
                cy = sum(lm[i].y for i in (0, 5, 9, 13, 17)) / 5
                scale = math.dist((lm[0].x, lm[0].y), (lm[9].x, lm[9].y)) or 1e-3
                d = math.dist((lm[4].x, lm[4].y), (lm[8].x, lm[8].y)) / scale
                pinch = d < PINCH_ON if not pinch else d < PINCH_OFF
                gesture = ""
                if res.gestures and res.gestures[0]:
                    g = res.gestures[0][0]
                    if g.score > 0.6:
                        gesture = g.category_name
                sender.hand(True, cx, cy, pinch, gesture == "Closed_Fist", gesture)
                if preview:
                    h, w = frame.shape[:2]
                    for p in lm:
                        cv2.circle(frame, (int(p.x * w), int(p.y * h)), 3, (80, 220, 120), -1)
                    cv2.putText(frame, f"{gesture} pinch={pinch}", (10, 30),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (60, 200, 255), 2)
            else:
                pinch = False
                sender.hand(False)
            if preview:
                cv2.imshow("teleop", frame)
                if cv2.waitKey(1) & 0xFF == 27:
                    break
    except KeyboardInterrupt:
        pass
    finally:
        cap.release()
        if preview:
            cv2.destroyAllWindows()
        sender.bye()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--camera", type=int, default=0)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--test", action="store_true")
    ap.add_argument("--duration", type=float, default=0, help="秒;0=不限")
    args = ap.parse_args()
    sender = Sender(Link(BRIDGE))
    if args.test:
        run_test(sender, args.duration)
    else:
        run_camera(sender, args.camera, args.preview, args.duration)


if __name__ == "__main__":
    main()
