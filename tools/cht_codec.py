#!/usr/bin/env python3
"""瘋狂大樓（SCUMM v2）繁中化自訂碼空間編解碼。

碼空間設計
----------
首碼 0x88-0x9F（24 個）、尾碼 0xA1-0xFD（93 個）→ 2232 個字位。

SCUMM v2 的腳本字串用「位元組 | 0x80」表示「該字元後面接一個空白」（空白壓縮），
所以首碼必須避開所有可能被壓縮出來的值：

* 可列印 ASCII（0x20-0x7E）| 0x80 → **0xA0-0xFE**
* SCUMM 控制碼 0x01-0x03（換行／不換行／等待點擊）| 0x80 → **0x81-0x83**
  （0x04-0x07 帶參數，scummtr 的 _spaceCharToBit 不壓縮它們）

一開始把首碼取成 0x80-0x9F 就是因為漏看了第二種：片頭字幕 `by\\001     Ron`
的 `\\001` 後面接空白，被壓成 0x81，於是被誤判成中文首碼、算出負索引，
畫面上多出一個亂碼字並把整行截掉。收窄到 0x88-0x9F 之後，
首碼與「壓縮碼 / 原始控制碼 0x01-0x07 / 原始 ASCII 0x20-0x7E」三者都不重疊。

尾碼避開 0x00（字串結尾）、0x40（'@' 排版填充，printChar 會 skip）、
0x5C（'\\' scummtr 轉義）、0xFE/0xFF（SCUMM 控制碼前綴）。

字型索引：idx = (lead - 0x88) * 93 + (trail - 0xA1)
"""

import argparse
import json
import sys
import unicodedata

LEAD_LO, LEAD_HI = 0x88, 0x9F
TRAIL_LO, TRAIL_HI = 0xA1, 0xFD
N_LEAD = LEAD_HI - LEAD_LO + 1        # 24
N_TRAIL = TRAIL_HI - TRAIL_LO + 1     # 93
CAPACITY = N_LEAD * N_TRAIL           # 2232


def slot_to_bytes(slot):
    if not 0 <= slot < CAPACITY:
        raise ValueError(f"字位 {slot} 超出碼空間容量 {CAPACITY}")
    return LEAD_LO + slot // N_TRAIL, TRAIL_LO + slot % N_TRAIL


def font_index(lead, trail):
    return (lead - LEAD_LO) * N_TRAIL + (trail - TRAIL_LO)


def collect_chars(lines):
    """依出現順序蒐集所有非 ASCII 字元。"""
    seen = {}
    for ln in lines:
        for ch in ln:
            if ord(ch) > 0x7E and ch not in seen:
                seen[ch] = len(seen)
    return list(seen)


def build_table(chars):
    if len(chars) > CAPACITY:
        raise SystemExit(f"字集 {len(chars)} 字超出碼空間容量 {CAPACITY}")
    return {ch: list(slot_to_bytes(i)) for i, ch in enumerate(chars)}


def encode_line(text, table, lineno=None):
    out = bytearray()
    for ch in text:
        o = ord(ch)
        if 0x20 <= o <= 0x7E or ch == "\t":
            out.append(o)
        elif ch in table:
            out.extend(table[ch])
        else:
            where = f"（第 {lineno} 行）" if lineno else ""
            name = unicodedata.name(ch, "?")
            raise SystemExit(f"字元 {ch!r} (U+{o:04X} {name}) 不在碼表中{where}")
    return bytes(out)


# ── 斷行 ────────────────────────────────────────────────────────────────
# SCUMM v2 的對白**完全不自動換行**（ScummVM 的 addLinebreaks 只在 version > 3
# 才呼叫），太長的一行會直接在畫面右緣被截掉。所以斷行必須在譯文裡做完：
# 對白畫在畫面左上 (0,0)、往右長，可用寬度 320px；中文 12px/字、ASCII 8px/字。
# 控制碼 \001 = 換行、\003 = 等待點擊（分頁），兩者都會把行寬歸零。
# printChar 的裁切條件是 `_left + width > _right + 1`（_right = 319），所以最後一個
# 字元的起點可以到 312：英文剛好放得下 40 字（= 320px），中文放得下 26 字（= 312px）。
LINE_WIDTH = 320
CJK_W, ASCII_W = 12, 8


def _tokens(text):
    """把一行切成 (種類, 字面) 序列：ctrl / cjk / ascii / pad。"""
    i = 0
    while i < len(text):
        if text[i] == "\\" and i + 3 < len(text) + 1 and text[i + 1:i + 4].isdigit():
            code = int(text[i + 1:i + 4])
            n = 4
            if 3 < code < 8:            # \004\xx\yy 這類帶兩個參數
                for _ in range(2):
                    if text[i + n:i + n + 4].startswith("\\"):
                        n += 4
            yield ("ctrl", text[i:i + n], code)
            i += n
            continue
        ch = text[i]
        if ch == "@":
            yield ("pad", ch, 0)
        elif ord(ch) > 0x7E:
            yield ("cjk", ch, 0)
        else:
            yield ("ascii", ch, 0)
        i += 1


def wrap_line(text, width=LINE_WIDTH):
    """在超寬處插入 \\001。已有的 \\001 / \\003 視為現成斷點，不重複插。

    純 ASCII 的行一律原樣送回——原版英文是照「一行 40 字」排好的，沒有翻譯到的
    行不該被我們改動（也讓「未翻譯的行必須 byte-perfect」這個不變式成立）。
    """
    if all(ord(c) <= 0x7E for c in text):
        return text
    out, cur = [], 0
    for kind, lit, code in _tokens(text):
        if kind == "ctrl":
            out.append(lit)
            if code in (1, 2, 3):
                cur = 0
            continue
        w = CJK_W if kind == "cjk" else (0 if kind == "pad" else ASCII_W)
        if cur + w > width:
            out.append("\\001")
            cur = 0
        out.append(lit)
        cur += w
    return "".join(out)


def verify(data):
    """回填前的自檢：不得出現會撞到引擎/工具語意的位元組。"""
    problems = []
    i = 0
    while i < len(data):
        b = data[i]
        if LEAD_LO <= b <= LEAD_HI:
            if i + 1 >= len(data):
                problems.append(f"offset {i}: 首碼 {b:#02x} 後面沒有尾碼")
                break
            t = data[i + 1]
            if not TRAIL_LO <= t <= TRAIL_HI:
                problems.append(f"offset {i}: 尾碼 {t:#02x} 超出 0xA1-0xFD")
            i += 2
            continue
        if b >= 0x80:
            problems.append(f"offset {i}: 落單的高位位元組 {b:#02x}（會被當成空白壓縮碼）")
        i += 1
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("translation", help="UTF-8 譯文，行數與行序須與 scummtr dump 一致")
    ap.add_argument("-r", "--reference", help="原始 scummtr dump，用來核對行數")
    ap.add_argument("-t", "--table", default="cht_table.json")
    ap.add_argument("-o", "--out", default="scummtr.txt", help="輸出（latin-1 + CRLF）")
    ap.add_argument("-c", "--context",
                    help="scummtr -h 的 dump；有給就只對對白行（opcode D8 / 14）自動斷行")
    args = ap.parse_args()

    lines = open(args.translation, encoding="utf-8").read().split("\n")
    while lines and lines[-1] == "":
        lines.pop()

    if args.reference:
        ref = open(args.reference, encoding="latin-1").read().split("\n")
        while ref and ref[-1] == "":
            ref.pop()
        if len(ref) != len(lines):
            raise SystemExit(f"行數不符：譯文 {len(lines)} 行，原 dump {len(ref)} 行")

    wrapped = 0
    if args.context:
        ctx = open(args.context, encoding="latin-1").read().split("\n")
        while ctx and ctx[-1] == "":
            ctx.pop()
        if len(ctx) != len(lines):
            raise SystemExit(f"context 行數 {len(ctx)} 與譯文 {len(lines)} 不符")
        for i, (ln, cl) in enumerate(zip(lines, ctx)):
            if "](D8)" in cl or "](14)" in cl:
                w = wrap_line(ln)
                if w != ln:
                    lines[i] = w
                    wrapped += 1

    chars = collect_chars(lines)
    table = build_table(chars)
    json.dump(table, open(args.table, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1, sort_keys=True)

    blob = bytearray()
    allp = []
    for n, ln in enumerate(lines, 1):
        enc = encode_line(ln, table, n)
        allp += [f"第 {n} 行: {p}" for p in verify(enc)]
        blob += enc + b"\r\n"
    if allp:
        for p in allp[:20]:
            print(p, file=sys.stderr)
        raise SystemExit(f"自檢失敗，共 {len(allp)} 個問題")

    open(args.out, "wb").write(blob)
    print(f"譯文 {len(lines)} 行；字集 {len(chars)} 字 / 容量 {CAPACITY}；"
          f"自動斷行 {wrapped} 行；輸出 {len(blob)} bytes → {args.out}，碼表 → {args.table}")


if __name__ == "__main__":
    main()
