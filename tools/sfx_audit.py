#!/usr/bin/env python3
"""操作音效审计:hardware/.venv/bin/python tools/sfx_audit.py [文件或目录…]
默认量 game/sfx.gd CLIPS 里的每个文件:时长、峰值 / RMS(dBFS)、频谱质心、4 kHz 以上能量占比、峰值因子,
按「不刺耳」标准(质心 < 3 kHz、4 kHz 以上占比 < 0.3、峰值因子 < 22 dB)标出超标的,并给 GAIN_DB 建议值
(目标 RMS -18 dBFS,封顶在 -峰值 不削波,取 0.5 dB 步)。需要 ffmpeg 与 numpy。退出码 = 刺耳 / 缺失的文件数。"""
import os, re, sys, subprocess
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RATE = 44100
CEN_MAX, HI4_MAX, CREST_MAX = 3000.0, 0.30, 22.0


def load(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '1', '-ar', str(RATE), '-'],
                         capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def feats(x):
    n = len(x)
    if n < 64:
        return None
    peak = float(np.max(np.abs(x)) + 1e-9)
    rms = float(np.sqrt(np.mean(x ** 2)) + 1e-9)
    F = 8192 if n >= 8192 else int(2 ** np.floor(np.log2(n)))
    w = np.hanning(F); hop = F // 2; spec = np.zeros(F // 2 + 1)
    for s in range(0, max(1, n - F + 1), hop):
        spec += np.abs(np.fft.rfft(x[s:s + F] * w)) ** 2
    freqs = np.fft.rfftfreq(F, 1 / RATE); tot = spec.sum() + 1e-12
    cen = float((freqs * spec).sum() / tot); hi4 = float(spec[freqs > 4000].sum() / tot)
    peak_db = 20 * np.log10(peak); rms_db = 20 * np.log10(rms); crest = peak_db - rms_db
    gain = max(-8.0, min(-18.0 - rms_db, -peak_db))
    return dict(dur=n / RATE, peak_db=peak_db, rms_db=rms_db, crest=crest, centroid=cen, hi4k=hi4,
                gain=round(gain * 2) / 2)


def clips_from_script():
    src = open(os.path.join(ROOT, 'game', 'sfx.gd'), encoding='utf-8').read()
    body = src.split('const CLIPS')[1].split('}')[0]
    out = []
    for m in re.finditer(r'&"([a-z_]+)":\s*"res://([^"]+)"', body):
        out.append((m.group(1), os.path.join(ROOT, m.group(2))))
    return out


def main(argv):
    targets = []
    if argv:
        for a in argv:
            if os.path.isdir(a):
                for f in sorted(os.listdir(a)):
                    if f.lower().endswith(('.ogg', '.wav', '.mp3')):
                        targets.append((os.path.splitext(f)[0], os.path.join(a, f)))
            else:
                targets.append((os.path.splitext(os.path.basename(a))[0], a))
    else:
        targets = clips_from_script()
    bad = 0
    print(f"{'槽位':16s} {'时长':>5s} {'峰值':>6s} {'RMS':>6s} {'质心':>6s} {'>4k':>5s} {'峰因':>5s} {'建议dB':>6s}  判定")
    for slot, path in targets:
        if not os.path.exists(path):
            print(f"{slot:16s} 缺文件 {path}"); bad += 1; continue
        f = feats(load(path))
        if f is None:
            print(f"{slot:16s} 读不出样本 {path}"); bad += 1; continue
        why = []
        if f['centroid'] > CEN_MAX: why.append('质心高')
        if f['hi4k'] > HI4_MAX: why.append('高频多')
        if f['crest'] > CREST_MAX: why.append('尖峰')
        verdict = '刺耳:' + '/'.join(why) if why else '柔和'
        if why: bad += 1
        print(f"{slot:16s} {f['dur']:5.2f} {f['peak_db']:6.1f} {f['rms_db']:6.1f} {f['centroid']:6.0f} {f['hi4k']:5.2f} {f['crest']:5.1f} {f['gain']:+6.1f}  {verdict}")
    print(f"超标 / 缺失:{bad}")
    return bad


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
