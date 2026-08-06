#!/usr/bin/env python3
"""把中文指令列按鈕裝進玩家自己的 Maniac Mansion Deluxe 遊戲夾。

只用標準函式庫，玩家不必 pip 裝任何東西：中文按鈕已經先烘成 `cht_buttons.bin`
（我們自己畫的 18 張小圖，不含遊戲美術），這支程式做的只是

  1. 從玩家的 `Maniac.exe`（CLIB）裡取出原本的 `acsprset.spr`
  2. 把那 18 張換成中文版
  3. 寫成**遊戲夾裡的鬆散 `acsprset.spr`**

引擎的 AssetManager 預設 `kAssetPriorityDir`，目錄排在 CLIB 前面，所以遊戲夾裡
這一份會蓋過 `Maniac.exe` 內的那份 —— **玩家原本的檔案一個位元組都不會被改到**，
要還原只要把 `acsprset.spr` 刪掉。

用法：
    patch_buttons.py <遊戲夾> [--pack cht_buttons.bin]
"""

import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ags_clib import read_lib, read_asset
from ags_spr import SpriteFile

MAGIC = b"MMCHTBTN\x01"


def load_pack(path):
    d = open(path, "rb").read()
    if d[:len(MAGIC)] != MAGIC:
        raise SystemExit(f"{path} 不是按鈕圖包")
    p = len(MAGIC)
    n = struct.unpack_from("<H", d, p)[0]
    p += 2
    out = {}
    for _ in range(n):
        idx, w, h, bpp, ln = struct.unpack_from("<HHHBI", d, p)
        p += 11
        out[idx] = (bpp, w, h, d[p:p + ln])
        p += ln
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gamedir")
    ap.add_argument("--pack", default=None)
    ap.add_argument("--exe", default=None, help="預設自動找 Maniac.exe")
    a = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    pack_path = a.pack or os.path.join(here, "cht_buttons.bin")
    exe = a.exe
    if not exe:
        for f in os.listdir(a.gamedir):
            if f.lower() == "maniac.exe":
                exe = os.path.join(a.gamedir, f)
                break
    if not exe or not os.path.exists(exe):
        raise SystemExit(f"在 {a.gamedir} 找不到 Maniac.exe")

    out_path = os.path.join(a.gamedir, "acsprset.spr")
    # 已經裝過的話，要從**原始的** CLIB 重新取，不然會疊在上一次的結果上
    lib = read_lib(exe)
    data = read_asset(lib, "acsprset.spr")
    if data is None:
        raise SystemExit("這個 Maniac.exe 裡沒有 acsprset.spr")
    tmp = out_path + ".orig.tmp"
    open(tmp, "wb").write(data)
    try:
        sf = SpriteFile(tmp)
        repl = load_pack(pack_path)
        new = sf.replace(repl)
        open(out_path, "wb").write(new)
    finally:
        os.remove(tmp)

    print(f"中文按鈕裝好了：{out_path}（{len(new):,} bytes，換了 {len(repl)} 張圖）")
    print("要還原的話，把這個檔案刪掉就好，遊戲原本的檔案沒有被動到。")


if __name__ == "__main__":
    main()
