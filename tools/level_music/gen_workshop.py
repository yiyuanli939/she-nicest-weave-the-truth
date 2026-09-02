"""把 out/ 里的渲染结果 + 报告嵌进 workshop.tpl.html → out/level_music.html(发布为 artifact)"""
import json, os, base64
HERE = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(HERE, 'out')
P = json.load(open(os.path.join(out, 'compositions.json')))
for p in P:
    mp3 = os.path.join(out, p['id'] + '.mp3')
    p['src'] = 'data:audio/mpeg;base64,' + base64.b64encode(open(mp3, 'rb').read()).decode()
    p.pop('voicings', None)
tpl = open(os.path.join(HERE, 'workshop.tpl.html'), encoding='utf-8').read()
html = tpl.replace('__DATA__', json.dumps(P, ensure_ascii=False).replace('</', '<\\/'))
open(os.path.join(out, 'level_music.html'), 'w', encoding='utf-8').write(html)
print(len(html) // 1024, 'KB')
