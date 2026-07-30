#!/usr/bin/env python3
"""檢查 Deluxe 分批譯文：鍵對位、行數、編碼、特殊 token、字元。

`.tra` 是用**英文原文當字典鍵**的格式，鍵錯一個字元該行就永遠比不中，
而且不會有任何錯誤訊息——遊戲只會默默顯示英文。所以逐行比對是必要的，
不是形式檢查。

檢查項目：

1. 每一行的鍵必須與 `english14.txt` 同序、同內容（含前後空白）。
2. 批次行數合計必須等於原文行數。
3. 格式化 token（`%s` `%d` `!s`）在譯文中必須出現同樣的次數。
4. 游標後綴（`>v` `>u` `>o` `>c` `>s` `>n`）必須原樣保留。
5. 內部標記（`_xxx_graphic_ 123` 這類）必須原樣不譯。
6. 譯文不得混入非預期的字集（西里爾、日文假名等——通常是打字時混進來的）。
7. 譯文必須能以 UTF-8 編碼（`.tra` 走 UTF-8 hint）。
"""

import argparse
import glob
import os
import re
import sys

TOKENS = ("%s", "%d", "!s")
SUFFIX = re.compile(r">[a-z]$")
INTERNAL = re.compile(r"^_[a-z]+_\d+_[a-z]+_ \d+$")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("english", help="原文聯集（tra_codec.py keys 的輸出）")
    ap.add_argument("batches", help="分批譯文所在目錄")
    a = ap.parse_args()

    en = [l.rstrip("\n") for l in open(a.english, encoding="utf-8")]
    files = sorted(glob.glob(os.path.join(a.batches, "b*.tsv")))
    if not files:
        raise SystemExit(f"{a.batches} 裡沒有 b*.tsv")

    problems = []
    pos = 0
    for f in files:
        rows = [l.rstrip("\n") for l in open(f, encoding="utf-8") if l.strip()]
        for i, line in enumerate(rows):
            n = i + 1
            where = f"{os.path.basename(f)}:{n}"
            if "\t" not in line:
                problems.append(f"{where} 沒有 TAB")
                continue
            src, dst = line.split("\t", 1)
            if pos + i >= len(en):
                problems.append(f"{where} 超出原文行數")
                continue
            if src != en[pos + i]:
                problems.append(f"{where} 鍵不符\n    譯 {src!r}\n    原 {en[pos + i]!r}")
                continue
            for t in TOKENS:
                if src.count(t) != dst.count(t):
                    problems.append(f"{where} token {t} 數量不符（原 {src.count(t)} / 譯 {dst.count(t)}）：{dst!r}")
            m = SUFFIX.search(src)
            if m and not dst.endswith(m.group(0)):
                problems.append(f"{where} 游標後綴 {m.group(0)} 沒保留：{dst!r}")
            if INTERNAL.match(src) and dst != src:
                problems.append(f"{where} 內部標記被改動：{dst!r}")
            if src.endswith(" ") and not dst.endswith(" "):
                problems.append(f"{where} 原文結尾有空白，譯文沒有：{dst!r}")
            for ch in dst:
                o = ord(ch)
                if (0x0400 <= o <= 0x04FF) or (0x3040 <= o <= 0x30FA):
                    problems.append(f"{where} 混入非預期字元 {ch!r}：{dst!r}")
                    break
            try:
                dst.encode("utf-8")
            except UnicodeEncodeError as e:
                problems.append(f"{where} 無法以 UTF-8 編碼：{e}")
        print(f"{os.path.basename(f)}: {len(rows)} 行（原文 {pos + 1}–{pos + len(rows)}）")
        pos += len(rows)

    print(f"合計 {pos} / {len(en)} 行")
    if pos != len(en):
        problems.append(f"行數不符：譯文 {pos}，原文 {len(en)}")

    if problems:
        for p in problems[:40]:
            print("  ✗ " + p, file=sys.stderr)
        raise SystemExit(f"共 {len(problems)} 個問題")
    print("鍵對位、token、後綴、字元、編碼全部通過")


if __name__ == "__main__":
    main()
