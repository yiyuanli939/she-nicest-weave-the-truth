#!/usr/bin/env python3
"""把现用 music/level.wav 做成几个处理版本(速度 / 音高 / 明暗 / 空间感),循环接缝保持无缝:
hardware/.venv/bin/python tools/level_music/level_remix.py  → out_remix/<id>.wav(游戏用)+ .mp3 + level_remix.html(试听页)。
做法:原曲首尾相接循环三遍 → ffmpeg 滤镜链 → 截中间一遍(混响 / 回声尾巴已接进开头)→ loudnorm → 16 bit wav。
变速用 atempo(不变调);变调用 asetrate + aresample 再 atempo 拉回原速。"""
import json, os, subprocess, base64, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, 'music', 'level.wav')
OUT = os.path.join(HERE, 'out_remix')
RATE = 44100


def semi(n):
    return 2 ** (n / 12)


VERSIONS = [
    dict(id='original', name='原版', desc='现在游戏里在用的 level.wav,不处理,作对照', chain='', tempo=1.0, target=-18),
    dict(id='soft', name='柔和', desc='高频再收一点、轻混响,像隔着一层布听', chain='lowpass=f=1800,aecho=0.8:0.5:60|130:0.22|0.14', tempo=1.0, target=-19),
    dict(id='bright', name='明亮', desc='快 4%、中高频提 4 dB、立体声略宽,更精神', chain='atempo=1.04,equalizer=f=1800:t=q:w=1.2:g=4,equalizer=f=3200:t=q:w=1.2:g=3,extrastereo=m=1.6', tempo=1.04, target=-17.5),
    dict(id='slow', name='慢速', desc='慢 10%(不变调)、轻混响,给需要慢慢想的关', chain='atempo=0.9,lowpass=f=2600,aecho=0.8:0.45:90|180:0.2|0.12', tempo=0.9, target=-18.5),
    dict(id='dark', name='暗调', desc='降两个半音、拉回原速、低通 + 长回声,第三章故障后的气氛', chain='asetrate=%d,aresample=%d,atempo=%.5f,lowpass=f=2000,aecho=0.8:0.5:120|260:0.25|0.16' % (int(RATE * semi(-2)), RATE, semi(2)), tempo=1.0, target=-19),
    dict(id='high', name='升调', desc='升两个半音、拉回原速,更亮更轻', chain='asetrate=%d,aresample=%d,atempo=%.5f' % (int(RATE * semi(2)), RATE, semi(-2)), tempo=1.0, target=-18),
    dict(id='far', name='远处', desc='低通 900 Hz、大混响、更轻,像从隔壁织坊传来', chain='lowpass=f=900,aecho=0.8:0.6:200|400:0.35|0.22', tempo=1.0, target=-23),
    dict(id='pulse', name='脉动', desc='按节拍做颤音(约 103 bpm 的半拍)+ 合唱,像织机在推', chain='tremolo=f=1.72:d=0.35,chorus=0.6:0.8:40|60:0.3|0.25:0.25|0.4:2|1.3', tempo=1.0, target=-18),
]


def duration_of(path):
    return float(subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path], capture_output=True, text=True).stdout.strip())


def envelope(path, n=400):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-f', 'f32le', '-ac', '1', '-ar', '8000', '-'], capture_output=True).stdout
    x = np.abs(np.frombuffer(raw, dtype=np.float32))
    k = max(1, len(x) // n)
    env = [float(x[i:i + k].max()) for i in range(0, len(x) - k, k)][:n]
    m = max(env) or 1.0
    return [round(v / m, 3) for v in env]


def crossfade_loop(wav, ms=30):
    """循环接缝交叉淡化:把结尾 ms 毫秒淡出叠进开头淡入,再把结尾那段去掉 —— 变调/变速后接缝处样本对不齐也不会有咔哒"""
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', wav, '-f', 'f32le', '-ac', '2', '-ar', str(RATE), '-'], capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).copy()
    n = int(RATE * ms / 1000)
    up = np.linspace(0, 1, n, dtype=np.float32)[:, None]
    x[:n] = x[:n] * up + x[-n:] * (1 - up)
    y = x[:-n]
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-f', 'f32le', '-ar', str(RATE), '-ac', '2', '-i', '-', '-c:a', 'pcm_s16le', wav], input=y.tobytes(), check=True)


def build():
    os.makedirs(OUT, exist_ok=True)
    L = duration_of(SRC)
    src_dur = L
    rows = []
    for v in VERSIONS:
        wav = os.path.join(OUT, v['id'] + '.wav'); mp3 = os.path.join(OUT, v['id'] + '.mp3')
        Lp = src_dur / v['tempo']
        chain = v['chain']
        graph = 'aloop=loop=2:size=%d' % int(round(src_dur * RATE))
        if chain:
            graph += ',' + chain
        graph += ',atrim=start=%.5f:end=%.5f,asetpts=PTS-STARTPTS,loudnorm=I=%g:TP=-1.5:LRA=9' % (Lp, 2 * Lp, v['target'])
        subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', SRC, '-af', graph, '-ar', str(RATE), '-ac', '2', '-c:a', 'pcm_s16le', wav], check=True)
        crossfade_loop(wav)
        subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', wav, '-codec:a', 'libmp3lame', '-b:a', '128k', mp3], check=True)
        d = duration_of(wav)
        vol = subprocess.run(['ffmpeg', '-i', wav, '-af', 'volumedetect', '-f', 'null', '-'], capture_output=True, text=True).stderr
        mean = [l for l in vol.splitlines() if 'mean_volume' in l][0].split()[-2]
        peak = [l for l in vol.splitlines() if 'max_volume' in l][0].split()[-2]
        rows.append(dict(v, duration=round(d, 2), mean_db=float(mean), peak_db=float(peak), env=envelope(wav),
                         src='data:audio/mpeg;base64,' + base64.b64encode(open(mp3, 'rb').read()).decode()))
        print('%-9s %-4s %5.2fs  mean %s dB  peak %s dB  %s' % (v['id'], v['name'], d, mean, peak, v['chain'][:70]))
    tpl = open(os.path.join(HERE, 'remix.tpl.html'), encoding='utf-8').read()
    html = tpl.replace('__DATA__', json.dumps(rows, ensure_ascii=False).replace('</', '<\\/'))
    open(os.path.join(OUT, 'level_remix.html'), 'w', encoding='utf-8').write(html)
    json.dump([{k: r[k] for k in r if k not in ('src', 'env')} for r in rows], open(os.path.join(OUT, 'versions.json'), 'w'), ensure_ascii=False, indent=1)
    print(len(html) // 1024, 'KB page')


if __name__ == '__main__':
    build()
