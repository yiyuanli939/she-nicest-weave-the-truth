#!/usr/bin/env python3
"""小机语音助手:电脑麦克风离线识别「请指导我」→ 经桥接 WebSocket 转给游戏。

    hardware/.venv/bin/python hardware/speech/listen.py      (一般由 hardware/run_robot.sh 拉起)

- 识别用 Vosk 中文小模型(hardware/speech/model,先跑 get_model.sh),语法约束只认「请 指导 我」「请 帮帮 我」+ [unk],
  所以基本只会在玩家真说这两句时命中;命中后 3 s 内不重复。
- 事件经桥接广播给游戏(bridge.js 把带 evt 的客户端消息转发给其它客户端,不下串口):
    {"evt":"speech_ready"}          启动并连上桥接
    {"evt":"speech_alive"}          每 5 s 心跳(维护面板显示「语音助手在线」)
    {"evt":"speech","text":"请指导我"}
- 桥接不在就每 2 s 重连;麦克风权限归拉起本进程的应用(Godot 或终端),第一次要点「允许」。
"""
import json
import os
import queue
import sys
import time

import sounddevice as sd
from vosk import KaldiRecognizer, Model, SetLogLevel

BRIDGE_URL = os.environ.get("BRIDGE_URL", "ws://127.0.0.1:9800")
MODEL_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "model")
PHRASE = "请指导我"
PHRASES = [["请", "指导", "我"], ["请", "帮帮", "我"]]   # 词表里没有的多字词自动退成单字
KEYS = ["请指导我", "请帮帮我"]   # 只认完整句;语法约束下噪音会被硬凑成短语,所以再看词置信度
MIN_CONF = 0.6
DEDUP_SEC = 3.0
ALIVE_SEC = 5.0
RECONNECT_SEC = 2.0


def log(*a):
    print("[speech]", *a, flush=True)


def build_grammar(model: Model) -> str:
    """语法里的词必须在模型词表里(vosk_model_find_word):多字词不成词就退成单字。"""
    def known(w: str) -> bool:
        return model.vosk_model_find_word(w) >= 0

    phrases = []
    for tokens in PHRASES:
        toks = []
        for t in tokens:
            if known(t) or len(t) == 1:
                toks.append(t)
            else:
                toks.extend(list(t))
        missing = [t for t in toks if not known(t)]
        if missing:
            log("词表缺", missing, "—— 这句可能识别不到")
        phrases.append(" ".join(toks))
    log("语法:", " | ".join(phrases))
    return json.dumps(phrases + ["[unk]"], ensure_ascii=False)


class Bridge:
    """极简 ws 客户端,断了静默重连。"""

    def __init__(self, url: str):
        self.url = url
        self.ws = None
        self.last_try = 0.0

    def poll(self, now: float) -> bool:
        if self.ws is not None:
            return True
        if now - self.last_try < RECONNECT_SEC:
            return False
        self.last_try = now
        try:
            from websockets.sync.client import connect
            try:
                self.ws = connect(self.url, open_timeout=1, legacy=True)
            except TypeError:
                self.ws = connect(self.url, open_timeout=1)
            log("已连上桥接", self.url)
            self.send({"evt": "speech_ready"})
            return True
        except Exception:
            self.ws = None
            return False

    def send(self, obj: dict) -> None:
        if self.ws is None:
            return
        try:
            self.ws.send(json.dumps(obj, ensure_ascii=False))
        except Exception as e:
            log("桥接断开:", e)
            try:
                self.ws.close()
            except Exception:
                pass
            self.ws = None


def main() -> int:
    if not os.path.isfile(os.path.join(MODEL_DIR, "graph", "HCLr.fst")):
        log("缺模型:先跑 hardware/speech/get_model.sh")
        return 1
    SetLogLevel(-1)
    model = Model(MODEL_DIR)
    dev = sd.query_devices(None, "input")
    rate = int(dev["default_samplerate"])
    rec = KaldiRecognizer(model, rate, build_grammar(model))
    rec.SetWords(True)
    q: "queue.Queue[bytes]" = queue.Queue()

    def cb(indata, _frames, _t, status):
        if status:
            log("音频状态:", status)
        q.put(bytes(indata))

    bridge = Bridge(BRIDGE_URL)
    last_hit = 0.0
    last_alive = 0.0
    with sd.RawInputStream(samplerate=rate, blocksize=4000, dtype="int16", channels=1, callback=cb):
        log(f"监听中:{dev['name']} @{rate} Hz,说「请指导我」或「请帮帮我」")
        while True:
            now = time.time()
            if bridge.poll(now) and now - last_alive > ALIVE_SEC:
                bridge.send({"evt": "speech_alive"})
                last_alive = now
            try:
                data = q.get(timeout=0.5)
            except queue.Empty:
                continue
            if not rec.AcceptWaveform(data):
                continue   # 只看一句说完的最终结果,部分结果太容易被语法硬凑出来
            res = json.loads(rec.Result())
            text = res.get("text", "")
            compact = text.replace(" ", "")
            if not compact or not any(k in compact for k in KEYS):
                continue
            confs = [w.get("conf", 1.0) for w in res.get("result", []) if w.get("word") != "[unk]"]
            conf = min(confs) if confs else 0.0
            if conf < MIN_CONF:
                log(f"疑似({conf:.2f}):", compact)
                continue
            if now - last_hit > DEDUP_SEC:
                last_hit = now
                log(f"命中({conf:.2f}):", compact)
                bridge.send({"evt": "speech", "text": PHRASE})


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
