"""静语纹关内曲候选:五首循环曲的音符数据(确定性、无随机)。输出 compositions.json,给试听台(Web Audio 合成)与离线渲染共用。
每首:bpm、拍号、调、小节数、轨道 [{name, inst, gain, notes:[[起拍(拍), 时长(拍), MIDI, 力度 0..1], …]}]。
乐器 id 与两端合成器对应:musicbox / pluck / harpsi / piano / pad / bass / bell / tick / block / drone。"""
import json, os

NOTE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def midi(name, octave):
    base = NOTE[name[0]] + (1 if len(name) > 1 and name[1] == '#' else 0) - (1 if len(name) > 1 and name[1] == 'b' else 0)
    return 12 * (octave + 1) + base


def chord(root, quality, octave=3):
    r = midi(root, octave)
    q = {'maj': [0, 4, 7], 'min': [0, 3, 7], 'maj7': [0, 4, 7, 11], 'min7': [0, 3, 7, 10], '7': [0, 4, 7, 10],
         'sus2': [0, 2, 7], 'add9': [0, 4, 7, 14], '6': [0, 4, 7, 9], 'min9': [0, 3, 7, 10, 14]}[quality]
    return [r + i for i in q]


pieces = []

# ---------- 1. 梭声(音乐盒,D 大调 6/8,像梭子来回)----------
def piece_shuttle():
    bpm, beats_per_bar, bars = 92, 2, 24          # 6/8:一小节 2 个附点四分拍,每拍 3 个八分
    prog = [('D', 'maj'), ('B', 'min'), ('G', 'maj'), ('A', 'maj'), ('D', 'maj'), ('F#', 'min'), ('G', 'maj'), ('A', 'maj')]
    mb, bass, tick, mel = [], [], [], []
    e = 1 / 3  # 一个八分音符 = 1/3 拍
    # 主旋律:每 8 小节一句,两句变奏(以音阶度写,D 大调)
    scale = [midi('D', 5), midi('E', 5), midi('F#', 5), midi('G', 5), midi('A', 5), midi('B', 5), midi('C#', 6), midi('D', 6)]
    phrase_a = [(0, 2, 0), (2, 1, 2), (3, 1, 4), (4, 2, 5), (6, 1, 4), (7, 1, 2),
                (8, 2, 3), (10, 1, 2), (11, 1, 0), (12, 3, 1), (15, 1, 2),
                (16, 2, 0), (18, 1, 2), (19, 1, 4), (20, 2, 7), (22, 1, 5), (23, 1, 4),
                (24, 2, 3), (26, 1, 4), (27, 1, 2), (28, 4, 0)]
    phrase_b = [(0, 2, 4), (2, 1, 5), (3, 1, 7), (4, 2, 5), (6, 1, 4), (7, 1, 2),
                (8, 2, 3), (10, 1, 4), (11, 1, 5), (12, 3, 4), (15, 1, 2),
                (16, 2, 0), (18, 1, 1), (19, 1, 2), (20, 2, 3), (22, 1, 4), (23, 1, 5),
                (24, 2, 4), (26, 1, 2), (27, 1, 1), (28, 4, 0)]
    phrase_c = [(0, 2, 7), (2, 1, 5), (3, 1, 4), (4, 2, 5), (6, 1, 4), (7, 1, 3),
                (8, 2, 4), (10, 1, 2), (11, 1, 0), (12, 3, 2), (15, 1, 1),
                (16, 2, 0), (18, 1, 2), (19, 1, 4), (20, 2, 7), (22, 1, 5), (23, 1, 4),
                (24, 2, 3), (26, 1, 1), (27, 1, 2), (28, 6, 0)]
    for ph_i, ph in enumerate([phrase_a, phrase_b, phrase_c]):
        base_bar = ph_i * 8
        for (start8, len8, deg) in ph:
            t = base_bar * beats_per_bar + start8 * e
            mel.append([round(t, 4), round(len8 * e * 0.95, 4), scale[deg], 0.8 if start8 % 6 == 0 else 0.62])
    for bar in range(bars):
        root, qual = prog[bar % 8]
        ch = chord(root, qual, 4)
        t0 = bar * beats_per_bar
        # 音乐盒分解:1-3-5-3-5-3 六个八分,每小节一轮,第三段加高八度
        pat = [ch[0], ch[1], ch[2], ch[1], ch[2], ch[1]]
        if bar >= 16:
            pat = [ch[0], ch[2], ch[1] + 12, ch[2], ch[1], ch[2] + 12]
        for i, n in enumerate(pat):
            mb.append([round(t0 + i * e, 4), round(e * 1.6, 4), n, 0.55 if i in (0, 3) else 0.38])
        # 低音:每小节两拍各一个,第二拍五度
        bass.append([t0, 0.9, chord(root, qual, 2)[0], 0.7])
        bass.append([t0 + 1, 0.9, chord(root, qual, 2)[2], 0.5])
        # 梭子:六个八分轻响,1、4 重
        for i in range(6):
            tick.append([round(t0 + i * e, 4), 0.08, 60, 0.45 if i in (0, 3) else 0.18])
    return dict(id='shuttle', name='梭声', mood='音乐盒 + 轻木梭,D 大调 6/8,像梭子来回穿经', bpm=bpm, meter='6/8', key='D 大调',
                bars=bars, beats_per_bar=beats_per_bar,
                tracks=[dict(name='旋律', inst='musicbox', gain=0.55, notes=mel), dict(name='音乐盒分解', inst='musicbox', gain=0.32, notes=mb),
                        dict(name='低音', inst='bass', gain=0.5, notes=bass), dict(name='梭子', inst='tick', gain=0.35, notes=tick)])


# ---------- 2. 黄铜机房(拨弦键琴 + 机械脉冲,A 小调 4/4)----------
def piece_brass():
    bpm, bpb, bars = 100, 4, 16
    prog = [('A', 'min'), ('F', 'maj'), ('C', 'maj'), ('G', 'maj'), ('A', 'min'), ('F', 'maj'), ('E', 'maj'), ('E', '7')]
    harp, bass, block, tick, mel = [], [], [], [], []
    s = 0.25
    for bar in range(bars):
        root, qual = prog[bar % 8]
        ch = chord(root, qual, 3)
        t0 = bar * bpb
        # 十六分分解 1-3-5-8-5-3 循环,后 8 小节改 1-5-3-8
        pat = [ch[0], ch[1], ch[2], ch[0] + 12, ch[2], ch[1]] if bar < 8 else [ch[0], ch[2], ch[1], ch[0] + 12]
        for i in range(16):
            n = pat[i % len(pat)]
            harp.append([round(t0 + i * s, 4), round(s * 1.1, 4), n, 0.5 if i % 4 == 0 else 0.33])
        bass.append([t0, 1.8, chord(root, qual, 2)[0], 0.8])
        bass.append([t0 + 2, 0.9, chord(root, qual, 2)[0], 0.55])
        bass.append([t0 + 3, 0.9, chord(root, qual, 2)[2], 0.5])
        block.append([t0 + 1, 0.1, 72, 0.5]); block.append([t0 + 3, 0.1, 72, 0.5])
        for i in range(8):
            tick.append([round(t0 + i * 0.5, 4), 0.05, 60, 0.3 if i % 2 == 0 else 0.15])
    # 旋律(A 小调),每 4 小节一句
    sc = [midi('A', 4), midi('B', 4), midi('C', 5), midi('D', 5), midi('E', 5), midi('F', 5), midi('G', 5), midi('A', 5), midi('B', 5), midi('C', 6)]
    lines = [
        [(0, 1, 7), (1, .5, 6), (1.5, .5, 5), (2, 1, 4), (3, 1, 2), (4, 1.5, 3), (5.5, .5, 4), (6, 2, 2), (8, 1, 0), (9, .5, 2), (9.5, .5, 4), (10, 1, 7), (11, 1, 6), (12, 3, 4)],
        [(0, 1, 4), (1, .5, 5), (1.5, .5, 4), (2, 1, 2), (3, 1, 0), (4, 1.5, 2), (5.5, .5, 3), (6, 2, 4), (8, 1, 7), (9, .5, 9), (9.5, .5, 7), (10, 1, 6), (11, 1, 4), (12, 2, 3), (14, 2, 1)],
        [(0, 1, 9), (1, .5, 7), (1.5, .5, 6), (2, 1, 4), (3, 1, 6), (4, 1.5, 7), (5.5, .5, 6), (6, 2, 4), (8, 1, 2), (9, .5, 4), (9.5, .5, 6), (10, 1, 5), (11, 1, 4), (12, 3, 3)],
        [(0, 1, 4), (1, .5, 3), (1.5, .5, 2), (2, 1, 3), (3, 1, 4), (4, 1.5, 2), (5.5, .5, 1), (6, 2, 0), (8, 1, 4), (9, .5, 3), (9.5, .5, 2), (10, 1, 1), (11, 1, 2), (12, 4, 0)],
    ]
    for li, line in enumerate(lines):
        for (st, ln, deg) in line:
            mel.append([round(li * 16 + st, 4), round(ln * 0.9, 4), sc[deg], 0.75 if st % 4 == 0 else 0.6])
    return dict(id='brass', name='黄铜机房', mood='拨弦键琴分解 + 机械脉冲,A 小调 4/4,齿轮匀速转着', bpm=bpm, meter='4/4', key='A 小调',
                bars=bars, beats_per_bar=bpb,
                tracks=[dict(name='旋律', inst='pluck', gain=0.5, notes=mel), dict(name='键琴分解', inst='harpsi', gain=0.3, notes=harp),
                        dict(name='低音', inst='bass', gain=0.55, notes=bass), dict(name='木块', inst='block', gain=0.3, notes=block),
                        dict(name='节拍', inst='tick', gain=0.25, notes=tick)])


# ---------- 3. 羊毛与雨(钢琴 + 铺底,C 大调 4/4,慢)----------
def piece_wool():
    bpm, bpb, bars = 64, 4, 12
    prog = [('C', 'maj7'), ('A', 'min7'), ('F', 'maj7'), ('G', '6'), ('E', 'min7'), ('A', 'min9'), ('F', 'maj7'), ('G', '6'),
            ('C', 'maj7'), ('E', 'min7'), ('F', 'maj7'), ('G', 'sus2')]
    piano, pad, bass, mel = [], [], [], []
    for bar in range(bars):
        root, qual = prog[bar]
        ch = chord(root, qual, 3)
        t0 = bar * bpb
        # 钢琴:1 拍柱式和弦(去根音),3.5 拍再一次轻的
        for n in ch[1:]:
            piano.append([t0, 2.8, n, 0.5])
            piano.append([t0 + 2.5, 1.4, n, 0.3])
        for n in ch[:3]:
            pad.append([t0, 4.0, n + 12, 0.35])
        bass.append([t0, 3.6, chord(root, qual, 2)[0], 0.6])
    sc = [midi('C', 5), midi('D', 5), midi('E', 5), midi('F', 5), midi('G', 5), midi('A', 5), midi('B', 5), midi('C', 6), midi('D', 6), midi('E', 6)]
    line = [(0, 3, 4), (3, 1, 5), (4, 2, 7), (6, 2, 5), (8, 3, 4), (11, 1, 2), (12, 4, 3),
            (16, 3, 2), (19, 1, 3), (20, 2, 4), (22, 2, 1), (24, 4, 0), (28, 4, 2),
            (32, 3, 7), (35, 1, 8), (36, 2, 9), (38, 2, 7), (40, 3, 5), (43, 1, 4), (44, 4, 4)]
    for (st, ln, deg) in line:
        mel.append([st, round(ln * 0.95, 4), sc[deg], 0.62])
    return dict(id='wool', name='羊毛与雨', mood='慢钢琴 + 柔和铺底,C 大调七和弦,窗外下着雨', bpm=bpm, meter='4/4', key='C 大调',
                bars=bars, beats_per_bar=bpb,
                tracks=[dict(name='旋律', inst='piano', gain=0.55, notes=mel), dict(name='钢琴和弦', inst='piano', gain=0.4, notes=piano),
                        dict(name='铺底', inst='pad', gain=0.28, notes=pad), dict(name='低音', inst='bass', gain=0.45, notes=bass)])


# ---------- 4. 齿轮华尔兹(G 大调 3/4)----------
def piece_waltz():
    bpm, bpb, bars = 132, 3, 24
    prog = [('G', 'maj'), ('G', 'maj'), ('D', '7'), ('D', '7'), ('G', 'maj'), ('E', 'min'), ('A', 'min'), ('D', '7'),
            ('G', 'maj'), ('B', 'min'), ('C', 'maj'), ('D', '7'), ('G', 'maj'), ('E', 'min'), ('A', 'min'), ('D', '7'),
            ('C', 'maj'), ('G', 'maj'), ('A', 'min'), ('D', '7'), ('G', 'maj'), ('C', 'maj'), ('D', '7'), ('G', 'maj')]
    bass, comp, mel, bell = [], [], [], []
    for bar in range(bars):
        root, qual = prog[bar]
        ch = chord(root, qual, 3)
        t0 = bar * bpb
        bass.append([t0, 0.8, chord(root, qual, 2)[0], 0.75])            # 嗡
        for b in (1, 2):                                                   # 啪 啪
            for n in ch[1:3] + [ch[0] + 12]:
                comp.append([t0 + b, 0.45, n, 0.32])
        if bar % 4 == 3:
            bell.append([t0 + 2, 1.0, ch[0] + 24, 0.4])
    sc = [midi('G', 4), midi('A', 4), midi('B', 4), midi('C', 5), midi('D', 5), midi('E', 5), midi('F#', 5), midi('G', 5), midi('A', 5), midi('B', 5)]
    line = [(0, 2, 4), (2, 1, 5), (3, 2, 6), (5, 1, 4), (6, 3, 7), (9, 3, 4),
            (12, 2, 2), (14, 1, 3), (15, 2, 4), (17, 1, 2), (18, 3, 1), (21, 3, 4),
            (24, 2, 4), (26, 1, 5), (27, 2, 6), (29, 1, 7), (30, 3, 8), (33, 3, 7),
            (36, 2, 5), (38, 1, 4), (39, 2, 3), (41, 1, 2), (42, 3, 4), (45, 3, 3),
            (48, 2, 7), (50, 1, 6), (51, 2, 5), (53, 1, 4), (54, 3, 2), (57, 3, 4),
            (60, 2, 3), (62, 1, 4), (63, 2, 5), (65, 1, 1), (66, 6, 0)]
    for (st, ln, deg) in line:
        mel.append([st, round(ln * 0.92, 4), sc[deg], 0.72 if st % 3 == 0 else 0.58])
    return dict(id='waltz', name='齿轮华尔兹', mood='拨弦旋律 + 嗡啪啪伴奏,G 大调 3/4,每四小节一声小铃', bpm=bpm, meter='3/4', key='G 大调',
                bars=bars, beats_per_bar=bpb,
                tracks=[dict(name='旋律', inst='pluck', gain=0.5, notes=mel), dict(name='伴奏', inst='harpsi', gain=0.28, notes=comp),
                        dict(name='低音', inst='bass', gain=0.5, notes=bass), dict(name='小铃', inst='bell', gain=0.35, notes=bell)])


# ---------- 5. 静语(E 小调持续音 + 稀疏铃,4/4 慢)----------
def piece_quiet():
    bpm, bpb, bars = 52, 4, 8
    drone, bell, tick, mel = [], [], [], []
    e_root = midi('E', 2)
    for bar in range(bars):
        t0 = bar * bpb
        drone.append([t0, 4.0, e_root, 0.5])
        drone.append([t0, 4.0, e_root + 7 if bar % 4 < 2 else e_root + 5, 0.32])
        drone.append([t0, 4.0, e_root + 12, 0.25])
        for i in range(4):
            tick.append([t0 + i, 0.06, 60, 0.12 if i else 0.2])
    # 五声(E G A B D)铃声,稀疏
    pent = [midi('E', 5), midi('G', 5), midi('A', 5), midi('B', 5), midi('D', 6), midi('E', 6), midi('G', 6)]
    line = [(0, 2, 0), (2.5, 1.5, 2), (4, 2, 3), (7, 1, 1), (8, 3, 0), (12, 2, 4), (14.5, 1.5, 3), (16, 2, 5), (19, 1, 4),
            (20, 3, 3), (24, 2, 1), (26.5, 1.5, 2), (28, 4, 0)]
    for (st, ln, deg) in line:
        bell.append([st, round(ln, 4), pent[deg], 0.5])
    for (st, ln, deg) in [(1, 3, 0), (9, 3, 2), (17, 3, 1), (25, 3, 0)]:
        mel.append([st, ln, pent[deg] - 12, 0.4])
    return dict(id='quiet', name='静语', mood='E 小调持续低音 + 稀疏五声铃,4/4 很慢,只有织机偶尔一响', bpm=bpm, meter='4/4', key='E 小调',
                bars=bars, beats_per_bar=bpb,
                tracks=[dict(name='铃', inst='bell', gain=0.5, notes=bell), dict(name='低铃', inst='musicbox', gain=0.35, notes=mel),
                        dict(name='持续音', inst='drone', gain=0.4, notes=drone), dict(name='织机', inst='tick', gain=0.2, notes=tick)])


for p in (piece_shuttle(), piece_brass(), piece_wool(), piece_waltz(), piece_quiet()):
    p['duration'] = round(p['bars'] * p['beats_per_bar'] * 60 / p['bpm'], 2)
    p['note_count'] = sum(len(t['notes']) for t in p['tracks'])
    pieces.append(p)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'compositions.json')
json.dump(pieces, open(out, 'w'), ensure_ascii=False)
for p in pieces:
    print(p['id'], p['name'], p['duration'], 's', p['note_count'], 'notes')
