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

所以這裡就照著同一套規則畫中文，置中排進原尺寸的畫布，補上同樣的陰影。畫面上這些
sprite 會被引擎以最近鄰放大兩倍（640×400 legacy hi-res），所以每個畫下去的像素在螢幕上
是 2×2 的方塊 —— 沒有抗鋸齒可用，只有黑白取捨。

**選型**（掃過 6 種字型 × size 12–14 × 門檻 × 字距 × 跳動，約 60 組逐張比對後定案）：

* **WQY Zen Hei 的 outline（face 0）14px、門檻 100**。字高跟英文一樣填滿按鈕；
  outline 光柵化下直筆 2px、橫筆 1px，**粗細不勻**正好對上英文那種手繪不勻感——
  點陣 strike 太工整反而做不出來。
* **字距 10**：原版英文把整顆按鈕填到 97%，中文兩個字置中只有 74%，並排看差很多。
* **`--jitter 1,0`**：第一個字掉 1px，做出英文那種基線上下跳。
* 落選的：華康少女文字／王漢宗波浪／海報體在 12–14px 結構崩壞（門框被打斷、筆畫黏死），
  華康超圓體的「關」內部糊成一塊，古印體只有 Big5 cmap（Unicode 查不到字）。
  判準是拿「關」（19 畫）、「談」、「查」逐格檢查筆畫之間有沒有留下背景像素，不靠肉眼。

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

# hi-res 版：遊戲裡 877–911 有一組**沒有任何語言在用的日文假名按鈕**
# （わたす／とる／つかう／あける／みる／おす／しめる／はなす／ひく），
# 尺寸剛好是英文那組的兩倍（80×28 / 128×28），而且 ac2game.dta 裡這 18 個槽
# 已經標了 SPF_HIRES —— 引擎因此以 1:1 畫它們（見 engine/ac/sprite.cpp
# get_new_size_for_sprite：旗標與遊戲解析度一致時直接原尺寸回傳），
# 等於同樣的螢幕面積換到兩倍解析度，中文可以用 24×24 而不是 12×12。
# 順序與寬窄和英文那組完全對應，所以只要照抄配對即可。
VERBS_HIRES = [
    ("a_button_give",     "給",   877, 878),
    ("a_button_pick_up",  "拿起", 895, 896),
    ("a_button_use",      "使用", 898, 899),
    ("a_button_open",     "打開", 900, 901),
    ("a_button_look_at",  "查看", 902, 903),
    ("a_button_push",     "推",   904, 905),
    ("a_button_close",    "關上", 906, 907),
    ("a_button_talk_to",  "交談", 908, 909),
    ("a_button_pull",     "拉",   910, 911),
]


def load_face(path="/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc", index=2, size=GLYPH):
    """有 embedded bitmap strike 就用它（點陣字設計師手繪的，小尺寸最清楚），
    沒有就退回 outline，用 FreeType 的單色 rasterizer。"""
    face = freetype.Face(path, index)
    sizes = [s.height for s in face.available_sizes]
    if size in sizes:
        face.select_size(sizes.index(size))
        face._is_strike = True
    else:
        face.set_pixel_sizes(0, size)
        face._is_strike = False
    return face


def glyph_bits(face, ch, box=GLYPH, thresh=128, bold=0):
    """回傳 box×box 的 bool 矩陣。thresh 只對 outline 有效（灰階二值化門檻）。"""
    if getattr(face, "_is_strike", False):
        face.load_char(ch, freetype.FT_LOAD_RENDER | freetype.FT_LOAD_TARGET_MONO)
        mono = True
    else:
        face.load_char(ch, freetype.FT_LOAD_RENDER)
        mono = False
    bm = face.glyph.bitmap
    rows, width, pitch = bm.rows, bm.width, bm.pitch
    top, left = face.glyph.bitmap_top, face.glyph.bitmap_left
    out = [[False] * box for _ in range(box)]
    # 讓字框在方格裡置中：漢字通常滿版，直接用 bitmap 的實際大小回推。
    # [雷] 這裡本來對 embedded bitmap 走 `y0 = 10 - bitmap_top`（12px strike 的基線），
    #      換成 13/14px 的 strike 時 bitmap_top 變 11/12 → y0 變負 → **靜靜切掉字的頂端**
    #      （「打」變「孔」、「拿」掉了人字頭）。置中就沒有這個問題，兩條路徑統一用它。
    y0 = (box - rows) // 2
    x0 = (box - width) // 2
    for r in range(rows):
        y = y0 + r
        if not (0 <= y < box):
            continue
        for c in range(width):
            x = x0 + c
            if not (0 <= x < box):
                continue
            on = (bm.buffer[r * pitch + (c >> 3)] & (0x80 >> (c & 7))) if mono \
                else (bm.buffer[r * pitch + c] >= thresh)
            if on:
                out[y][x] = True
    if bold:
        thick = [row[:] for row in out]
        for y in range(box):
            for x in range(box):
                if out[y][x]:
                    for dx in range(1, bold + 1):
                        if x + dx < box:
                            thick[y][x + dx] = True
        out = thick
    return out


def render_button(face, text, w, h, fg, box=GLYPH, thresh=128, bold=0,
                  jitter=(), shadow=True, track=0, margin=1):
    """畫一張 w×h 的按鈕，回傳 RGB565 的 bytes。

    jitter：每個字的垂直位移（像素），用來做原版那種「字會上下跳」的手寫感。
    """
    px = [[BG] * w for _ in range(h)]
    for y in range(h):                      # 原圖左右各留透明邊（低解析 1 欄、hi-res 2 欄）
        for m in range(margin):
            px[y][m] = TRANSP
            px[y][w - 1 - m] = TRANSP

    bits = [glyph_bits(face, ch, box, thresh, bold) for ch in text]
    # track = 字距。原版英文是把整顆按鈕撐滿的（40 寬填到 97%），中文兩個字擠在中間
    # 只占 74%、64 寬的更只有 44%，並排看差很多。加字距把密度拉回來。
    step = box + track
    total = len(bits) * box + (len(bits) - 1) * track
    x0 = (w - total) // 2
    y0 = (h - box) // 2
    dy = list(jitter) + [0] * (len(bits) - len(jitter))

    def put(x, y, colour):
        if margin <= x < w - margin and 0 <= y < h:
            px[y][x] = colour

    if shadow:
        for i, g in enumerate(bits):       # 先畫陰影，字才蓋得過去
            for gy in range(box):
                for gx in range(box):
                    if g[gy][gx]:
                        put(x0 + i * step + gx + 1, y0 + gy + dy[i] + 1, SHADOW)
    for i, g in enumerate(bits):
        for gy in range(box):
            for gx in range(box):
                if g[gy][gx]:
                    put(x0 + i * step + gx, y0 + gy + dy[i], fg)

    buf = bytearray()
    for row in px:
        for v in row:
            buf += struct.pack("<H", v)
    return bytes(buf)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help="來源 acsprset.spr（用 ags_clib.py 從 Maniac.exe 抽出來）")
    ap.add_argument("-o", "--out", required=True)
    # 預設值 = 定案的樣式（見檔頭「選型」一節）：黑體 outline 14px、門檻 100、
    # 字距 10、第一個字掉 1px。改這裡就會連帶改建置產出，所以別隨手動。
    ap.add_argument("--font", default="/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc")
    ap.add_argument("--face", type=int, default=0)
    ap.add_argument("--size", type=int, default=14, help="字框大小（12 或 13、14）")
    ap.add_argument("--thresh", type=int, default=100, help="outline 二值化門檻（越小越粗）")
    ap.add_argument("--bold", type=int, default=0, help="往右加粗幾像素")
    ap.add_argument("--jitter", default="1,0", help="每字垂直位移，例如 \"-1,1\"（手寫跳動感）")
    ap.add_argument("--no-shadow", action="store_true")
    ap.add_argument("--track", type=int, default=10, help="字距（像素），把詞撐開到接近英文的密度")
    ap.add_argument("--hires", action="store_true",
                    help="用遊戲內建的 hi-res 槽（877-911，SPF_HIRES 已設），字框 24")
    ap.add_argument("--append", action="store_true",
                    help="把中文圖接在檔尾（不動原本的槽），槽號印出來給 .tra 用")
    ap.add_argument("--preview", help="另存一張對照圖")
    ap.add_argument("--export-pack",
                    help="另外輸出一個只含這 18 張圖的小檔（我們自己的美術，可隨 patch 版散布）")
    a = ap.parse_args()

    sf = SpriteFile(a.src)
    verbs = VERBS_HIRES if a.hires else VERBS
    if a.hires:                              # hi-res 的預設值另一組
        if a.size == 14: a.size = 24
        if a.track == 10: a.track = 6
        if a.thresh == 100: a.thresh = 128
    face = load_face(a.font, a.face, a.size)
    jit = [int(v) for v in a.jitter.split(",") if v.strip()] if a.jitter else ()
    kw = dict(box=a.size, thresh=a.thresh, bold=a.bold, jitter=jit,
              shadow=not a.no_shadow, track=a.track, margin=2 if a.hires else 1)

    repl = {}
    mapping = []
    next_slot = sf.topmost + 1
    for name, text, n_slot, h_slot in verbs:
        if a.append:
            n_slot, h_slot = next_slot, next_slot + 1
            next_slot += 2
            w, h = 40, 14
        else:
            _, _, w, h, _, _ = sf.sprites[n_slot]
        repl[n_slot] = (2, w, h, render_button(face, text, w, h, FG_NORMAL, **kw))
        repl[h_slot] = (2, w, h, render_button(face, text, w, h, FG_HILITE, **kw))
        mapping.append((name, text, n_slot, h_slot, w, h))

    data = sf.replace(repl, topmost=next_slot - 1 if a.append else None)
    open(a.out, "wb").write(data)

    print(f"{a.out}（{len(data):,} bytes）")
    for name, text, n, hl, w, h in mapping:
        print(f"  {name:<20} {text:<3} 一般={n:<5} 反白={hl:<5} {w}x{h}")
    if a.hires:
        print("\n給 .tra 的 a_button_* 值（格子位置 一般圖 反白圖 熱鍵）：")
        for (name, _, n, hl, _, _), (_, _, en_n, _), keys in zip(
                mapping, VERBS, ["Qq", "Ww", "Ee", "Aa", "Ss", "Dd", "Zz", "Xx", "Cc"]):
            pos = [v[2] for v in VERBS].index(en_n)
            print(f"  {name} …\t{pos} {n} {hl} {keys}")

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
