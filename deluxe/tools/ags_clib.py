#!/usr/bin/env python3
"""AGS CLIB（多檔資料庫）讀取器 —— 用來把 acsprset.spr 從 Maniac.exe 抽出來。

格式依 ScummVM `engines/ags/shared/util/multi_file_lib.cpp` 實作，不是猜的：

* 簽章 `CLIB\\x1a` 可能在檔頭，也可能是「接在 exe 後面」——後者要從檔尾的
  `CLIB\\x01\\x02\\x03\\x04SIGE` 往回讀偏移量（先試 64-bit 再試 32-bit）。
* v20/v21 的目錄是加密的：以 `int32 seed + 9338638` 起始的 LCG
  （`rand = rand*214013 + 2531011`，取 `(>>16) & 0x7fff`），每讀一個 byte 就減一次。
* 檔案內容本身沒有加密，直接照 offset/size 取即可。
* 多檔資料庫：每筆資產帶一個 LibUid，指向 `LibFileNames[uid]`（Maniac.001…005）。

用法：
    ags_clib.py list <Maniac.exe>
    ags_clib.py extract <Maniac.exe> acsprset.spr -o out.spr
"""

import argparse
import os
import struct
import sys

HEAD_SIG = b"CLIB\x1a"
TAIL_SIG = b"CLIB\x01\x02\x03\x04SIGE"
RAND_SEED = 9338638
MAX_ASSET_LEN = 100
MAX_DATA_LEN = 50


class Dec:
    """v20/v21 目錄用的偽亂數解密器。"""

    def __init__(self, data, pos):
        self.d = data
        self.p = pos
        seed = struct.unpack_from("<i", data, self.p)[0]
        self.p += 4
        self.rand = (seed + RAND_SEED) & 0xFFFFFFFF

    def _next(self):
        self.rand = (self.rand * 214013 + 2531011) & 0xFFFFFFFF
        # C 的 int 右移是算術移位，先還原成有號數
        v = self.rand - (1 << 32) if self.rand >= (1 << 31) else self.rand
        return (v >> 16) & 0x7FFF

    def byte(self):
        b = (self.d[self.p] - self._next()) & 0xFF
        self.p += 1
        return b

    def int32(self):
        v = bytes(self.byte() for _ in range(4))
        return struct.unpack("<i", v)[0]

    def string(self, max_len):
        out = bytearray()
        while True:
            c = self.byte()
            if c == 0:
                break
            out.append(c)
            if len(out) >= max_len - 1:
                break
        return out.decode("latin-1")


def find_lib(data):
    """回傳 (絕對偏移, 版本)。"""
    if data[: len(HEAD_SIG)] == HEAD_SIG:
        return 0, data[len(HEAD_SIG)]
    if data[-len(TAIL_SIG):] != TAIL_SIG:
        raise SystemExit("不是 AGS CLIB（檔尾沒有 SIGE 簽章）")
    tail = len(data) - len(TAIL_SIG)
    off64 = struct.unpack_from("<q", data, tail - 8)[0]
    off32 = struct.unpack_from("<i", data, tail - 4)[0]
    for off in (off64, off32):
        if 0 < off < tail - len(HEAD_SIG) and data[off:off + len(HEAD_SIG)] == HEAD_SIG:
            return off, data[off + len(HEAD_SIG)]
    raise SystemExit("找得到檔尾簽章，但偏移量指不到檔頭簽章")


V10_LIB_FILE_LEN = 20
V10_ASSET_FILE_LEN = 25
ENC_STRING = b"My\x01\xde\x04Jibzle"


def decrypt_text(buf):
    """v11/v15 的檔名加密：逐位元組減去 'My\\x01\\xde\\x04Jibzle'（索引 0..10 循環）。"""
    out = bytearray()
    adx = 0
    for c in buf:
        v = (c - ENC_STRING[adx]) & 0xFF
        if v == 0:
            break
        out.append(v)
        adx += 1
        if adx > 10:      # 金鑰只有 11 個字元，繞回開頭
            adx = 0
    return out.decode("latin-1")


def read_lib_v10(data, p, ver):
    """v10 / v11 / v15：目錄沒有加密，只有檔名在 v11 起會被 decrypt_text 打亂。"""
    def i32():
        nonlocal p
        v = struct.unpack_from("<i", data, p)[0]
        p += 4
        return v

    mf_count = i32()
    lib_files = []
    for _ in range(mf_count):
        lib_files.append(data[p:p + V10_LIB_FILE_LEN].split(b"\0")[0].decode("latin-1"))
        p += V10_LIB_FILE_LEN
    n = i32()
    names = []
    for _ in range(n):
        raw = data[p:p + V10_ASSET_FILE_LEN]
        p += V10_ASSET_FILE_LEN
        names.append(decrypt_text(raw) if ver >= 11 else raw.split(b"\0")[0].decode("latin-1"))
    offsets = [i32() for _ in range(n)]
    sizes = [i32() for _ in range(n)]
    uids = []
    for _ in range(n):
        uids.append(data[p])
        p += 1
    return lib_files, names, offsets, sizes, uids


def read_lib(path):
    data = open(path, "rb").read()
    off, ver = find_lib(data)
    p = off + len(HEAD_SIG) + 1
    if ver >= 10:
        p += 1                       # 這是不是 chain 的第一個檔
    if ver in (10, 11, 15):
        lib_files, names, offsets, sizes, uids = read_lib_v10(data, p, ver)
        assets = [
            # CLIB 接在 exe 後面時，uid 0（＝這個檔本身）的偏移量要加上 CLIB 的起點；
            # 其他分割檔是獨立檔案，偏移量本來就是絕對的
            {"name": nm, "offset": (o & 0xFFFFFFFF) + (off if u == 0 else 0),
             "size": s & 0xFFFFFFFF, "uid": u}
            for nm, o, s, u in zip(names, offsets, sizes, uids)
        ]
        return {"version": ver, "lib_files": lib_files, "assets": assets, "base": path}
    if ver not in (20, 21):
        raise SystemExit(f"目前只實作 v10/v11/v15/v20/v21，這個檔是 v{ver}")
    d = Dec(data, p)
    mf_count = d.int32()
    lib_files = [d.string(MAX_DATA_LEN) for _ in range(mf_count)]
    n = d.int32()
    names = [d.string(MAX_ASSET_LEN) for _ in range(n)]
    offsets = [d.int32() for _ in range(n)]
    sizes = [d.int32() for _ in range(n)]
    uids = [d.byte() for _ in range(n)]
    assets = [
        {"name": nm, "offset": o & 0xFFFFFFFF, "size": s & 0xFFFFFFFF, "uid": u}
        for nm, o, s, u in zip(names, offsets, sizes, uids)
    ]
    return {"version": ver, "lib_files": lib_files, "assets": assets, "base": path}


def read_asset(lib, name):
    for a in lib["assets"]:
        if a["name"].lower() == name.lower():
            # uid 0 指的是「這個 CLIB 自己所在的檔案」——目錄裡記的名字（ac2game.ags）
            # 是打包時的原始檔名，磁碟上其實是 Maniac.exe
            if a["uid"] == 0:
                with open(lib["base"], "rb") as fh:
                    fh.seek(a["offset"])
                    return fh.read(a["size"])
            fn = lib["lib_files"][a["uid"]]
            d = os.path.dirname(os.path.abspath(lib["base"]))
            # CLIB 裡記的檔名大小寫未必與磁碟上一致
            real = None
            for f in os.listdir(d):
                if f.lower() == fn.lower():
                    real = os.path.join(d, f)
                    break
            if real is None:
                raise SystemExit(f"找不到分割檔 {fn}")
            with open(real, "rb") as fh:
                fh.seek(a["offset"])
                return fh.read(a["size"])
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["list", "extract"])
    ap.add_argument("clib")
    ap.add_argument("asset", nargs="?")
    ap.add_argument("-o", "--out")
    args = ap.parse_args()

    lib = read_lib(args.clib)
    if args.cmd == "list":
        print(f"CLIB v{lib['version']}，分割檔 {lib['lib_files']}，共 {len(lib['assets'])} 個資產")
        for a in sorted(lib["assets"], key=lambda x: -x["size"])[:40]:
            print(f"  {a['name']:<28} {a['size']:>10,} bytes  (part {a['uid']} @ {a['offset']})")
        return
    data = read_asset(lib, args.asset)
    if data is None:
        raise SystemExit(f"CLIB 裡沒有 {args.asset}")
    out = args.out or args.asset
    open(out, "wb").write(data)
    print(f"{args.asset} → {out}（{len(data):,} bytes）")


if __name__ == "__main__":
    main()
