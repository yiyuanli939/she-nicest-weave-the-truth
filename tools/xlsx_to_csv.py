#!/usr/bin/env python3
"""把策划的剧情 xlsx(sheet1)原样转成 CSV,供 tools/import_dialogue.gd 读取。

只做格式转换,不做任何语义处理(表头别名/关卡映射/「无」等都在 import_dialogue.gd 里,
那边是纯函数、有 headless 测试)。零第三方依赖(标准库 zipfile + ElementTree)。
唯一的例外:英文台词列「语句_en」只在 CSV 里(策划的 xlsx 没有)—— 若 xlsx 没有这一列而旧 CSV 有,
按(关卡, 发言人, 语句)把旧译文并回新表(台词改了的句子译文留空,等重译),否则重导一次 xlsx 就把译文冲掉了。

用法:
    python3 tools/xlsx_to_csv.py [xlsx路径] [输出csv路径]
默认:剧情文件及美术补充/静语纹_四章剧情_无旁白版_v2.xlsx → information/dialogue.csv
"""
import re
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"

DEFAULT_XLSX = "剧情文件及美术补充/静语纹_四章剧情_无旁白版_v2.xlsx"
DEFAULT_OUT = "information/dialogue.csv"


def col_index(ref: str) -> int:
    """单元格引用 'C7' → 0 起的列号 2。"""
    letters = re.match(r"[A-Z]+", ref).group(0)
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - ord("A") + 1)
    return n - 1


def cell_text(c, shared):
    t = c.get("t")
    v = c.find(NS + "v")
    if t == "s" and v is not None:
        return shared[int(v.text)]
    if t == "inlineStr":
        is_el = c.find(NS + "is")
        return "".join(el.text or "" for el in is_el.iter(NS + "t")) if is_el is not None else ""
    return v.text if v is not None and v.text is not None else ""


def read_rows(path: str):
    z = zipfile.ZipFile(path)
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall(NS + "si"):
            shared.append("".join(t.text or "" for t in si.iter(NS + "t")))
    # 第一张工作表(workbook 顺序)
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = {r.get("Id"): r.get("Target") for r in ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))}
    first = wb.find(NS + "sheets")[0]
    target = rels[first.get(REL + "id")]
    if not target.startswith("xl/"):
        target = "xl/" + target
    rows = []
    for row in ET.fromstring(z.read(target)).iter(NS + "row"):
        cells = {}
        for c in row.findall(NS + "c"):
            cells[col_index(c.get("r"))] = cell_text(c, shared)
        rows.append(cells)
    width = max((max(r) + 1 for r in rows if r), default=0)
    return [[r.get(i, "") for i in range(width)] for r in rows]


def csv_field(s: str) -> str:
    if any(ch in s for ch in ',"\n\r'):
        return '"' + s.replace('"', '""') + '"'
    return s


EN_COLS = ("语句_en", "台词_en", "英文语句", "英文台词")
KEY_COLS = (("关卡", "关卡id"), ("发言人",), ("语句", "台词"))


def header_index(rows):
    """表头行号(含「发言人」与「语句/台词」的第一行),找不到 -1。"""
    for i, r in enumerate(rows):
        if "发言人" in r and any(c in r for c in ("语句", "台词")):
            return i
    return -1


def col_of(header, names):
    for n in names:
        if n in header:
            return header.index(n)
    return -1


def merge_english(rows, old_csv: str):
    """xlsx 没有英文列时,把旧 CSV 的英文列按(关卡, 发言人, 语句)并回来;返回新 rows(可能加了一列)。"""
    import csv
    h = header_index(rows)
    if h < 0 or col_of(rows[h], EN_COLS) >= 0 or not Path(old_csv).is_file():
        return rows
    with open(old_csv, encoding="utf-8-sig", newline="") as f:
        old = list(csv.reader(f))
    oh = header_index(old)
    if oh < 0 or col_of(old[oh], EN_COLS) < 0:
        return rows
    oe = col_of(old[oh], EN_COLS)
    okeys = [col_of(old[oh], n) for n in KEY_COLS]
    if min(okeys) < 0:
        return rows
    def key(r, idx):
        return tuple(r[i].strip() if i < len(r) else "" for i in idx)
    old_en = {key(r, okeys): (r[oe] if oe < len(r) else "") for r in old[oh + 1:] if any(x.strip() for x in r)}
    nkeys = [col_of(rows[h], n) for n in KEY_COLS]
    if min(nkeys) < 0:
        return rows
    merged = []
    for i, r in enumerate(rows):
        r = list(r)
        if i < h:
            r.append("")
        elif i == h:
            r.append("语句_en")
        else:
            r.append(old_en.get(key(r, nkeys), "") if any(x.strip() for x in r) else "")
        merged.append(r)
    return merged


def main() -> int:
    xlsx = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_XLSX
    out = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT
    rows = merge_english(read_rows(xlsx), out)
    text = "\n".join(",".join(csv_field(v) for v in row) for row in rows) + "\n"
    # newline="" 关掉平台换行翻译:Windows 文本模式会把 \n 写成 \r\n(若源串用 \r\n 更会翻成 \r\r\n)。
    # 统一写 LF,git 也不再做 CRLF 归一化;importer 的 split_rows 对 \r\n / \n 都认。
    with open(out, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print(f"{xlsx} → {out}:{len(rows)} 行")
    return 0


if __name__ == "__main__":
    sys.exit(main())
