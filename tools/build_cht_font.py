#!/usr/bin/env python3
"""烘 12x12 中文點陣字型（chinese_gb16x12.fnt）給 patched ScummVM 用。

字形來源是 WenQuanYi Zen Hei Sharp 的 **embedded bitmap**（TTC face 2 的 12px
strike），不是用 TTF outline 去 rasterize。12px 下 outline 描出來的筆畫太細、
看起來像雜訊；Zen Hei Sharp 的 12px strike 是設計師手繪點陣，清晰得多。

檔案格式（依 ScummVM engines/scumm/charset.cpp loadCJKFont 推導）：
  無檔頭，緊接 numChar 個字形，每字 ((width+7)/8) * height = 2 * 12 = 24 bytes。
  每列 2 bytes（高位在前），只用左邊 12 bit。
  字形位置 idx = (lead - 0x80) * 93 + (trail - 0xA1)，見 cht_codec.py。
"""

import argparse
import json
import sys

import freetype

from cht_codec import CAPACITY, font_index

WIDTH, HEIGHT = 12, 12
GLYPH_BYTES = ((WIDTH + 7) // 8) * HEIGHT   # 24
BASELINE = 10   # 12px strike 的 bitmap_top 對齊點


def load_face(path, index):
    face = freetype.Face(path, index)
    if not face.available_sizes:
        raise SystemExit(f"{path} face {index} 沒有 embedded bitmap strike")
    sizes = [s.height for s in face.available_sizes]
    if HEIGHT not in sizes:
        raise SystemExit(f"face {index} 的 strike 高度是 {sizes}，找不到 {HEIGHT}px")
    face.select_size(sizes.index(HEIGHT))
    return face


def render(face, ch):
    """回傳 24 bytes 的字形；描不出來回 None。"""
    face.load_char(ch, freetype.FT_LOAD_RENDER |
                   freetype.FT_LOAD_TARGET_MONO |
                   freetype.FT_LOAD_MONOCHROME)
    bm = face.glyph.bitmap
    if bm.width == 0 or bm.rows == 0:
        return None
    rows = [[0] * WIDTH for _ in range(HEIGHT)]
    y0 = BASELINE - face.glyph.bitmap_top
    x0 = face.glyph.bitmap_left
    for y in range(bm.rows):
        ty = y0 + y
        if not 0 <= ty < HEIGHT:
            continue
        for x in range(bm.width):
            tx = x0 + x
            if not 0 <= tx < WIDTH:
                continue
            if bm.buffer[y * bm.pitch + (x >> 3)] & (0x80 >> (x & 7)):
                rows[ty][tx] = 1
    out = bytearray()
    for r in rows:
        v = 0
        for x in range(WIDTH):
            v |= r[x] << (15 - x)
        out += bytes(((v >> 8) & 0xFF, v & 0xFF))
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("table", help="cht_table.json")
    ap.add_argument("-o", "--out", default="chinese_gb16x12.fnt")
    ap.add_argument("--font", default="/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc")
    ap.add_argument("--face", type=int, default=2, help="2 = Zen Hei Sharp")
    ap.add_argument("--preview", help="另存一張 PNG 預覽（需要 PIL）")
    args = ap.parse_args()

    table = json.load(open(args.table, encoding="utf-8"))
    face = load_face(args.font, args.face)

    blob = bytearray(GLYPH_BYTES * CAPACITY)
    missing = []
    for ch, (lead, trail) in table.items():
        g = render(face, ch)
        if g is None:
            missing.append(ch)
            continue
        off = font_index(lead, trail) * GLYPH_BYTES
        blob[off:off + GLYPH_BYTES] = g

    open(args.out, "wb").write(blob)
    print(f"字型 {args.out}：{len(table)} 字寫入 / 容量 {CAPACITY}，"
          f"{len(blob)} bytes")
    if missing:
        print(f"字形缺漏 {len(missing)} 字：{''.join(missing)}", file=sys.stderr)
        sys.exit(1)

    if args.preview:
        from PIL import Image
        chars = sorted(table)
        cols = 32
        rows = (len(chars) + cols - 1) // cols
        img = Image.new("1", (cols * WIDTH, rows * HEIGHT))
        px = img.load()
        for i, ch in enumerate(chars):
            lead, trail = table[ch]
            off = font_index(lead, trail) * GLYPH_BYTES
            gx, gy = (i % cols) * WIDTH, (i // cols) * HEIGHT
            for y in range(HEIGHT):
                v = (blob[off + 2 * y] << 8) | blob[off + 2 * y + 1]
                for x in range(WIDTH):
                    if v & (1 << (15 - x)):
                        px[gx + x, gy + y] = 1
        img.resize((img.width * 3, img.height * 3), Image.NEAREST).save(args.preview)
        print(f"預覽 → {args.preview}")


if __name__ == "__main__":
    main()
