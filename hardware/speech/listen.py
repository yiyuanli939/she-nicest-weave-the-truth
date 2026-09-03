#!/usr/bin/env python3
"""小机语音助手:电脑麦克风离线识别「请指导我」/ "please guide me" → 经桥接 WebSocket 转给游戏。

    hardware/.venv/bin/python hardware/speech/listen.py [--lang zh|en|all] [--check-only]
    (一般由 hardware/run_robot.sh 拉起;默认 all = 有模型的语言都听)

- 识别用 Vosk 小模型(中文 model/、英文 model_en/,先跑 get_model.sh),每种语言一个识别器喂同一段音频,
  语法约束只认「请 指导 我」「请 帮帮 我」/ "please guide me" "please help me" "help me" + [unk],
  所以基本只会在玩家真说这几句时命中;命中后 3 s 内不重复。游戏切语言不用重启助手(两边一直都在听)。
- 事件经桥接广播给游戏(bridge.js 把带 evt 的客户端消息转发给其它客户端,不下串口):
    {"evt":"speech_ready","langs":["zh","en"]}   启动并连上桥接
    {"evt":"speech_alive","langs":[...]}         每 5 s 心跳(维护面板显示「语音助手在线(zh, en)」)
    {"evt":"speech","text":"请指导我","lang":"zh"} / {"evt":"speech","text":"please guide me","lang":"en"}
- 桥接不在就每 2 s 重连;麦克风权限归拉起本进程的应用(Godot 或终端),第一次要点「允许」。
- --check-only:只加载模型、打印语法,不开麦克风,退出码 0 = 就绪(至少一种语言有模型)。
"""
import json
import os
import queue
import sys
import time

BRIDGE_URL = os.environ.get("BRIDGE_URL", "ws://127.0.0.1:9800")
HERE = os.path.dirname(os.path.abspath(__file__))
LANGS = {
    "zh": {
        "dir": "model",
        "phrases": [["请", "指导", "我"], ["请", "帮帮", "我"]],   # 词表里没有的多字词自动退成单字
        "keys": ["请指导我", "请帮帮我"],                          # 只认完整句
        "text": "请指导我",
    },
    "en": {
        "dir": "model_en",
        "phrases": [["please", "guide", "me"], ["please", "help", "me"], ["help", "me"]],
        "keys": ["pleaseguideme", "pleasehelpme", "helpme"],
        "text": "please guide me",
    },
}
MIN_CONF = 0.6
DEDUP_SEC = 3.0
ALIVE_SEC = 5.0
RECONNECT_SEC = 2.0


def log(*a):
    print("[speech]", *a, flush=True)


def model_dir(lang: str) -> str:
    return os.path.join(HERE, LANGS[lang]["dir"])


def has_model(lang: str) -> bool:
    return os.path.isfile(os.path.join(model_dir(lang), "graph", "HCLr.fst"))


def build_grammar(model, lang: str) -> str:
    """语法里的词必须在模型词表里(vosk_model_find_word):多字词不成词就退成单字。"""
    def known(w: str) -> bool:
        return model.vosk_model_find_word(w) >= 0

    phrases = []
    for tokens in LANGS[lang]["phrases"]:
        toks = []
        for t in tokens:
            if known(t) or len(t) == 1:
                toks.append(t)
            else:
                toks.extend(list(t))
        missing = [t for t in toks if not known(t)]
        if missing:
            log(lang, "词表缺", missing, "—— 这句可能识别不到")
        phrases.append(" ".join(toks))
    log(f"语法[{lang}]:", " | ".join(phrases))
    return json.dumps(phrases + ["[unk]"], ensure_ascii=False)


def compact_text(text: str, lang: str) -> str:
    """Vosk 输出词间有空格,先去掉;英文再转小写。"""
    s = text.replace(" ", "").replace("　", "")
    return s.lower() if lang == "en" else s


def hit(res: dict, lang: str):
    """一句最终结果是否命中该语言的唤醒短语;返回 (命中, 置信度, 紧凑文本)。"""
    compact = compact_text(res.get("text", ""), lang)
    if not compact or not any(k in compact for k in LANGS[lang]["keys"]):
        return False, 0.0, compact
    confs = [w.get("conf", 1.0) for w in res.get("result", []) if w.get("word") != "[unk]"]
    conf = min(confs) if confs else 0.0
    return conf >= MIN_CONF, conf, compact


class Bridge:
    """极简 ws 客户端,断了静默重连。"""

    def __init__(self, url: str, langs):
        self.url = url
        self.langs = list(langs)
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
            self.send({"evt": "speech_ready", "langs": self.langs})
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


def parse_args(argv):
    lang = "all"
    check = False
    i = 0
    while i < len(argv):
        if argv[i] == "--lang" and i + 1 < len(argv):
            lang = argv[i + 1]
            i += 1
        elif argv[i] == "--check-only":
            check = True
        i += 1
    if lang not in ("zh", "en", "all"):
        log("用法: listen.py [--lang zh|en|all] [--check-only]")
        sys.exit(2)
    return lang, check


def main(argv) -> int:
    want, check = parse_args(argv)
    langs = [l for l in LANGS if (want == "all" or l == want) and has_model(l)]
    if not langs:
        log("缺模型:先跑 hardware/speech/get_model.sh(zh → model/,en → model_en/)")
        return 1
    for l in LANGS:
        if l not in langs and (want == "all" or l == want):
            log(f"没有 {l} 模型({LANGS[l]['dir']}),这门语言不听")
    from vosk import KaldiRecognizer, Model, SetLogLevel
    SetLogLevel(-1)
    models = {l: Model(model_dir(l)) for l in langs}
    if check:
        for l in langs:
            build_grammar(models[l], l)
        log("就绪(--check-only):", ", ".join(langs))
        return 0
    import sounddevice as sd
    dev = sd.query_devices(None, "input")
    rate = int(dev["default_samplerate"])
    recs = {}
    for l in langs:
        rec = KaldiRecognizer(models[l], rate, build_grammar(models[l], l))
        rec.SetWords(True)
        recs[l] = rec
    q: "queue.Queue[bytes]" = queue.Queue()

    def cb(indata, _frames, _t, status):
        if status:
            log("音频状态:", status)
        q.put(bytes(indata))

    bridge = Bridge(BRIDGE_URL, langs)
    last_hit = 0.0
    last_alive = 0.0
    with sd.RawInputStream(samplerate=rate, blocksize=4000, dtype="int16", channels=1, callback=cb):
        log(f"监听中({', '.join(langs)}):{dev['name']} @{rate} Hz,说「请指导我」或 \"please guide me\"")
        while True:
            now = time.time()
            if bridge.poll(now) and now - last_alive > ALIVE_SEC:
                bridge.send({"evt": "speech_alive", "langs": langs})
                last_alive = now
            try:
                data = q.get(timeout=0.5)
            except queue.Empty:
                continue
            for l, rec in recs.items():
                if not rec.AcceptWaveform(data):
                    continue   # 只看一句说完的最终结果,部分结果太容易被语法硬凑出来
                ok, conf, compact = hit(json.loads(rec.Result()), l)
                if not compact:
                    continue
                if not ok:
                    if conf > 0.0:
                        log(f"疑似[{l}]({conf:.2f}):", compact)
                    continue
                if now - last_hit > DEDUP_SEC:
                    last_hit = now
                    log(f"命中[{l}]({conf:.2f}):", compact)
                    bridge.send({"evt": "speech", "text": LANGS[l]["text"], "lang": l})


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        pass
