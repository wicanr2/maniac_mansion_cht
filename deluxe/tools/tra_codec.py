#!/usr/bin/env python3
"""AGS `.tra` 翻譯檔的解／編碼（Maniac Mansion Deluxe 用）。

Deluxe 是 AGS 遊戲，隨遊戲附了 German / French / Spanish 三份 `.tra`，
所以**不需要 AGS Editor 也拿得到完整的可翻譯字串集**：`.tra` 的鍵就是英文原文。

檔案格式（依 ScummVM `engines/ags/shared/game/tra_file.cpp`
與 `util/data_ext.cpp` 推導，非猜測）：

    "AGSTranslation\\0"          15 bytes
    迴圈 {
        int32 blockID            1=Dict, 2=GameID, 3=TextOpts, -1=結束
        int32 blockLen
        blockID == 2: int32 gameUid, 接一個加密字串（遊戲名）
        blockID == 1: 反覆 (原文, 譯文) 兩個加密字串，直到任一為空
        blockID == 3: int32 normalFont, speechFont, rightToLeft
    }

加密是逐位元組**減去** `"Avis Durgan"`（`decrypt_text()`；不是 XOR，
寫回去時要用加法），遇到解出 0 就視為字串結尾。

用法：
    tra_codec.py dump German.tra -o de.tsv          # 匯出「原文<TAB>譯文」
    tra_codec.py keys *.tra -o english.txt          # 取三份的原文聯集當翻譯範本
    tra_codec.py build zh.tsv -o Chinese.tra --game-uid 0x3e98150f \\
                 --game-name "Maniac Mansion Deluxe"
"""

import argparse
import struct
import sys

KEY = b"Avis Durgan"
BLK_DICT, BLK_GAMEID, BLK_TEXTOPTS = 1, 2, 3


def decrypt(buf):
    out = bytearray()
    for i, c in enumerate(buf):
        v = (c - KEY[i % 11]) & 0xFF
        if v == 0:
            break
        out.append(v)
    return bytes(out)


def encrypt(raw):
    return bytes((c + KEY[i % 11]) & 0xFF for i, c in enumerate(raw + b"\x00"))


def read_str(d, p):
    (ln,) = struct.unpack_from("<i", d, p)
    p += 4
    return decrypt(d[p:p + ln]), p + ln


def write_str(s):
    e = encrypt(s)
    return struct.pack("<i", len(e)) + e


def parse(path):
    d = open(path, "rb").read()
    if d[:14] != b"AGSTranslation":
        raise SystemExit(f"{path} 不是 AGS 翻譯檔")
    p = 15
    info = {"pairs": [], "uid": None, "name": b"", "textopts": None}
    while p + 8 <= len(d):
        (bid,) = struct.unpack_from("<i", d, p)
        p += 4
        if bid < 0:
            break
        (blen,) = struct.unpack_from("<i", d, p)
        p += 4
        end = p + blen
        q = p
        if bid == BLK_GAMEID:
            (info["uid"],) = struct.unpack_from("<i", d, p)
            info["name"], q = read_str(d, p + 4)
        elif bid == BLK_DICT:
            while q < end:
                src, q = read_str(d, q)
                dst, q = read_str(d, q)
                if not src or not dst:
                    break
                info["pairs"].append((src, dst))
        elif bid == BLK_TEXTOPTS:
            info["textopts"] = struct.unpack_from("<iii", d, p)
            q = p + 12
        # 位置以「實際讀到哪」為準，不硬跳 blockLen：3.0 以前的編輯器寫出來的
        # GameID 區塊長度會少算 1 個位元組（ScummVM 的 GetOverLeeway 正是在容忍它）。
        p = max(q, end)
    return info


def ext_block(ext_id, body):
    """新式（字串 ID）擴充區塊：int32 0 + 16 bytes ID + int64 長度 + 內容。"""
    return (struct.pack("<i", 0) + ext_id.encode("ascii").ljust(16, b"\x00")
            + struct.pack("<q", len(body)) + body)


def str_map(pairs):
    """StrUtil::WriteStringMap：int32 筆數 + 每筆 (int32 長度 + 位元組)，不加密。"""
    out = struct.pack("<i", len(pairs))
    for k, v in pairs:
        out += struct.pack("<i", len(k)) + k
        out += struct.pack("<i", len(v)) + v
    return out


def build(pairs, uid, name, textopts=None, legacy_gameid_len=False, encoding_hint=None):
    out = bytearray(b"AGSTranslation\x00")

    body = struct.pack("<i", uid) + write_str(name)
    # 3.0 以前的編輯器把 GameID 的長度少寫 1；照著寫可以與原檔 byte-perfect，
    # 寫正確值 ScummVM 也吃（它會 seek 到宣告的結尾，剛好落在正確位置）。
    out += struct.pack("<ii", BLK_GAMEID,
                       len(body) - 1 if legacy_gameid_len else len(body)) + body

    body = bytearray()
    for src, dst in pairs:
        body += write_str(src) + write_str(dst)
    body += write_str(b"") + write_str(b"")
    out += struct.pack("<ii", BLK_DICT, len(body)) + body

    if textopts:
        body = struct.pack("<iii", *textopts)
        out += struct.pack("<ii", BLK_TEXTOPTS, len(body)) + body

    if encoding_hint:
        # ScummVM 的 init_translation() 讀 StrOptions["encoding"]，是 "utf-8" 就
        # set_uformat(U_UTF8)——**與遊戲本身的版本無關**，所以 AGS 2.x 的舊遊戲
        # 也能靠這個 hint 走 UTF-8 文字路徑（字典的鍵仍是原文的單位元組編碼）。
        out += ext_block("ext_sopts",
                         str_map([(b"encoding", encoding_hint.encode("ascii"))]))

    # 結尾照原版寫法：-1（區塊列表結束）之後還有 4 個 0，是 3.0 以前的寫入器留下的。
    out += struct.pack("<ii", -1, 0)
    return bytes(out)


def esc(b):
    """TSV 用：把 tab / 換行寫成可見的轉義。"""
    return (b.decode("latin-1").replace("\\", "\\\\")
            .replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r"))


def unesc(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append({"t": "\t", "n": "\n", "r": "\r", "\\": "\\"}.get(s[i + 1], s[i + 1]))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("dump", help="把 .tra 匯成 原文<TAB>譯文")
    d.add_argument("tra")
    d.add_argument("-o", "--out", required=True)

    k = sub.add_parser("keys", help="取多份 .tra 的原文聯集（翻譯範本）")
    k.add_argument("tra", nargs="+")
    k.add_argument("-o", "--out", required=True)

    b = sub.add_parser("build", help="由 原文<TAB>譯文 產生 .tra")
    b.add_argument("tsv")
    b.add_argument("-o", "--out", required=True)
    b.add_argument("--game-uid", default="0x3e98150f")
    b.add_argument("--game-name", default="Maniac Mansion Deluxe")
    b.add_argument("--encoding", default="utf-8",
                   help="譯文寫進 .tra 時的位元組編碼；配合 --utf8 用預設即可")
    b.add_argument("--legacy-gameid-len", action="store_true",
                   help="GameID 區塊長度照 3.0 以前的寫法少寫 1（用來做 byte-perfect 回歸測試）")
    b.add_argument("--normal-font", type=int)
    b.add_argument("--speech-font", type=int)
    b.add_argument("--utf8", action="store_true",
                   help="寫入 ext_sopts encoding=utf-8，並用 UTF-8 編譯文"
                        "（ScummVM 會據此切到 UTF-8 文字模式）")

    a = ap.parse_args()

    if a.cmd == "dump":
        info = parse(a.tra)
        with open(a.out, "w", encoding="utf-8") as f:
            for src, dst in info["pairs"]:
                f.write(f"{esc(src)}\t{esc(dst)}\n")
        print(f"{a.tra}: {info['name'].decode('latin-1')} "
              f"uid={info['uid']:#x} 對照 {len(info['pairs'])} 組 → {a.out}"
              + (f"；TextOpts={info['textopts']}" if info["textopts"] else ""))

    elif a.cmd == "keys":
        seen = {}
        for path in a.tra:
            info = parse(path)
            for src, _ in info["pairs"]:
                seen.setdefault(esc(src), None)
            print(f"{path}: {len(info['pairs'])} 組", file=sys.stderr)
        with open(a.out, "w", encoding="utf-8") as f:
            for s in seen:
                f.write(s + "\n")
        print(f"原文聯集 {len(seen)} 行 → {a.out}")

    else:
        pairs = []
        for n, line in enumerate(open(a.tsv, encoding="utf-8").read().split("\n"), 1):
            if not line.strip():
                continue
            if "\t" not in line:
                raise SystemExit(f"第 {n} 行沒有 TAB：{line!r}")
            src, dst = line.split("\t", 1)
            if not dst.strip():
                continue                      # 沒翻的就不進字典，遊戲會用原文
            pairs.append((unesc(src).encode("latin-1"),
                          unesc(dst).encode(a.encoding)))
        # 原版三份 .tra 的 TextOpts 都是 (-1, -1, -1) = 不覆寫字型、不右到左；
        # 中文若要改用另一個字型槽，就用 --normal-font / --speech-font 指定。
        topts = (a.normal_font if a.normal_font is not None else -1,
                 a.speech_font if a.speech_font is not None else -1,
                 -1)
        blob = build(pairs, int(a.game_uid, 0), a.game_name.encode("latin-1"), topts,
                     a.legacy_gameid_len, "utf-8" if a.utf8 else None)
        open(a.out, "wb").write(blob)
        print(f"{len(pairs)} 組 → {a.out}（{len(blob)} bytes）")


if __name__ == "__main__":
    main()
