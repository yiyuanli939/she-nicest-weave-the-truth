#!/usr/bin/env python3
"""把策划的剧情 xlsx(sheet1)原样转成 CSV,供 tools/import_dialogue.gd 读取。

只做格式转换,不做任何语义处理(表头别名/关卡映射/「无」等都在 import_dialogue.gd 里,
那边是纯函数、有 headless 测试)。零第三方依赖(标准库 zipfile + ElementTree)。

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


def main() -> int:
    xlsx = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_XLSX
    out = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT
    rows = read_rows(xlsx)
    text = "\r\n".join(",".join(csv_field(v) for v in row) for row in rows) + "\r\n"
    Path(out).write_text(text, encoding="utf-8")
    print(f"{xlsx} → {out}:{len(rows)} 行")
    return 0


if __name__ == "__main__":
    sys.exit(main())
