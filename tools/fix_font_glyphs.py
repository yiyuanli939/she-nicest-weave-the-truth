#!/usr/bin/env python3
"""剥掉站酷小薇体里的坏字形,让这些字自动走系统兜底字体(mac 苹方 / Windows 雅黑)。

背景:字体里「回」(U+56DE) 的字形是一个实心块(渲染检测:墨水占比 0.35,中位数 0.16 的两倍;
220px 大字号下肉眼可见实心方块,而同结构的 田因固国图 全部正常)。has_char 查不出这种坏字形
(字体声称有映射),所以从 cmap 里删掉映射 → Godot 判定缺字 → 走 FontVariation 的系统兜底,
两个平台都能正常显示,只是该字风格与站酷小薇略异。

用法(改动会覆盖 ttf,原件备份为 .ttf.bak,重跑幂等):
    pip3 install fonttools
    python3 tools/fix_font_glyphs.py
改完后跑 `godot --headless --path . --import` 重导入,并同步 tests/test_theme.gd 的
ALLOWED_FALLBACK 列表(该测试保证其余全部可见文字都在打包字体里)。
"""
import shutil
from pathlib import Path

from fontTools.ttLib import TTFont

FONT = Path(__file__).resolve().parent.parent / "assets/fonts/ZCOOLXiaoWei-Regular.ttf"
BACKUP = FONT.with_suffix(".ttf.bak")   # .bak 后缀避开 Godot 资源导入(不进导出包)
BAD_CODEPOINTS = [0x56DE]   # 回:字形是实心块

if not BACKUP.exists():
    shutil.copy2(FONT, BACKUP)
    print(f"原件备份 -> {BACKUP.name}")

font = TTFont(str(BACKUP))   # 始终从原件出发,重跑幂等
removed = []
for table in font["cmap"].tables:
    for cp in BAD_CODEPOINTS:
        if cp in table.cmap:
            del table.cmap[cp]
            removed.append(cp)
font.save(str(FONT))
print(f"已从 cmap 移除 {sorted(set(removed))} -> {FONT.name}")
for cp in BAD_CODEPOINTS:
    assert cp not in font.getBestCmap(), f"U+{cp:04X} 仍在 cmap"
print("校验通过:坏字形已剥离,这些字将走系统兜底字体")
