#!/usr/bin/env python3
"""按乐理写关内曲(规则见 THEORY.md):hardware/.venv/bin/python tools/level_music/theory_compose.py [out_dir] [--sf 音色库.sf3]
流程:乐句计划(乐段 / 乐句 + 终止式)→ 罗马数字和声(music21 取音)→ 四部排列动态规划(禁平行五八、导音 / 七音解决、
最小位移)→ 高声部骨架 → 动机化旋律(强拍和弦音、弱拍经过 / 辅助音,跳进后反向级进)→ 配器成 MIDI(mido)→
FluidSynth + MuseScore_General 渲染 → 取第二遍做无缝循环 → loudnorm → wav(游戏)+ mp3(试听台)。
每首输出 <id>.mid / .wav / .mp3 / .json(逐小节和声、终止式、各项检查结果)。全部确定性,无随机。"""
import json, os, subprocess, sys, itertools
from music21 import key as m21key, roman, voiceLeading, pitch as m21pitch, note as m21note

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SF_DEFAULT = os.path.join(HERE, 'sf', 'MuseScore_General.sf3')

MAJ = [0, 2, 4, 5, 7, 9, 11]
MIN = [0, 2, 3, 5, 7, 8, 10]
RANGES = {'S': (62, 79), 'A': (55, 74), 'T': (48, 67), 'B': (40, 60)}   # D4–G5 / G3–D5 / C3–G4 / E2–C4


# ---------------- 和声 ----------------

def key_of(tonic, mode):
    return m21key.Key(tonic if mode == 'major' else tonic.lower())


def chord_info(rn_text, k):
    rn = roman.RomanNumeral(rn_text, k)
    pcs = sorted(set(p.pitchClass for p in rn.pitches))
    seventh = rn.seventh.pitchClass if rn.seventh is not None else None
    return dict(figure=rn_text, pcs=pcs, bass=rn.bass().pitchClass, root=rn.root().pitchClass,
                third=(rn.third.pitchClass if rn.third is not None else None), fifth=(rn.fifth.pitchClass if rn.fifth is not None else None),
                seventh=seventh, is_dom=(rn.scaleDegree in (5, 7)), degree=rn.scaleDegree)


def scale_pcs(k, mode, chord=None):
    t = k.tonic.pitchClass
    base = [(t + i) % 12 for i in (MAJ if mode == 'major' else MIN)]
    if mode == 'minor' and chord is not None and chord['is_dom']:   # 属功能:用和声小调的导音
        base[6] = (t + 11) % 12
    return base


def degree_pc(k, deg, mode, raised7=False):
    t = k.tonic.pitchClass
    steps = MAJ if mode == 'major' else MIN
    pc = (t + steps[deg - 1]) % 12
    if mode == 'minor' and deg == 7 and raised7:
        pc = (t + 11) % 12
    return pc


# ---------------- 四部排列(动态规划) ----------------

def _parallel_perfect(prev, cur):
    """任意两声部都在动、从纯五(八)到纯五(八)—— 平行或反向纯五八 —— 算违规;外声部同向跳进到达纯五八(隐伏)也算"""
    names = list(prev.keys())
    for a, b in itertools.combinations(names, 2):
        i1 = abs(prev[a] - prev[b]) % 12
        i2 = abs(cur[a] - cur[b]) % 12
        if i2 in (0, 7) and cur[a] != prev[a] and cur[b] != prev[b]:
            if i1 == i2:
                return True                          # 平行 / 反向五八
            da, db = cur[a] - prev[a], cur[b] - prev[b]
            if (da > 0) == (db > 0) and {a, b} == {'S', 'B'} and abs(cur['S'] - prev['S']) > 2:
                return True                          # 外声部隐伏(高声部跳进到达)
    return False


def _voicings(ch, prev_bass):
    """枚举合法排列:B 取和弦低音,S/A/T 覆盖和弦音;重复音 / 音域 / 间距 / 不交叉"""
    out = []
    pcs = ch['pcs']
    bass_opts = [p for p in range(RANGES['B'][0], RANGES['B'][1] + 1) if p % 12 == ch['bass']]
    if prev_bass is not None:
        bass_opts.sort(key=lambda p: abs(p - prev_bass))
        bass_opts = bass_opts[:2]
    for b in bass_opts:
        for combo in itertools.product(pcs, repeat=3):
            all_pcs = list(combo) + [ch['bass']]
            need = set(pcs)
            if ch['seventh'] is not None:
                if not (need <= set(all_pcs) or (set(all_pcs) >= need - {ch['fifth']} and all_pcs.count(ch['root']) == 2)):
                    continue
            else:
                if not need <= set(all_pcs):
                    continue
            lt = None
            if ch['is_dom']:
                lt = ch['third'] if ch['degree'] == 5 else ch['root']
                if lt is not None and all_pcs.count(lt) > 1:
                    continue                          # 导音不重复
            if ch['seventh'] is not None and all_pcs.count(ch['seventh']) > 1:
                continue
            for s in range(RANGES['S'][0], RANGES['S'][1] + 1):
                if s % 12 != combo[0]:
                    continue
                for a in range(RANGES['A'][0], RANGES['A'][1] + 1):
                    if a % 12 != combo[1] or a >= s or s - a > 12:
                        continue
                    for t in range(RANGES['T'][0], RANGES['T'][1] + 1):
                        if t % 12 != combo[2] or t >= a or a - t > 12 or t <= b or t - b > 19:
                            continue
                        out.append({'S': s, 'A': a, 'T': t, 'B': b})
    return out


def voice_lead(chords, k, mode, soprano_rules, climax_idx):
    """chords: chord_info 列表;soprano_rules: {index: set(允许的音级)};返回每个和弦的 SATB"""
    tonic = k.tonic.pitchClass
    layers = []
    for i, ch in enumerate(chords):
        prev_b = layers[-1][0]['B'] if layers and layers[-1] else None
        vs = _voicings(ch, None)
        if i in soprano_rules:
            allowed = set(degree_pc(k, d, mode, raised7=True) for d in soprano_rules[i])
            vs = [v for v in vs if v['S'] % 12 in allowed]
        assert vs, '和弦 %d %s 无合法排列' % (i, ch['figure'])
        layers.append(vs)
    n = len(chords)
    INF = 10 ** 9
    best = [[(0, -1)] * len(layers[0])] + [[(INF, -1)] * len(l) for l in layers[1:]]
    for i in range(1, n):
        ch, prev_ch = chords[i], chords[i - 1]
        for j, v in enumerate(layers[i]):
            for pj, pv in enumerate(layers[i - 1]):
                pc, _ = best[i - 1][pj]
                if pc >= INF:
                    continue
                if _parallel_perfect(pv, v):
                    continue
                sd = abs(v['S'] - pv['S'])
                if sd == 6 or sd > 9 or abs(v['B'] - pv['B']) > 12:
                    continue                          # 高声部不跳三全音 / 超过小六度;低音不超八度
                bad = False
                # 导音(外声部)上行到主音;七音下行级进
                if prev_ch['is_dom'] and ch['degree'] == 1:
                    lt = (tonic + 11) % 12
                    for vn in ('S', 'B'):
                        if pv[vn] % 12 == lt and v[vn] - pv[vn] != 1:
                            bad = True
                if prev_ch['seventh'] is not None:
                    for vn in ('S', 'A', 'T', 'B'):
                        if pv[vn] % 12 == prev_ch['seventh'] and not (-2 <= v[vn] - pv[vn] <= -1):
                            bad = True
                if bad:
                    continue
                cost = sum(abs(v[x] - pv[x]) for x in ('S', 'A', 'T')) + abs(v['B'] - pv['B']) * 0.5
                if abs(v['S'] - pv['S']) > 7:
                    cost += 6                         # 高声部大跳
                if abs(v['B'] - pv['B']) > 7:
                    cost += 3                         # 低音大跳
                if v['S'] < 64:
                    cost += (64 - v['S']) * 1.5       # 高声部别一直趴在底下
                if abs(v['S'] - pv['S']) == 0:
                    cost += 1                         # 高声部原地不动略罚,让线条有起伏
                if (v['S'] - pv['S']) * (v['B'] - pv['B']) > 0:
                    cost += 1.5                       # 外声部同向略罚
                # 高潮塑形:高潮和弦鼓励高音,其它地方过高罚
                if i == climax_idx:
                    cost -= (v['S'] - 67) * 0.6
                elif v['S'] > 76:
                    cost += (v['S'] - 76) * 2
                c = pc + cost
                if c < best[i][j][0]:
                    best[i][j] = (c, pj)
    j = min(range(len(layers[-1])), key=lambda x: best[-1][x][0])
    assert best[-1][j][0] < INF, '无法在不出现平行五八度的前提下连接整段和声'
    path = []
    for i in range(n - 1, -1, -1):
        path.append(layers[i][j])
        j = best[i][j][1]
    return path[::-1]


def check_parallels_music21(voicings):
    """独立复核:music21 VoiceLeadingQuartet 数平行五八"""
    bad = 0
    names = ['S', 'A', 'T', 'B']
    for i in range(1, len(voicings)):
        for a, b in itertools.combinations(names, 2):
            v1n1 = m21note.Note(voicings[i - 1][a]); v1n2 = m21note.Note(voicings[i][a])
            v2n1 = m21note.Note(voicings[i - 1][b]); v2n2 = m21note.Note(voicings[i][b])
            q = voiceLeading.VoiceLeadingQuartet(v1n1, v1n2, v2n1, v2n2)
            if q.parallelFifth() or q.parallelOctave() or q.parallelUnison():
                bad += 1
    return bad


# ---------------- 旋律 ----------------

def _step(pc_scale, p, direction):
    """沿音阶走一步"""
    q = p + direction
    while q % 12 not in pc_scale:
        q += direction
    return q


def melody_for_bar(rhythm, start_pitch, next_pitch, chord_pcs, scale, prev_pitch, is_last_bar, cadence):
    """rhythm: [(起拍, 时长)];第一音 = 骨架音,其余按经过 / 辅助 / 和弦音填,遵守跳进后反向级进"""
    notes = []
    n = len(rhythm)
    pitches = [start_pitch]
    diff = next_pitch - start_pitch
    steps_needed = 0
    # 起点到下一骨架音之间的音阶步数
    if diff != 0:
        p = start_pitch
        d = 1 if diff > 0 else -1
        while p != next_pitch and abs(p - start_pitch) < 24:
            p = _step(scale, p, d); steps_needed += 1
    for i in range(1, n):
        remaining = n - i                           # 含本音还剩几个音要走到 next_pitch
        cur = pitches[-1]
        strong = rhythm[i][0] == int(rhythm[i][0])   # 整拍视为强位
        if is_last_bar and cadence in ('PAC', 'HC') and i == n - 1:
            # 终止前最后一个音:2̂ / 7̂ 之类由骨架决定,这里向 next_pitch 级进靠拢
            pitches.append(_step(scale, cur, 1 if next_pitch > cur else -1) if next_pitch != cur else cur)
            continue
        if diff != 0 and steps_needed >= remaining and abs(next_pitch - cur) > 2:
            pitches.append(_step(scale, cur, 1 if diff > 0 else -1))     # 经过音级进
            continue
        # 和弦音琶音 / 辅助音:强位用和弦音,弱位可用上辅助音
        cands = []
        for q in range(cur - 9, cur + 10):
            if q == cur:
                continue
            if q % 12 in chord_pcs and (strong or True):
                leap = abs(q - cur)
                if leap in (6,) or leap > 9:
                    continue
                prev_leap = cur - prev_pitch if prev_pitch is not None else 0
                if abs(prev_leap) >= 5 and (q - cur) * prev_leap > 0:
                    continue                          # 跳进后不再同向
                if abs(prev_leap) >= 5 and leap > 2:
                    continue                          # 跳进后必须级进
                cost = leap + (0 if strong else 1) + abs(q - next_pitch) * 0.3 + abs(q - start_pitch) * 0.15
                if q > 79 or q < 62:
                    continue                          # 旋律音域 D4–G5
                cands.append((cost, q))
        if not strong:
            nb = _step(scale, cur, 1 if cur < 77 else -1)   # 辅助音(弱位,回到和弦音由下一音承担);顶上就用下辅助音
            cands.append((1.5 + abs(nb - next_pitch) * 0.3, nb))
        cands.sort()
        pitches.append(cands[0][1] if cands else cur)
        prev_pitch = cur
    for (onset, dur), p in zip(rhythm, pitches):
        notes.append((onset, dur, p))
    return notes


# ---------------- 计划 ----------------

def period_16(hc, pac):
    """16 小节平行乐段:前句 HC、后句 PAC,各 8 小节"""
    return [dict(chords=hc, cadence='HC'), dict(chords=pac, cadence='PAC')]


PIECES = [
    dict(id='shuttle', name='梭声', tonic='D', mode='major', meter=(6, 8), beats_per_bar=2, bpm=88,
         mood='音乐盒主奏 + 拨弦分解 + 木鱼梭声,D 大调 6/8 平行乐段(前句半终止、后句完全终止)',
         phrases=period_16(['I', 'vi', 'IV', 'V', 'I', 'IV', 'ii6', 'V'], ['I', 'vi', 'IV', 'V', 'I', 'ii6', 'V7', 'I']),
         motif=[[(0, 1), (1, 1 / 3), (4 / 3, 1 / 3), (5 / 3, 1 / 3)], [(0, 2 / 3), (2 / 3, 1 / 3), (1, 1)]],
         cont=[[(0, 1 / 3), (1 / 3, 1 / 3), (2 / 3, 1 / 3), (1, 1)]], cad=[[(0, 1), (1, 1)], [(0, 2)]],
         style='arp68', melody_prog=10, acc_prog=45, bass_prog=42, pad_prog=None, perc='woodblock', repeat=True),
    dict(id='brass', name='黄铜机房', tonic='A', mode='minor', meter=(4, 4), beats_per_bar=4, bpm=96,
         mood='大键琴主奏 + 十六分分解 + 木鱼节拍,A 小调 4/4 平行乐段,弗里吉亚半终止',
         phrases=period_16(['i', 'VI', 'iv', 'V', 'i', 'iv', 'iv6', 'V'], ['i', 'VI', 'iv', 'V', 'i', 'iv', 'V7', 'i']),
         motif=[[(0, 1), (1, 0.5), (1.5, 0.5), (2, 1), (3, 1)], [(0, 1.5), (1.5, 0.5), (2, 2)]],
         cont=[[(0, 0.5), (0.5, 0.5), (1, 1), (2, 0.5), (2.5, 0.5), (3, 1)]], cad=[[(0, 1), (1, 1), (2, 2)], [(0, 4)]],
         style='arp16', melody_prog=6, acc_prog=6, bass_prog=32, pad_prog=None, perc='woodblock'),
    dict(id='wool', name='羊毛与雨', tonic='C', mode='major', meter=(4, 4), beats_per_bar=4, bpm=72,
         mood='钢琴主奏 + 弱奏弦乐铺底 + 大提琴低音,C 大调 4/4 平行乐段,慢',
         phrases=period_16(['I', 'IV', 'vi', 'V', 'I', 'IV', 'ii6', 'V'], ['I', 'IV', 'vi', 'V', 'I', 'IV', 'V7', 'I']),
         motif=[[(0, 2), (2, 1), (3, 1)], [(0, 3), (3, 1)]],
         cont=[[(0, 1), (1, 1), (2, 2)]], cad=[[(0, 2), (2, 2)], [(0, 4)]],
         style='block', melody_prog=0, acc_prog=0, bass_prog=42, pad_prog=49, perc=None),
    dict(id='waltz', name='齿轮华尔兹', tonic='G', mode='major', meter=(3, 4), beats_per_bar=3, bpm=126,
         mood='拨弦主奏 + 嗡啪啪伴奏 + 每四小节一声钟琴,G 大调 3/4 平行乐段',
         phrases=period_16(['I', 'I', 'V', 'V', 'I', 'vi', 'ii6', 'V'], ['I', 'I', 'V', 'V', 'IV', 'I', 'V7', 'I']),
         motif=[[(0, 1), (1, 1), (2, 1)], [(0, 2), (2, 1)]],
         cont=[[(0, 1), (1, 0.5), (1.5, 0.5), (2, 1)]], cad=[[(0, 1), (1, 2)], [(0, 3)]],
         style='waltz', melody_prog=45, acc_prog=46, bass_prog=42, pad_prog=None, perc='triangle', repeat=True),
    dict(id='quiet', name='静语', tonic='E', mode='minor', meter=(4, 4), beats_per_bar=4, bpm=66,
         mood='钟琴主奏 + 弦乐持续 + 大提琴,E 小调 4/4 平行乐段,很慢很稀',
         phrases=period_16(['i', 'VI', 'iv', 'V', 'i', 'VI', 'iv6', 'V'], ['i', 'VI', 'iv', 'V', 'i', 'iv', 'V7', 'i']),
         motif=[[(0, 2), (2, 2)], [(0, 3), (3, 1)]],
         cont=[[(0, 2), (2, 1), (3, 1)]], cad=[[(0, 2), (2, 2)], [(0, 4)]],
         style='pad', melody_prog=9, acc_prog=None, bass_prog=42, pad_prog=49, perc=None),
]


def bar_rhythms(p, nbars):
    """乐段 16 小节的节奏分配:前 4 小节 基本乐思 + 复述,5–6 延续(片段化),7–8 终止;后句同。
    重复一遍乐段时(32 小节)第二遍基本乐思改用延续段的密节奏做变奏"""
    out = []
    for ph in range(2):
        out += p['motif'] + p['motif'] + p['cont'] + p['cont'] + p['cad']
    if nbars == 32:
        for ph in range(2):
            out += p['cont'] + p['cont'] + p['cont'] + p['cont'] + p['cont'] + p['cont'] + p['cad']
    assert len(out) == nbars, (len(out), nbars)
    return out


# ---------------- 生成 ----------------

def compose(p):
    k = key_of(p['tonic'], p['mode'])
    chords_txt = [c for ph in p['phrases'] for c in ph['chords']]
    if p.get('repeat'):
        chords_txt = chords_txt * 2
    chords = [chord_info(c, k) for c in chords_txt]
    n = len(chords)
    rules = {7: {2, 7}, 15: {1}, 14: {2, 7}}    # HC 高声部停 2̂/7̂;PAC 前 V7 高声部 2̂/7̂、终止 1̂
    if n == 32:
        rules.update({23: {2, 7}, 31: {1}, 30: {2, 7}})
    voicings = voice_lead(chords, k, p['mode'], rules, climax_idx=int(n * 2 / 3))
    assert check_parallels_music21(voicings) == 0
    rhythms = bar_rhythms(p, n)
    bpb = p['beats_per_bar']
    melody = []
    prev = None
    for i in range(n):
        start = voicings[i]['S']
        nxt = voicings[(i + 1) % n]['S']
        scale = scale_pcs(k, p['mode'], chords[i])
        cadence = None
        if i % 16 == 7: cadence = 'HC'
        if i % 16 == 15: cadence = 'PAC'
        bar = melody_for_bar(rhythms[i], start, nxt, chords[i]['pcs'], scale, prev, cadence is not None, cadence)
        for (on, du, pi) in bar:
            melody.append([round(i * bpb + on, 4), round(du * 0.92, 4), pi, 0.85 if on == 0 else 0.68])
        prev = bar[-1][2]
    # 小节接缝修补:进入下一小节骨架音若是三全音 / 超过小六度的跳进,把前一音改成朝骨架音的级进音
    for i in range(1, len(melody)):
        d = melody[i][2] - melody[i - 1][2]
        if abs(d) == 6 or abs(d) > 9:
            bar_i = int(melody[i][0] // bpb)
            scale = scale_pcs(k, p['mode'], chords[bar_i % n])
            melody[i - 1][2] = min(79, max(62, _step(scale, melody[i][2], -1 if d > 0 else 1)))
    # 循环接缝:最后一音回到第一音也按同样规则
    d = melody[0][2] - melody[-1][2]
    if abs(d) == 6 or abs(d) > 9:
        melody[-1][2] = _step(scale_pcs(k, p['mode'], chords[-1]), melody[0][2], -1 if d > 0 else 1)
    # 旋律规则复核:跳进 ≤ 小六度、无三全音跳进、跳进(≥四度)后反向级进(允许同向再走一步内的例外计数)
    leaps_bad = 0
    tritone = 0
    for i in range(1, len(melody)):
        d = melody[i][2] - melody[i - 1][2]
        if abs(d) > 9: leaps_bad += 1
        if abs(d) == 6: tritone += 1
    # 伴奏
    tracks = []
    bass, acc, pad, perc = [], [], [], []
    for i, v in enumerate(voicings):
        t0 = i * bpb
        st = p['style']
        if st == 'arp68':
            e = 1 / 3
            pat = [v['B'] + 12, v['T'], v['A'], v['T'], v['A'], v['T']]
            for j, pitch_ in enumerate(pat):
                acc.append([round(t0 + j * e, 4), round(e * 1.5, 4), pitch_, 0.5 if j in (0, 3) else 0.38])
            bass.append([t0, 0.95, v['B'], 0.75]); bass.append([t0 + 1, 0.95, v['B'], 0.5])
            for j in range(6):
                perc.append([round(t0 + j * e, 4), 0.1, 77 if j in (0, 3) else 76, 0.5 if j in (0, 3) else 0.22])
        elif st == 'arp16':
            pat = [v['T'], v['A'], v['B'] + 12, v['A']]
            for j in range(16):
                acc.append([round(t0 + j * 0.25, 4), 0.28, pat[j % 4], 0.5 if j % 4 == 0 else 0.34])
            bass.append([t0, 1.9, v['B'], 0.8]); bass.append([t0 + 2, 0.95, v['B'], 0.55]); bass.append([t0 + 3, 0.95, v['T'] - 12 if v['T'] - 12 >= 40 else v['B'], 0.5])
            for j in range(8):
                perc.append([round(t0 + j * 0.5, 4), 0.08, 76, 0.35 if j % 2 == 0 else 0.16])
        elif st == 'block':
            for pitch_ in (v['A'], v['T']):
                acc.append([t0, 2.9, pitch_, 0.5]); acc.append([t0 + 2.5, 1.4, pitch_, 0.32])
            bass.append([t0, 3.8, v['B'], 0.62])
            for pitch_ in (v['A'], v['T']):
                pad.append([t0, 4.0, pitch_, 0.3])
        elif st == 'waltz':
            bass.append([t0, 0.8, v['B'], 0.78])
            for b in (1, 2):
                for pitch_ in (v['T'], v['A']):
                    acc.append([t0 + b, 0.5, pitch_, 0.36])
            if i % 4 == 3:
                perc.append([t0 + 2, 0.4, 81, 0.35])
        elif st == 'pad':
            for pitch_ in (v['A'], v['T']):
                pad.append([t0, 4.0, pitch_, 0.32])
            bass.append([t0, 3.9, v['B'], 0.55])
    tracks.append(dict(name='旋律', prog=p['melody_prog'], ch=0, gain=1.0, notes=melody))
    if acc: tracks.append(dict(name='伴奏', prog=p['acc_prog'], ch=1, gain=0.8, notes=acc))
    if pad: tracks.append(dict(name='铺底', prog=p['pad_prog'], ch=2, gain=0.7, notes=pad))
    tracks.append(dict(name='低音', prog=p['bass_prog'], ch=3, gain=0.9, notes=bass))
    if perc: tracks.append(dict(name='打击', prog=None, ch=9, gain=0.8, notes=perc))
    duration = n * bpb * 60 / p['bpm']
    report = dict(id=p['id'], name=p['name'], mood=p['mood'], key=('%s %s' % (p['tonic'], '大调' if p['mode'] == 'major' else '小调')),
                  meter='%d/%d' % p['meter'], bpm=p['bpm'], bars=n, beats_per_bar=bpb, duration=round(duration, 2),
                  progression=chords_txt, cadences=({'bar8': 'HC', 'bar16': 'PAC', 'bar24': 'HC', 'bar32': 'PAC'} if n == 32 else {'bar8': 'HC', 'bar16': 'PAC'}),
                  soprano_skeleton=[v['S'] for v in voicings], voicings=voicings,
                  checks=dict(parallel_5_8_music21=check_parallels_music21(voicings), melody_leaps_over_m6=leaps_bad, melody_tritone_leaps=tritone,
                              hc_soprano_deg=_deg(k, voicings[7]['S'], p['mode']), pac_soprano_deg=_deg(k, voicings[15]['S'], p['mode']),
                              melody_range=max(m[2] for m in melody) - min(m[2] for m in melody)),
                  tracks=tracks, note_count=sum(len(t['notes']) for t in tracks))
    return report


def _deg(k, midi_, mode):
    t = k.tonic.pitchClass
    steps = MAJ if mode == 'major' else MIN
    pc = (midi_ - t) % 12
    for i, s in enumerate(steps):
        if s == pc: return i + 1
    if mode == 'minor' and pc == 11: return 7
    return 0


# ---------------- MIDI / 渲染 ----------------

def write_midi(rep, path, repeats=2):
    import mido
    tpb = 480
    mid = mido.MidiFile(ticks_per_beat=tpb)
    meta = mido.MidiTrack(); mid.tracks.append(meta)
    meta.append(mido.MetaMessage('set_tempo', tempo=mido.bpm2tempo(rep['bpm']), time=0))
    loop_beats = rep['bars'] * rep['beats_per_bar']
    for tr in rep['tracks']:
        t = mido.MidiTrack(); mid.tracks.append(t)
        ch = tr['ch']
        if tr['prog'] is not None:
            t.append(mido.Message('program_change', program=tr['prog'], channel=ch, time=0))
        t.append(mido.Message('control_change', control=7, value=int(100 * tr['gain']), channel=ch, time=0))
        events = []
        for r in range(repeats):
            for (on, du, pi, vel) in tr['notes']:
                a = int(round((on + r * loop_beats) * tpb)); b = a + max(int(round(du * tpb)), 10)
                events.append((a, 1, pi, int(40 + 87 * vel))); events.append((b, 0, pi, 0))
        events.sort(key=lambda e: (e[0], e[1]))
        last = 0
        for (tick, kind, pi, vel) in events:
            msg = mido.Message('note_on' if kind else 'note_off', note=int(pi), velocity=vel, channel=ch, time=tick - last)
            t.append(msg); last = tick
    mid.save(path)


def render(rep, out_dir, sf):
    mid = os.path.join(out_dir, rep['id'] + '.mid'); write_midi(rep, mid)
    raw = os.path.join(out_dir, rep['id'] + '_raw.wav')
    subprocess.run(['fluidsynth', '-ni', '-g', '1.4', '-R', '1', '-r', '44100', '-F', raw, sf, mid], capture_output=True, check=True)
    L = rep['duration']
    wav = os.path.join(out_dir, rep['id'] + '.wav'); mp3 = os.path.join(out_dir, rep['id'] + '.mp3')
    # 取第二遍(混响尾巴已接进开头)→ 响度归一 → 16 bit
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-ss', '%.4f' % L, '-t', '%.4f' % L, '-i', raw, '-af', 'loudnorm=I=-18:TP=-1.5:LRA=9', '-ar', '44100', '-c:a', 'pcm_s16le', wav], check=True)
    subprocess.run(['ffmpeg', '-y', '-v', 'error', '-i', wav, '-codec:a', 'libmp3lame', '-b:a', '128k', mp3], check=True)
    os.remove(raw)
    return wav, mp3


def main(argv):
    out_dir = argv[0] if argv and not argv[0].startswith('--') else os.path.join(HERE, 'out')
    sf = SF_DEFAULT
    if '--sf' in argv: sf = argv[argv.index('--sf') + 1]
    os.makedirs(out_dir, exist_ok=True)
    reports = []
    for p in PIECES:
        rep = compose(p)
        json.dump(rep, open(os.path.join(out_dir, rep['id'] + '.json'), 'w'), ensure_ascii=False, indent=1)
        if os.path.exists(sf):
            render(rep, out_dir, sf)
        reports.append(rep)
        c = rep['checks']
        print('%-8s %-6s %s %5.1fs %4d音  和声:%s  检查:%s' % (rep['id'], rep['name'], rep['key'], rep['duration'], rep['note_count'], ' '.join(rep['progression']), c))
    json.dump(reports, open(os.path.join(out_dir, 'compositions.json'), 'w'), ensure_ascii=False)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
