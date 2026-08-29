# She Nicest 小机固件(MicroPython, ESP32-S3N16R8-EMOJI 板)
# 协议:USB CDC 上的行分隔 JSON(与 hardware/bridge 和游戏 Robot autoload 对应)
#   下行 {"cmd":"emote","name":"happy|sad|confused|think|glitch|sleep|idle"}
#        {"cmd":"anim","name":"celebrate(俯仰连点头)|panic|nod|shake|look_pc"}
#        {"cmd":"say","name":"greet|win|encourage|hint|calm|glitch1..3"}   播 /sounds/<name>.wav
#        {"cmd":"gimbal","pan":90,"tilt":90,"ms":300}
#        {"cmd":"text","s":"..."}   {"cmd":"ping"}
#   上行 {"evt":"ready"...} {"evt":"pong"} {"evt":"button","name":"boot"}
# 引脚来自 deskemoji 板配置:OLED I2C SDA=41 SCL=42;舵机 水平=11 垂直=12;
# 功放 MAX98357A I2S BCLK=15 LRC=16 DIN=7(16kHz 16bit 单声道 WAV)。
import json
import math
import select
import sys
import time
import random
from machine import Pin, SoftI2C, PWM, I2S
import framebuf
from paj7620 import PAJ7620

# ---- SSD1306 128x64 I2C 最小驱动(内嵌,免联网装库) ----
class SSD1306(framebuf.FrameBuffer):
    # I2C 偶发 ENODEV(曾把整个固件打回 REPL):写失败只标记 ok=False,5 s 后重试初始化,云台/语音照跑
    INIT = (
        0xAE, 0x20, 0x00, 0x40, 0xA1, 0xA8, 63, 0xC8, 0xD3, 0x00,
        0xDA, 0x12, 0xD5, 0x80, 0xD9, 0xF1, 0xDB, 0x30, 0x81, 0xFF,
        0xA4, 0xA6, 0x8D, 0x14, 0xAF,
    )

    def __init__(self, i2c, addr=0x3C, w=128, h=64):
        self.i2c, self.addr, self.w, self.h = i2c, addr, w, h
        self.buf = bytearray(w * h // 8)
        super().__init__(self.buf, w, h, framebuf.MONO_VLSB)
        self.ok = False
        self.retry_at = 0
        self.init()

    def init(self):
        try:
            for cmd in self.INIT:
                self.i2c.writeto(self.addr, bytes((0x80, cmd)))
            self.ok = True
        except OSError:
            self._fail()

    def _fail(self):
        self.ok = False
        self.retry_at = time.ticks_add(time.ticks_ms(), 5000)

    def _cmd(self, c):
        self.i2c.writeto(self.addr, bytes((0x80, c)))

    def show(self):
        if not self.ok:
            if time.ticks_diff(time.ticks_ms(), self.retry_at) > 0:
                self.init()
            if not self.ok:
                return
        try:
            for c in (0x21, 0, self.w - 1, 0x22, 0, self.h // 8 - 1):
                self._cmd(c)
            self.i2c.writeto(self.addr, b"\x40" + self.buf)
        except OSError:
            self._fail()


# ---- 云台舵机 ----
class Servo:
    def __init__(self, pin, lo, hi, center):
        self.pwm = PWM(Pin(pin), freq=50)
        self.lo, self.hi = lo, hi
        self.angle = center
        self.goto(center)

    def goto(self, deg):
        deg = max(self.lo, min(self.hi, deg))
        self.angle = deg
        us = 500 + (2500 - 500) * deg / 180
        self.pwm.duty_u16(int(us * 65535 // 20000))


i2c = SoftI2C(sda=Pin(41), scl=Pin(42), freq=400000)
oled = SSD1306(i2c)
pan = Servo(11, 50, 130, 90)    # 水平:中心±40
tilt = Servo(12, 70, 110, 90)   # 垂直:中心±20
boot_btn = Pin(0, Pin.IN, Pin.PULL_UP)
# I2S 初始化容错:软复位后外设可能未释放,失败则静音运行(表情/云台不受影响)
try:
    audio = I2S(0, sck=Pin(15), ws=Pin(16), sd=Pin(7),
                mode=I2S.TX, bits=16, format=I2S.MONO, rate=16000, ibuf=16384)
except (OSError, ValueError):
    audio = None
_voice = None                    # 正在播的 WAV 文件对象
gest = PAJ7620(i2c)              # 手势传感器(共用 I2C;不在也能跑,校准退化为按键)

# "看电脑"方向:给提示时先扭头望向屏幕再转回来。
# 出厂默认值;跑一次校准({"cmd":"cal_look"} 扫描锁定,或 {"cmd":"cal_set"} 直接取
# 当前云台角)后存 /look_cfg.json,开机自动加载。
LOOK_PC = [122, 102]
try:
    with open("/look_cfg.json") as _f:
        _c = json.load(_f)
        LOOK_PC = [int(_c["pan"]), int(_c["tilt"])]
except (OSError, ValueError, KeyError):
    pass

emote = "idle"
cal_t0 = None        # 校准模式:扫描起始 ticks_ms;None=不在校准
text_until = 0
blink_at = time.ticks_ms() + 2500
blinking = False
anim = None          # (name, start_ms)
anim_base = (90, 90)


def send(d):
    sys.stdout.write(json.dumps(d) + "\n")


# ---- 表情脸(程序化,128x64) ----
# talk_open:None=按表情画嘴;True/False=说话口型(张/合),与语音播放联动
def draw_face(name, blink, talk_open=None):
    o = oled
    o.fill(0)
    ex_l, ex_r, ey = 38, 90, 22          # 双眼中心
    if name == "sleep":
        o.hline(ex_l - 10, ey, 20, 1)
        o.hline(ex_r - 10, ey, 20, 1)
        o.text("z Z", 100, 4, 1)
        o.hline(54, 48, 20, 1)
    elif name == "glitch":
        for _ in range(14):
            x = random.getrandbits(7)
            y = 8 + random.getrandbits(5)
            o.fill_rect(x, y, 10, 2, 1)
        o.rect(ex_l - 8, ey - 8, 16, 16, 1)
        o.line(ex_r - 8, ey - 8, ex_r + 8, ey + 8, 1)
        o.line(ex_r + 8, ey - 8, ex_r - 8, ey + 8, 1)
        o.hline(48, 50, 32, 1)
    else:
        if blink:
            o.hline(ex_l - 9, ey, 18, 1)
            o.hline(ex_r - 9, ey, 18, 1)
        else:
            o.fill_rect(ex_l - 7, ey - 9, 14, 18, 1)
            o.fill_rect(ex_r - 7, ey - 9, 14, 18, 1)
            if name == "confused":
                o.fill_rect(ex_r - 7, ey - 9, 14, 6, 0)   # 右眼眯起
            if name == "think":
                o.fill_rect(ex_l - 7, ey + 4, 14, 5, 0)
                o.fill_rect(ex_r - 7, ey + 4, 14, 5, 0)   # 眼神上瞟
        if talk_open is not None:                          # 说话口型盖过表情嘴
            if talk_open:
                o.fill_rect(55, 43, 18, 12, 1)
                o.fill_rect(58, 46, 12, 6, 0)
            else:
                o.fill_rect(55, 48, 18, 3, 1)
        elif name == "happy":
            for i in range(20):                            # 上弯嘴
                o.pixel(54 + i, 50 - (i * (19 - i)) // 14, 1)
        elif name == "sad":
            for i in range(20):
                o.pixel(54 + i, 44 + (i * (19 - i)) // 14, 1)
        elif name == "confused":
            o.hline(52, 48, 12, 1)
            o.hline(64, 51, 12, 1)
            o.text("?", 108, 12, 1)
        elif name == "think":
            o.hline(56, 49, 14, 1)
            o.text("...", 100, 40, 1)
        else:  # idle
            o.hline(56, 49, 16, 1)
    o.show()


# ---- 语音(分块喂 I2S,不长阻塞主循环) ----
def say(name):
    global _voice
    if audio is None:
        return
    if _voice:
        _voice.close()
        _voice = None
    try:
        f = open("/sounds/%s.wav" % name, "rb")
        hdr = f.read(256)
        i = hdr.find(b"data")
        f.seek(i + 8 if i >= 0 else 44)
        _voice = f
    except OSError:
        send({"evt": "err", "msg": "no sound: " + str(name)})


def tick_voice():
    global _voice, audio
    if _voice is None:
        return
    chunk = _voice.read(2048)
    if chunk:
        try:
            audio.write(chunk)
        except OSError:          # 功放/I2S 掉了:静音继续跑,别崩
            _voice.close()
            _voice = None
            audio = None
    else:
        _voice.close()
        _voice = None


def draw_text(s):
    oled.fill(0)
    for i, chunk in enumerate([s[j:j + 16] for j in range(0, len(s), 16)][:6]):
        oled.text(chunk, 0, 4 + i * 10, 1)
    oled.show()


# ---- 动画状态机(非阻塞,主循环里 tick) ----
def tick_anim(now):
    global anim, emote
    if anim is None:
        return
    name, t0 = anim
    t = time.ticks_diff(now, t0)
    if name == "celebrate":
        # 庆祝 = 上面那根轴(俯仰)连续点头,不左右摇
        if t > 2600:
            anim = None
        else:
            tilt.goto(90 + (16 if (t // 260) % 2 else -6))
    elif name == "panic":
        if t > 3000:
            anim = None
        elif t % 90 < 20:
            pan.goto(50 + random.getrandbits(6))
            tilt.goto(70 + random.getrandbits(5))
    elif name == "nod":
        if t > 1200:
            anim = None
        else:
            tilt.goto(90 + (14 if (t // 300) % 2 else -6))
    elif name == "shake":
        if t > 1400:
            anim = None
        else:
            pan.goto(90 + (22 if (t // 250) % 2 else -22))
    elif name == "look_pc":
        # 装作看电脑:400ms 转过去 → 停 1.6s(读屏时轻点头)→ 600ms 转回来
        bx, by = anim_base
        px, py = LOOK_PC
        if t < 400:
            k = t / 400
            pan.goto(int(bx + (px - bx) * k))
            tilt.goto(int(by + (py - by) * k))
        elif t < 2000:
            pan.goto(px)
            tilt.goto(py + (3 if (t // 400) % 2 else -3))
        elif t < 2600:
            k = (t - 2000) / 600
            pan.goto(int(px + (bx - px) * k))
            tilt.goto(int(py + (by - py) * k))
        else:
            anim = None
    if anim is None:
        pan.goto(anim_base[0])
        tilt.goto(anim_base[1])


# ---- "看电脑"方向校准 ----
# cal_look:云台左右扫描,玩家在小机正对电脑屏幕的时刻朝它挥手(PAJ7620 检测)
# 或按 BOOT 键 → 锁定该方向并写入 /look_cfg.json。30 秒无锁定超时。
def save_look():
    with open("/look_cfg.json", "w") as f:
        json.dump({"pan": LOOK_PC[0], "tilt": LOOK_PC[1]}, f)


def tick_cal(now):
    global cal_t0, anim, anim_base, text_until
    if cal_t0 is None:
        return
    t = time.ticks_diff(now, cal_t0)
    if t > 30000:
        cal_t0 = None
        text_until = 0
        send({"evt": "cal_timeout"})
        pan.goto(90)
        tilt.goto(90)
        return
    ph = (t % 6400) / 6400          # 三角波 50→130→50,周期 6.4s
    ang = 50 + 160 * ph if ph < 0.5 else 130 - 160 * (ph - 0.5)
    pan.goto(int(ang))
    tilt.goto(96)
    if gest.hand() or boot_btn.value() == 0:
        LOOK_PC[0] = pan.angle
        LOOK_PC[1] = 100
        save_look()
        cal_t0 = None
        text_until = 0
        send({"evt": "cal_done", "pan": LOOK_PC[0], "tilt": LOOK_PC[1]})
        anim = ("nod", now)          # 点头确认
        anim_base = (pan.angle, 90)


def handle(line):
    global emote, text_until, anim, anim_base, cal_t0
    try:
        d = json.loads(line)
    except ValueError:
        return
    cmd = d.get("cmd")
    if cmd == "ping":
        send({"evt": "pong"})
    elif cmd == "emote":
        emote = d.get("name", "idle")
        text_until = 0
    elif cmd == "anim":
        anim = (d.get("name", "nod"), time.ticks_ms())
        anim_base = (pan.angle, tilt.angle)
    elif cmd == "say":
        say(d.get("name", ""))
    elif cmd == "cal_look":
        cal_t0 = time.ticks_ms()
        draw_text("CAL: WAVE WHEN I FACE THE SCREEN")
        text_until = time.ticks_ms() + 30000
    elif cmd == "cal_set":       # 以当前云台角为"屏幕方向"(游戏里手动微调后保存)
        LOOK_PC[0] = pan.angle
        LOOK_PC[1] = tilt.angle
        save_look()
        send({"evt": "cal_done", "pan": LOOK_PC[0], "tilt": LOOK_PC[1]})
    elif cmd == "gimbal":
        pan.goto(int(d.get("pan", pan.angle)))
        tilt.goto(int(d.get("tilt", tilt.angle)))
        send({"evt": "gimbal", "pan": pan.angle, "tilt": tilt.angle})   # ack:确认执行到 PWM 写入
    elif cmd == "text":
        draw_text(str(d.get("s", "")))
        text_until = time.ticks_ms() + 3000


def main():
    global blink_at, blinking, text_until
    poller = select.poll()
    poller.register(sys.stdin, select.POLLIN)
    buf = ""
    last_face = None
    btn_was = 1
    send({"evt": "ready", "board": "esp32-s3n16r8-emoji", "fw": "she-nicest-bot 1.1",
          "oled": oled.ok, "audio": audio is not None})
    while True:
        while poller.poll(0):
            ch = sys.stdin.read(1)
            if ch in ("\n", "\r"):
                if buf:
                    handle(buf)
                    buf = ""
            else:
                buf += ch
                if len(buf) > 512:
                    buf = ""
        now = time.ticks_ms()
        b = boot_btn.value()
        if b == 0 and btn_was == 1 and cal_t0 is None:
            send({"evt": "button", "name": "boot"})
        btn_was = b
        tick_anim(now)
        tick_voice()
        tick_cal(now)
        if text_until and time.ticks_diff(now, text_until) > 0:
            text_until = 0
        if cal_t0 is None and not text_until:
            if time.ticks_diff(now, blink_at) > 0:
                blinking = not blinking
                blink_at = now + (140 if blinking else 1800 + random.getrandbits(11))
            talk = ((now // 160) % 2 == 0) if _voice else None
            face = (emote, blinking, anim[0] if anim else "", talk)
            if face != last_face or emote == "glitch":
                draw_face("glitch" if anim and anim[0] == "panic" else emote, blinking, talk)
                last_face = face
        time.sleep_ms(15)


try:
    main()
except Exception as e:          # 崩溃可见:上报后 1.5 s 自动复位(不再落回 REPL 变成"没在跑");mpremote 仍可 Ctrl-C 打断
    sys.print_exception(e)
    try:
        send({"evt": "err", "msg": "crash: " + repr(e)})
    except Exception:
        pass
    time.sleep_ms(1500)
    import machine
    machine.soft_reset()        # 软复位重跑 main.py;硬复位偶发让 USB 僵死
