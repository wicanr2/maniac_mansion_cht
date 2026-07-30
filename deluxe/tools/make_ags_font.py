#!/usr/bin/env python3
"""把一份 CJK 字型做成 AGS 能用的 `agsfnt*.ttf`（含放大與精簡）。

為什麼需要這支工具
------------------
AGS 2.x 的遊戲資料裡，字型槽**沒有** size 欄位，所以 ScummVM 載 TTF 時會走
`ttf_font_renderer.cpp` 的相容分支：

    if (fontSize <= 0)
        fontSize = 8; // compatibility fix

也就是不管你放什麼字型，都以 **8px em** 渲染——中文在這個尺寸下細得像雜訊。
引擎那邊沒有可調的參數，但**字型自己可以決定 1 em 有多大**：把 `head.unitsPerEm`
改小而字形座標不動，同樣的 8px em 就會畫出比例上更大的字。upem 減半 → 字大一倍。

這是純資料的作法，不必修引擎（Deluxe 這條線的原則）。

順便做兩件事：
* `.ttc` 取出指定 face（FreeType 自己也會取第一個 face，但明確一點比較好）。
* 依譯文精簡字集（`--subset-from`），避免把整份 CJK 字型塞進發佈包。

用法：
    make_ags_font.py /usr/share/fonts/truetype/wqy/wqy-zenhei.ttc \\
        -o agsfnt0.ttf --scale 2 --subset-from zh.tsv
"""

import argparse
import sys


def load_font(path, face):
    from fontTools.ttLib import TTFont, TTCollection
    if path.lower().endswith(".ttc"):
        coll = TTCollection(path, lazy=False)
        if face >= len(coll.fonts):
            raise SystemExit(f"{path} 只有 {len(coll.fonts)} 個 face")
        return coll.fonts[face]
    return TTFont(path, fontNumber=face if face else 0, lazy=False)


def chars_from_tsv(path):
    """從 原文<TAB>譯文 的譯文欄收字。"""
    used = set()
    for line in open(path, encoding="utf-8"):
        if "\t" not in line:
            continue
        used.update(line.split("\t", 1)[1].rstrip("\n"))
    return used


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("font")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--face", type=int, default=0)
    ap.add_argument("--scale", type=float, default=2.0,
                    help="字要放大幾倍（做法是把 unitsPerEm 除以這個值）")
    ap.add_argument("--subset-from", help="譯文 TSV；有給就只留用到的字")
    ap.add_argument("--fail-on-missing", action="store_true",
                    help="譯文用到字型沒有的字就直接失敗（預設只警告）")
    a = ap.parse_args()

    font = load_font(a.font, a.face)
    upem = font["head"].unitsPerEm

    if a.subset_from:
        from fontTools import subset
        used = chars_from_tsv(a.subset_from)
        # 字型沒有的字會被 FreeType 畫成 .notdef（空心方框），畫面上看起來像「有字但不對」，
        # 而且不會有任何錯誤訊息。實際踩過的例子：⋯（U+22EF，數學用省略號）在 WQY 裡不存在，
        # 288 處對白開頭全變成方框；換成中文標準的「…」（U+2026）才有字。
        missing = sorted(c for c in used
                         if c.strip() and font.getBestCmap().get(ord(c)) is None)
        if missing:
            print("字型缺字：" + " ".join(f"U+{ord(c):04X}({c})" for c in missing),
                  file=sys.stderr)
            if a.fail_on_missing:
                raise SystemExit(f"{len(missing)} 個字在字型裡不存在，會畫成空心方框")
        used.update(chr(c) for c in range(0x20, 0x7F))     # 英數與標點一定要留
        opt = subset.Options()
        opt.layout_features = ["*"]
        opt.drop_tables += ["EBDT", "EBLC"]                # 內嵌點陣用不到（alfont 走輪廓）
        opt.notdef_outline = True
        sub = subset.Subsetter(options=opt)
        sub.populate(text="".join(sorted(used)))
        sub.subset(font)
        print(f"精簡字集：{len(used)} 字", file=sys.stderr)

    if a.scale and a.scale != 1.0:
        new_upem = int(round(upem / a.scale))
        font["head"].unitsPerEm = new_upem
        print(f"unitsPerEm {upem} → {new_upem}（字形座標不動 = 視覺放大 {a.scale}×）",
              file=sys.stderr)

    font.flavor = None
    font.save(a.out)
    import os
    print(f"{a.out}（{os.path.getsize(a.out)} bytes）")


if __name__ == "__main__":
    main()
