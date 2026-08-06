#!/usr/bin/env python3
"""把 Maniac Mansion Deluxe 指令列的九顆按鈕烘成中文圖，寫進 acsprset.spr。

**為什麼要動圖不能只改翻譯**：那九顆按鈕是 CLIB 裡的手繪 sprite（40×14／64×14、
16-bit），`.tra` 只能換「用哪一號 sprite」，換不出中文字形。遊戲自己內建 15 種語言，
每種一組 18 張（9 個動詞 × 一般/反白），例如德文在 788–805、俄文在 924–941——
俄文那組證明非拉丁字母本來就行得通。

**原圖的構造**（`ags_spr.py` 把 sprite 1 印成字元圖看出來的）：

    第 0 欄與最後一欄是 0xF81F（洋紅＝透明），其餘填 0x1001（近黑背景），
    字是 0x0211（藍）或 0xFC64（橘），字的右下 +1,+1 有一層 0x4008 的暗紫陰影。
    一般／反白兩張除了字的顏色以外像素完全相同。

所以這裡就照著同一套規則畫中文：12×12 的 WQY Zen Hei Sharp **embedded bitmap**
（跟 v2 原版那支 `build_cht_font.py` 同一個來源，12px 下 outline 描出來像雜訊），
置中排進原尺寸的畫布，補上同樣的陰影。畫面上這些 sprite 會被引擎放大兩倍
（640×400 legacy hi-res），所以 12×12 的字實際看到的是 24×24。

用法：
    make_deluxe_buttons.py <來源 acsprset.spr> -o <輸出.spr> [--preview 圖.png]
"""

import argparse
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ags_spr import SpriteFile

import freetype

# 原圖用色（16-bit RGB565）
BG = 0x1001          # 近黑背景
FG_NORMAL = 0x0211   # 藍
FG_HILITE = 0xFC64   # 橘
SHADOW = 0x4008      # 暗紫，字的右下 +1,+1
TRANSP = 0xF81F      # 洋紅＝透明

GLYPH = 12

# 動詞：中文字 → (一般圖槽, 反白圖槽)。預設沿用英文那一組的槽號，
# 這樣 .tra 的 a_button_* 不必動；用 --append 則改成接在檔尾。
VERBS = [
    ("a_button_give",     "給",   1, 2),
    ("a_button_pick_up",  "拿起", 7, 8),
    ("a_button_use",      "使用", 13, 14),
    ("a_button_open",     "打開", 3, 4),
    ("a_button_look_at",  "查看", 9, 10),
    ("a_button_push",     "推",   15, 28),
    ("a_button_close",    "關上", 5, 6),
    ("a_button_talk_to",  "交談", 11, 12),
    ("a_button_pull",     "拉",   29, 30),
]


def load_face(path="/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc", index=2):
    face = freetype.Face(path, index)
    sizes = [s.height for s in face.available_sizes]
    if GLYPH not in sizes:
        raise SystemExit(f"face {index} 的 strike 高度是 {sizes}，找不到 {GLYPH}px")
    face.select_size(sizes.index(GLYPH))
    return face


def glyph_bits(face, ch):
    """回傳 12x12 的 bool 矩陣。"""
    face.load_char(ch, freetype.FT_LOAD_RENDER | freetype.FT_LOAD_TARGET_MONO)
    bm = face.glyph.bitmap
    rows, width, pitch = bm.rows, bm.width, bm.pitch
    top, left = face.glyph.bitmap_top, face.glyph.bitmap_left
    out = [[False] * GLYPH for _ in range(GLYPH)]
    # 12px strike 的基線在第 10 列
    y0 = 10 - top
    for r in range(rows):
        y = y0 + r
        if not (0 <= y < GLYPH):
            continue
        for c in range(width):
            x = left + c
            if not (0 <= x < GLYPH):
                continue
            if bm.buffer[r * pitch + (c >> 3)] & (0x80 >> (c & 7)):
                out[y][x] = True
    return out


def render_button(face, text, w, h, fg):
    """畫一張 w×h 的按鈕，回傳 RGB565 的 bytes。"""
    px = [[BG] * w for _ in range(h)]
    for y in range(h):
        px[y][0] = TRANSP
        px[y][w - 1] = TRANSP

    bits = [glyph_bits(face, ch) for ch in text]
    total = len(bits) * GLYPH
    x0 = (w - total) // 2
    y0 = (h - GLYPH) // 2

    def put(x, y, colour):
        if 1 <= x < w - 1 and 0 <= y < h:
            px[y][x] = colour

    for i, g in enumerate(bits):           # 先畫陰影，字才蓋得過去
        for gy in range(GLYPH):
            for gx in range(GLYPH):
                if g[gy][gx]:
                    put(x0 + i * GLYPH + gx + 1, y0 + gy + 1, SHADOW)
    for i, g in enumerate(bits):
        for gy in range(GLYPH):
            for gx in range(GLYPH):
                if g[gy][gx]:
                    put(x0 + i * GLYPH + gx, y0 + gy, fg)

    buf = bytearray()
    for row in px:
        for v in row:
            buf += struct.pack("<H", v)
    return bytes(buf)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help="來源 acsprset.spr（用 ags_clib.py 從 Maniac.exe 抽出來）")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--font", default="/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc")
    ap.add_argument("--face", type=int, default=2)
    ap.add_argument("--append", action="store_true",
                    help="把中文圖接在檔尾（不動原本的槽），槽號印出來給 .tra 用")
    ap.add_argument("--preview", help="另存一張對照圖")
    ap.add_argument("--export-pack",
                    help="另外輸出一個只含這 18 張圖的小檔（我們自己的美術，可隨 patch 版散布）")
    a = ap.parse_args()

    sf = SpriteFile(a.src)
    face = load_face(a.font, a.face)

    repl = {}
    mapping = []
    next_slot = sf.topmost + 1
    for name, text, n_slot, h_slot in VERBS:
        if a.append:
            n_slot, h_slot = next_slot, next_slot + 1
            next_slot += 2
            w, h = 40, 14
        else:
            _, _, w, h, _, _ = sf.sprites[n_slot]
        repl[n_slot] = (2, w, h, render_button(face, text, w, h, FG_NORMAL))
        repl[h_slot] = (2, w, h, render_button(face, text, w, h, FG_HILITE))
        mapping.append((name, text, n_slot, h_slot, w, h))

    data = sf.replace(repl, topmost=next_slot - 1 if a.append else None)
    open(a.out, "wb").write(data)

    print(f"{a.out}（{len(data):,} bytes）")
    for name, text, n, hl, w, h in mapping:
        print(f"  {name:<20} {text:<3} 一般={n:<5} 反白={hl:<5} {w}x{h}")

    if a.export_pack:
        # 只裝我們自己畫的那 18 張，不含任何遊戲美術，所以 patch 版可以帶著走。
        # 格式：magic + 張數，接著每張 (槽號, w, h, bpp, 長度, 資料)
        pack = bytearray(b"MMCHTBTN\x01")
        pack += struct.pack("<H", len(repl))
        for idx in sorted(repl):
            bpp, w, h, buf = repl[idx]
            pack += struct.pack("<HHHBI", idx, w, h, bpp, len(buf)) + buf
        open(a.export_pack, "wb").write(pack)
        print(f"按鈕圖包 → {a.export_pack}（{len(pack):,} bytes，{len(repl)} 張）")

    if a.preview:
        from PIL import Image
        sf2 = SpriteFile(a.out)
        ims = []
        for _, _, n, hl, _, _ in mapping:
            ims += [sf2.to_image(n), sf2.to_image(hl)]
        wmax = max(i.size[0] for i in ims)
        sheet = Image.new("RGB", (wmax * 2 + 12, (14 + 3) * len(mapping)), (16, 16, 24))
        for k in range(0, len(ims), 2):
            sheet.paste(ims[k], (0, (k // 2) * 17))
            sheet.paste(ims[k + 1], (wmax + 8, (k // 2) * 17))
        sheet = sheet.resize((sheet.size[0] * 3, sheet.size[1] * 3), Image.NEAREST)
        sheet.save(a.preview)
        print(f"對照圖 → {a.preview}")


if __name__ == "__main__":
    main()
