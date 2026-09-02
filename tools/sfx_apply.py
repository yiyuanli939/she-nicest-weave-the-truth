#!/usr/bin/env python3
"""把候选音效装进游戏:hardware/.venv/bin/python tools/sfx_apply.py <方案|选择结果文件> [--no-import] [--test]
  方案 = K / D / A / B / C / S(assets/sfx/候选/ 下的整套,每槽位第 1 候选);
  选择结果文件 = 试听台「复制选择结果」贴出来的文本,每行 `槽位: 路径   # 说明`,路径可写 `A_黄铜机械/click.ogg`
  或 `assets/sfx/click.ogg`;写「(未选)」的槽位保持现状。
做的事:复制到 assets/sfx/<槽位>.<后缀>(后缀变了就删旧文件与 .import 并改 game/sfx.gd CLIPS 那一行;共用文件的槽位跟着主槽位走),
`godot --headless --import`,跑 tools/sfx_audit.py 把建议 dB 写进 GAIN_DB(hover 固定 -4、win 不高于 -5),`--test` 再跑 headless 全量。
退出码:0 成功;1 有刺耳 / 缺失(仍已装上,请看审计输出)。"""
import os, re, sys, shutil, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_GD = os.path.join(ROOT, 'game', 'sfx.gd')
DST = os.path.join(ROOT, 'assets', 'sfx')
CAND = os.path.join(DST, '候选')
SETS = {'K': None, 'D': 'D_合成', 'A': 'A_黄铜机械', 'B': 'B_纸布柔和', 'C': 'C_柔和界面', 'S': 'S_Sonniss样例'}
GODOT = '/Applications/Godot.app/Contents/MacOS/Godot'
PY = os.path.join(ROOT, 'hardware', '.venv', 'bin', 'python')
EXTS = ('.ogg', '.wav', '.mp3')


def read_clips():
    src = open(SFX_GD, encoding='utf-8').read()
    body = src.split('const CLIPS')[1].split('\n}')[0]
    return [(m.group(1), m.group(2)) for m in re.finditer(r'&"([a-z_]+)":\s*"(res://[^"]*)"', body)]


def find_candidate(setdir, slot):
    for ext in EXTS:
        p = os.path.join(CAND, setdir, slot + ext)
        if os.path.exists(p):
            return p
    return None


def parse_selection(path):
    out = {}
    for line in open(path, encoding='utf-8'):
        m = re.match(r'\s*([a-z_]+)\s*:\s*(\S+)', line)
        if not m or m.group(2).startswith('(') or m.group(2).startswith('（'):
            continue
        rel = m.group(2)
        p = os.path.join(CAND, rel) if not rel.startswith('assets/') else os.path.join(ROOT, rel)
        if os.path.exists(p):
            out[m.group(1)] = p
        else:
            print('找不到', rel)
    return out


def main(argv):
    if not argv:
        print(__doc__); return 2
    arg = argv[0]
    do_import = '--no-import' not in argv
    do_test = '--test' in argv
    if arg.upper() in SETS and len(arg) == 1:
        setdir = SETS[arg.upper()]
        if setdir is None:
            print('K = 现用 Kenney 套,不用复制'); chosen = {}
        else:
            chosen = {}
            for slot, _ in read_clips():
                p = find_candidate(setdir, slot)
                if p:
                    chosen[slot] = p
    else:
        chosen = parse_selection(arg)
    clips = read_clips()
    primary = {}     # 文件名(不含后缀)→ 主槽位(共用文件的槽位跟主槽位走)
    for slot, res in clips:
        stem = os.path.splitext(os.path.basename(res))[0]
        primary.setdefault(stem, slot)
    src_gd = open(SFX_GD, encoding='utf-8').read()
    changed = 0
    for slot, res in clips:
        stem = os.path.splitext(os.path.basename(res))[0]
        p = chosen.get(slot)
        if p is None or primary.get(stem) != slot and chosen.get(primary.get(stem)) is not None:
            continue   # 没选 / 共用文件由主槽位处理
        ext = os.path.splitext(p)[1].lower()
        old_ext = os.path.splitext(res)[1].lower()
        target = os.path.join(DST, stem + ext)
        shutil.copy(p, target)
        changed += 1
        if ext != old_ext:
            for e in EXTS:
                if e != ext:
                    for f in (os.path.join(DST, stem + e), os.path.join(DST, stem + e + '.import')):
                        if os.path.exists(f):
                            os.remove(f)
            src_gd = src_gd.replace('"res://assets/sfx/%s%s"' % (stem, old_ext), '"res://assets/sfx/%s%s"' % (stem, ext))
    open(SFX_GD, 'w', encoding='utf-8').write(src_gd)
    print('复制了 %d 个文件' % changed)
    if do_import:
        subprocess.run([GODOT, '--headless', '--path', ROOT, '--import'], capture_output=True, timeout=600)
    audit = subprocess.run([PY, os.path.join(ROOT, 'tools', 'sfx_audit.py')], capture_output=True, text=True, cwd=ROOT)
    print(audit.stdout)
    rows = [l.split() for l in audit.stdout.splitlines()[1:] if re.match(r'^[a-z_]+\s+\d', l)]
    gain = {r[0]: float(r[7]) for r in rows}
    if 'hover' in gain: gain['hover'] = -4.0
    if 'win' in gain: gain['win'] = min(gain['win'], -5.0)
    lines, cur = [], []
    for r in rows:
        cur.append('&"%s": %.1f' % (r[0], gain[r[0]]))
        if len(cur) == 6:
            lines.append('\t' + ', '.join(cur) + ','); cur = []
    if cur:
        lines.append('\t' + ', '.join(cur) + ',')
    table = 'const GAIN_DB: Dictionary = {\n' + '\n'.join(lines) + '\n}'
    src_gd = open(SFX_GD, encoding='utf-8').read()
    src_gd = re.sub(r'const GAIN_DB: Dictionary = \{.*?\n\}', table, src_gd, flags=re.S)
    open(SFX_GD, 'w', encoding='utf-8').write(src_gd)
    print('GAIN_DB 已重生成(%d 槽位)' % len(gain))
    rc = audit.returncode
    if do_test:
        t = subprocess.run([GODOT, '--headless', '--path', ROOT, '--script', 'res://tests/run_tests.gd'], capture_output=True, text=True, timeout=900)
        tail = [l for l in t.stdout.splitlines() if '———' in l or '✗' in l]
        print('\n'.join(tail[-5:]))
        rc = rc or t.returncode
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
