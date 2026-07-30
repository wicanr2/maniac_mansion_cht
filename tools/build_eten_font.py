#!/usr/bin/env python3
"""用倚天中文系統 (ETEN 3.53) 的 16x15 原生點陣字烘 chinese_gb16x12.fnt。

1990 年代 DOS 中文長什麼樣，倚天就長什麼樣——這是為 15 點手工調過的點陣字，
比把 TTF 輪廓縮到這個尺寸清楚得多。

檔案格式（依 ScummVM engines/scumm/charset.cpp loadCJKFont 推導）：
    無檔頭，緊接 numChar 個字形，每字 ((_2byteWidth+7)/8) * _2byteHeight
    = 2 * 15 = 30 bytes，每列 2 bytes、MSB-first、由上而下。

這個 stride 與倚天 STDFONT.15 / SPCFONT.15 的原生格式**完全相同**，
所以漢字與標點都是直接搬 30 bytes，不做任何縮放或重新取樣。

字形位置 idx = (lead - 0x88) * 93 + (trail - 0xA1)，見 cht_codec.py。

[雷] STDFONT.15 從 A440（「一」）起算，**不含**全形標點（A140-A3BF）。
只帶 STDFONT 去烘，「，。！？「」（）《》」全都會缺字，所以一定要一起帶
SPCFONT.15（與補充區 SPCFSUPP.15）。
"""

import argparse
import json
import sys

from cht_codec import CAPACITY, font_index
from eten_font import DIM15, STRIDE15, EtenFont, embolden

GLYPH_BYTES = STRIDE15   # 30


def rows_to_bytes(rows):
    out = bytearray()
    for r in rows:
        v = 0
        for x in range(DIM15[0]):
            v |= r[x] << (15 - x)
        out += bytes(((v >> 8) & 0xFF, v & 0xFF))
    return bytes(out)


def ttf_glyph(face, ch):
    """Big5 缺字時的備援：從 TTF 描 16x15。"""
    import freetype
    face.set_pixel_sizes(0, DIM15[1])
    face.load_char(ch, freetype.FT_LOAD_RENDER |
                   freetype.FT_LOAD_TARGET_MONO |
                   freetype.FT_LOAD_MONOCHROME)
    bm = face.glyph.bitmap
    rows = [[0] * DIM15[0] for _ in range(DIM15[1])]
    y0 = DIM15[1] - 3 - face.glyph.bitmap_top
    x0 = face.glyph.bitmap_left
    for y in range(bm.rows):
        ty = y0 + y
        if not 0 <= ty < DIM15[1]:
            continue
        for x in range(bm.width):
            tx = x0 + x
            if not 0 <= tx < DIM15[0]:
                continue
            if bm.buffer[y * bm.pitch + (x >> 3)] & (0x80 >> (x & 7)):
                rows[ty][tx] = 1
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("table", help="cht_table.json")
    ap.add_argument("-o", "--out", default="chinese_gb16x12.fnt")
    ap.add_argument("--eten-dir", default="font-src",
                    help="放 STDFONT.15 / SPCFONT.15 / SPCFSUPP.15 的目錄")
    ap.add_argument("--embolden", action="store_true",
                    help="程式加粗（15 點只有偏細的明體；每列與左移一格 OR）")
    ap.add_argument("--fallback-ttf",
                    default="/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
                    help="Big5 缺字時的備援字型")
    ap.add_argument("--preview")
    args = ap.parse_args()

    table = json.load(open(args.table, encoding="utf-8"))
    d = args.eten_dir
    eten = EtenFont(f"{d}/STDFONT.15", f"{d}/SPCFONT.15", f"{d}/SPCFSUPP.15")

    blob = bytearray(GLYPH_BYTES * CAPACITY)
    fallback = []
    face = None

    for ch, (lead, trail) in table.items():
        rows = eten.bitmap(ch)
        if rows is None:
            if face is None:
                import freetype
                face = freetype.Face(args.fallback_ttf, 0)
            rows = ttf_glyph(face, ch)
            fallback.append(ch)
        elif args.embolden:
            rows = embolden(rows)
        off = font_index(lead, trail) * GLYPH_BYTES
        blob[off:off + GLYPH_BYTES] = rows_to_bytes(rows)

    open(args.out, "wb").write(blob)
    print(f"字型 {args.out}：{len(table)} 字 / 容量 {CAPACITY}，{len(blob)} bytes"
          f"（16x15，每字 {GLYPH_BYTES} bytes）")
    if fallback:
        # fallback 數量是品質指標：一大批掉進 fallback 就先懷疑索引公式或漏帶 SPCFONT
        print(f"Big5 缺字 {len(fallback)} 字（{len(fallback)*100/len(table):.2f}%），"
              f"改用 {args.fallback_ttf} 描：{''.join(fallback)}", file=sys.stderr)

    if args.preview:
        from PIL import Image
        chars = sorted(table)
        cols = 24
        rows_n = (len(chars) + cols - 1) // cols
        img = Image.new("1", (cols * DIM15[0], rows_n * DIM15[1]))
        px = img.load()
        for i, ch in enumerate(chars):
            lead, trail = table[ch]
            off = font_index(lead, trail) * GLYPH_BYTES
            gx, gy = (i % cols) * DIM15[0], (i // cols) * DIM15[1]
            for y in range(DIM15[1]):
                v = (blob[off + 2 * y] << 8) | blob[off + 2 * y + 1]
                for x in range(DIM15[0]):
                    if v & (1 << (15 - x)):
                        px[gx + x, gy + y] = 1
        img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(args.preview)
        print(f"預覽 → {args.preview}")


if __name__ == "__main__":
    main()
