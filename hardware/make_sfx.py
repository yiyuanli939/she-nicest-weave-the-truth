#!/usr/bin/env python3
"""程序合成小机「坏掉」音效(纯噪音/蜂鸣,不含任何台词):hardware/.venv/bin/python hardware/make_sfx.py
→ hardware/firmware/sounds/glitch1.wav / glitch2.wav / glitch3.wav(16 kHz / 16 bit 单声道,固定种子可复现)。
第三章故障态与 panic cue 随机挑一段播;改完用「小机维护」→「刷入固件与语音」送进小机。"""
import os
import wave

import numpy as np

RATE = 16000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "firmware", "sounds")
PEAK = 0.45   # 坏掉音效比台词(0.9)明显轻一些(用户要求"稍微小一点")


def t(sec: float) -> np.ndarray:
    return np.arange(int(sec * RATE)) / RATE


def square(freq: float, sec: float) -> np.ndarray:
    return np.sign(np.sin(2 * np.pi * freq * t(sec)))


def saw(freq: float, sec: float) -> np.ndarray:
    x = t(sec) * freq
    return 2 * (x - np.floor(x + 0.5))


def env(n: int, attack: float = 0.004, release: float = 0.02) -> np.ndarray:
    e = np.ones(n)
    a = max(1, int(attack * RATE)); r = max(1, int(release * RATE))
    e[:a] = np.linspace(0, 1, a); e[-r:] = np.linspace(1, 0, r)
    return e


def bitcrush(x: np.ndarray, bits: int = 5, hold: int = 3) -> np.ndarray:
    q = 2 ** (bits - 1)
    y = np.round(x * q) / q
    return np.repeat(y[::hold], hold)[: len(x)]


def glitch1(rng) -> np.ndarray:
    """断续的随机蜂鸣 + 杂音爆点:像坏掉的电路板。"""
    out = np.zeros(int(1.5 * RATE))
    pos = 0
    while pos < len(out) - RATE // 10:
        dur = rng.uniform(0.04, 0.13)
        freq = rng.choice([180, 330, 620, 900, 1500, 2400]) * rng.uniform(0.9, 1.1)
        seg = square(freq, dur) * env(int(dur * RATE)) * rng.uniform(0.4, 0.9)
        if rng.random() < 0.35:
            seg = rng.uniform(-1, 1, len(seg)) * env(len(seg)) * 0.6   # 一段杂音
        end = min(len(out), pos + len(seg))
        out[pos:end] += seg[: end - pos]
        pos = end + int(rng.uniform(0.01, 0.08) * RATE)
    return bitcrush(out, 5, 3)


def glitch2(rng) -> np.ndarray:
    """掉电音:音高一路下滑,同时被 18 Hz 的开关门抖成一段段,尾巴带静电。"""
    sec = 1.6
    tt = t(sec)
    freq = 1400 * np.exp(-2.2 * tt) + 60
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    tone = np.sign(np.sin(phase)) * 0.7 + saw(float(freq.mean()), sec) * 0.15
    gate = (np.sin(2 * np.pi * 18 * tt) > -0.2).astype(float)
    static = rng.uniform(-1, 1, len(tt)) * np.clip((tt - 0.9) / 0.7, 0, 1) * 0.5
    return bitcrush((tone * gate * np.exp(-1.2 * tt) + static) * env(len(tt)), 6, 2)


def glitch3(rng) -> np.ndarray:
    """粗糙低频嗡鸣 + 噼啪爆音:像接触不良。"""
    sec = 1.3
    tt = t(sec)
    buzz = saw(55, sec) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 7 * tt)))
    buzz *= 0.5 + 0.5 * (rng.uniform(0, 1, len(tt)) > 0.3)   # 断续
    pops = np.zeros(len(tt))
    for _ in range(18):
        i = int(rng.uniform(0, len(tt) - 200))
        pops[i:i + 120] += rng.uniform(-1, 1, 120) * np.linspace(1, 0, 120) * rng.uniform(0.5, 1.0)
    return bitcrush((buzz * 0.6 + pops) * env(len(tt), release=0.15), 5, 2)


def write(name: str, x: np.ndarray) -> None:
    x = x / (np.max(np.abs(x)) or 1.0) * PEAK
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(data.tobytes())
    print("写出", name + ".wav", f"{len(data) / RATE:.2f}s")


if __name__ == "__main__":
    rng = np.random.default_rng(20260829)
    write("glitch1", glitch1(rng))
    write("glitch2", glitch2(rng))
    write("glitch3", glitch3(rng))
