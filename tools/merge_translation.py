#!/usr/bin/env python3
"""把分批譯文併成一份完整的 scummtr 譯文檔，並對齊需要固定寬度的行。

兩種寬度必須守住：

* 原文以 `@` 結尾 —— `@` 是 SCUMM 的排版填充字元（printChar 遇到 '@' 直接 skip），
  用來把物件名／指令名補到固定長度。物件名的長度就是該物件名緩衝區的大小，
  腳本後續用 setObjectName 換名字時不能超過它；指令名的長度則決定
  `curRect.right = left + (資源長度-1)*8`，也就是可點擊範圍。
* 原文以空白結尾且屬於 verbOps（opcode 7A）—— 例如選角畫面的名牌
  `"        Dave "`，靠前後空白置中，長度同樣決定可點擊範圍。

其餘行（一般對白）不補，長度自由。
"""

import argparse
import sys


def enc_len(s):
    """譯文編成自訂碼空間後的位元組長度（非 ASCII 一律兩個位元組）。"""
    return sum(2 if ord(c) > 0x7E else 1 for c in s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("reference", help="原始 scummtr dump（-r -w）")
    ap.add_argument("context", help="帶 script context 的 dump（scummtr -h）")
    ap.add_argument("batches", nargs="+", help="依序排列的分批譯文")
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()

    ref = open(args.reference, encoding="latin-1").read().split("\n")
    ctx = open(args.context, encoding="latin-1").read().split("\n")
    for lst in (ref, ctx):
        while lst and lst[-1] == "":
            lst.pop()
    if len(ref) != len(ctx):
        raise SystemExit(f"reference {len(ref)} 行 / context {len(ctx)} 行 不符")

    zh = []
    for p in args.batches:
        lines = open(p, encoding="utf-8").read().split("\n")
        while lines and lines[-1] == "":
            lines.pop()
        zh += lines

    header = [l for l in ref[:2]]
    if not all(l.startswith(";;") for l in header):
        raise SystemExit("原 dump 前兩行不是 ScummTR 註解標頭")
    out = header + zh

    if len(out) != len(ref):
        raise SystemExit(f"合併後 {len(out)} 行，應為 {len(ref)} 行"
                         f"（譯文 {len(zh)} 行 + 標頭 2 行）")

    padded = untouched = restored = 0
    for i in range(2, len(out)):
        # scummtr 不接受空行（`Empty lines are forbidden`）。原文中有些行本身就是
        # 單一空白（用來清掉上一句對白），譯文如果寫成真正的空行就會被擋下來，
        # 這裡一律還原成原文。
        if out[i] == "" and ref[i] != "":
            out[i] = ref[i]
            restored += 1
        orig, cur, c = ref[i], out[i], ctx[i]
        if orig == cur:
            untouched += 1
            continue
        want = len(orig)                     # 原文是 latin-1，長度即位元組數
        # [例外] 指令列（script 164 的 15 個指令）不補到原長度。
        # 中文指令一律補到 5 bytes，讓 drawVerb 算出的欄寬
        # `curRect.right = left + (6-1)*8 = left + 40` 剛好等於 2 列排版的欄距，
        # 相鄰指令的可點範圍才不會互相重疊；引擎端也是用「資源長度 == 6」
        # 來認出「這是中文化過的指令」才套用兩列版面。
        if "SCv2#0164" in c:
            continue
        if orig.endswith("@"):
            ch = "@"
        elif orig.endswith(" ") and "](7A)" in c:
            ch = " "
        else:
            continue
        have = enc_len(cur)
        if have > want:
            raise SystemExit(f"第 {i+1} 行譯文 {have} bytes 超過原文 {want} bytes：{cur!r}")
        if have < want:
            out[i] = cur + ch * (want - have)
            padded += 1

    open(args.out, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"合併 {len(out)} 行 → {args.out}；補位 {padded} 行；"
          f"空行還原 {restored} 行；未翻譯（與原文相同）{untouched} 行")


if __name__ == "__main__":
    main()
