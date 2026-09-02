#!/usr/bin/env python3
"""现用音效统一处理(用户 2026-09-02:保证音效声音的一致性):hardware/.venv/bin/python tools/sfx_normalize.py [--crest 21]
对 game/sfx.gd CLIPS 里的每个文件(assets/sfx/<名>.ogg|.wav|.mp3)就地处理成 16 bit 单声道 44.1 kHz WAV:
起始静音(峰值 -40 dB 以下)裁到 5 ms、尾部(峰值 -60 dB 以下)裁到 20 ms、2 ms 淡入 / 10 ms 淡出、
软限幅(1 ms 前瞻、30 ms 释放)把峰值因子压到 ≤ crest dB、RMS 归 -18 dBFS 且峰值 ≤ -1 dBFS(与 sfx_audit.py 同口径);
原文件不是 .wav 就删掉它和 .import,并把 CLIPS 那行后缀改成 .wav。音色不动,只动静音、电平和攻击尖峰。重复跑是幂等的。
换音效流程:sfx_apply.py <选择表> --no-import(复制原始候选)→ 本脚本 → sfx_apply.py <空文件> --test(--import、GAIN_DB、全量测试)。
需要 ffmpeg 与 numpy(hardware/.venv)。"""
import os, re, sys, wave, subprocess
import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_GD = os.path.join(ROOT, 'game', 'sfx.gd')
DST = os.path.join(ROOT, 'assets', 'sfx')
EXTS = ('.wav', '.ogg', '.mp3')
RATE = 44100
LEAD_DB, TAIL_DB, LEAD_MS, TAIL_MS, FI_MS, FO_MS = -40.0, -60.0, 5, 20, 2, 10
TARGET_RMS, PEAK_CEIL = -18.0, -1.0


def db(v):
    return 20 * np.log10(v + 1e-12)


def decode(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '1', '-ar', str(RATE), '-'],
                         capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def trim_fade(x):
    peak = np.max(np.abs(x)) + 1e-12
    idx = np.where(np.abs(x) > peak * 10 ** (LEAD_DB / 20))[0]
    start = max(0, idx[0] - LEAD_MS * RATE // 1000)
    idx2 = np.where(np.abs(x) > peak * 10 ** (TAIL_DB / 20))[0]
    end = min(len(x), idx2[-1] + 1 + TAIL_MS * RATE // 1000)
    x = x[start:end].copy()
    fi = min(FI_MS * RATE // 1000, len(x)); x[:fi] *= np.linspace(0, 1, fi, endpoint=False)
    fo = min(FO_MS * RATE // 1000, len(x)); x[-fo:] *= np.linspace(1, 0, fo)
    return x


def limit_crest(x, crest_db):
    """峰值包络(瞬时起、30 ms 释放)超过 RMS × crest 的部分按比例压下去,增益提前 1 ms 动作(前瞻)。
    压掉瞬态后整段 RMS 也会降一点,所以迭代几遍直到峰值因子 ≤ crest(短促的木击一般 2–3 遍);返回总共削掉的 dB"""
    peak0 = np.abs(x).max()
    rel = np.exp(-1.0 / (0.030 * RATE))
    la = RATE // 1000
    for _ in range(4):
        rms = np.sqrt(np.mean(x ** 2)) + 1e-12
        thr = rms * 10 ** (crest_db / 20)
        a = np.abs(x)
        if a.max() <= thr * 1.01:
            break
        env = np.empty(len(x)); e = 0.0
        for i in range(len(x)):
            e = a[i] if a[i] > e else e * rel
            env[i] = e
        g = np.minimum(1.0, thr / np.maximum(env, 1e-12))
        g = sliding_window_view(np.pad(g, (0, la), constant_values=1.0), la + 1).min(axis=1)
        x = x * g
    return x, db(peak0) - db(np.abs(x).max())


def normalize(x):
    g = 10 ** ((TARGET_RMS - db(np.sqrt(np.mean(x ** 2)))) / 20)
    g = min(g, 10 ** ((PEAK_CEIL - db(np.max(np.abs(x)))) / 20))
    return x * g


def write_wav(path, x):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(np.clip(np.round(x * 32767.0), -32768, 32767).astype('<i2').tobytes())


def main(argv):
    crest = float(argv[argv.index('--crest') + 1]) if '--crest' in argv else 21.0
    src_gd = open(SFX_GD, encoding='utf-8').read()
    body = src_gd.split('const CLIPS')[1].split('\n}')[0]
    stems = []
    for m in re.finditer(r'&"([a-z_]+)":\s*"res://assets/sfx/([a-z_]+)\.(wav|ogg|mp3)"', body):
        if m.group(2) not in stems:
            stems.append(m.group(2))
    print(f"{'文件':15s} {'原时长':>6s} {'新时长':>6s} {'限幅dB':>6s} {'峰值':>6s} {'RMS':>6s} {'峰因':>5s}")
    for stem in stems:
        src = next((os.path.join(DST, stem + e) for e in EXTS if os.path.exists(os.path.join(DST, stem + e))), None)
        if src is None:
            print(f"{stem:15s} 缺文件"); return 1
        x = decode(src)
        n0 = len(x)
        x = trim_fade(x)
        x, cut = limit_crest(x, crest)
        x = normalize(x)
        out = os.path.join(DST, stem + '.wav')
        write_wav(out, x)
        if src != out:
            for f in (src, src + '.import'):
                if os.path.exists(f):
                    os.remove(f)
        pk, rm = db(np.max(np.abs(x))), db(np.sqrt(np.mean(x ** 2)))
        print(f"{stem:15s} {n0 / RATE:6.2f} {len(x) / RATE:6.2f} {cut:6.1f} {pk:6.1f} {rm:6.1f} {pk - rm:5.1f}")
    new_gd = re.sub(r'"res://assets/sfx/([a-z_]+)\.(ogg|mp3)"', r'"res://assets/sfx/\1.wav"', src_gd)
    if new_gd != src_gd:
        open(SFX_GD, 'w', encoding='utf-8').write(new_gd)
        print('CLIPS 后缀已改成 .wav')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
