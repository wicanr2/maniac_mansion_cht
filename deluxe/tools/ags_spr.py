#!/usr/bin/env python3
"""AGS `acsprset.spr`（sprite file v4／未壓縮）的讀寫。

格式依 ScummVM `engines/ags/shared/ac/sprite_file.cpp` 的 `OpenFile()`／
`ReadSprHeader()`／`RebuildSpriteIndex()` 實作：

    int16  version                    （MMD 1.4 是 4 = 未壓縮）
    char   sig[13] = " Sprite File "
    byte   palette[256*3]             （version < 5 才有）
    uint16 topmost                    （version < 11）
    重複 topmost+1 次：
        int8  bpp                     （0 = 空槽，後面沒有東西，直接接下一張）
        int8  sformat                 （v<12 恆為 0；這兩個 byte 等於舊版的 int16 coldep）
        int16 width
        int16 height
        byte  data[width*height*bpp]  （v4 沒有壓縮、也沒有長度欄位）

用法：
    ags_spr.py list  acsprset.spr [--from N --to M]
    ags_spr.py png   acsprset.spr N [N...] -o 目錄/
    ags_spr.py sheet acsprset.spr --from N --to M -o out.png
    ags_spr.py put   acsprset.spr --png N=檔案.png [...] -o 新的.spr
"""

import argparse
import os
import struct
import sys

SIG = b" Sprite File "


class SpriteFile:
    def __init__(self, path):
        self.raw = open(path, "rb").read()
        self.version = struct.unpack_from("<h", self.raw, 0)[0]
        if self.raw[2:2 + 13] != SIG:
            raise SystemExit("不是 AGS sprite 檔（簽章不符）")
        if self.version != 4:
            raise SystemExit(f"目前只實作 v4（未壓縮），這個檔是 v{self.version}")
        p = 2 + 13
        self.palette = self.raw[p:p + 768]
        p += 768
        self.topmost = struct.unpack_from("<H", self.raw, p)[0]
        p += 2
        self.data_start = p
        self.sprites = []          # (offset, bpp, w, h, data_offset, data_size)
        for _ in range(self.topmost + 1):
            off = p
            bpp = self.raw[p]
            p += 2                                   # bpp + sformat
            if bpp == 0:
                self.sprites.append((off, 0, 0, 0, p, 0))
                continue
            w, h = struct.unpack_from("<hh", self.raw, p)
            p += 4
            size = w * h * bpp
            self.sprites.append((off, bpp, w, h, p, size))
            p += size
        self.end = p

    def pixels(self, i):
        off, bpp, w, h, d, size = self.sprites[i]
        return self.raw[d:d + size], bpp, w, h

    def to_image(self, i):
        from PIL import Image
        data, bpp, w, h = self.pixels(i)
        if bpp == 0:
            return None
        if bpp == 1:
            im = Image.frombytes("P", (w, h), data)
            pal = []
            # AGS 的調色盤是 6-bit VGA 值，要放大到 8-bit
            for k in range(256):
                r, g, b = self.palette[k * 3:k * 3 + 3]
                pal += [min(255, r * 255 // 63), min(255, g * 255 // 63), min(255, b * 255 // 63)]
            im.putpalette(pal)
            return im.convert("RGB")
        if bpp == 2:
            # 16-bit RGB565
            out = bytearray()
            for k in range(w * h):
                v = data[k * 2] | (data[k * 2 + 1] << 8)
                out += bytes((((v >> 11) & 31) * 255 // 31,
                              ((v >> 5) & 63) * 255 // 63,
                              (v & 31) * 255 // 31))
            return Image.frombytes("RGB", (w, h), bytes(out))
        if bpp == 4:
            return Image.frombytes("RGBA", (w, h), data)[:, :]
        raise SystemExit(f"未支援的 bpp={bpp}")

    def replace(self, repl, topmost=None):
        """repl: {index: (bpp, w, h, bytes)} → 回傳整份新的 .spr 內容。

        topmost 給大於原值的數字就會往後長出新槽（沒指定內容的填空槽）。
        """
        new_top = self.topmost if topmost is None else max(topmost, self.topmost)
        head = bytearray(self.raw[:self.data_start])
        struct.pack_into("<H", head, self.data_start - 2, new_top)
        out = head
        for i in range(new_top + 1):
            if i in repl:
                nbpp, nw, nh, ndata = repl[i]
                assert len(ndata) == nw * nh * nbpp, f"sprite {i} 資料長度不符"
                out += struct.pack("<bbhh", nbpp, 0, nw, nh) + ndata
            elif i <= self.topmost:
                off, bpp, w, h, d, size = self.sprites[i]
                out += b"\x00\x00" if bpp == 0 else self.raw[off:d + size]
            else:
                out += b"\x00\x00"          # 新長出來但沒填東西的槽
        return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["list", "png", "sheet", "put"])
    ap.add_argument("spr")
    ap.add_argument("idx", nargs="*", type=int)
    ap.add_argument("--from", dest="lo", type=int, default=0)
    ap.add_argument("--to", dest="hi", type=int)
    ap.add_argument("--png", action="append", default=[], help="N=檔案.png")
    ap.add_argument("-o", "--out")
    a = ap.parse_args()

    sf = SpriteFile(a.spr)
    hi = a.hi if a.hi is not None else sf.topmost

    if a.cmd == "list":
        print(f"v{sf.version}，共 {sf.topmost + 1} 個槽，資料到 {sf.end:,} bytes")
        for i in range(a.lo, min(hi, sf.topmost) + 1):
            off, bpp, w, h, d, size = sf.sprites[i]
            if bpp:
                print(f"  {i:>5}  {w:>4}x{h:<4} bpp={bpp}  {size:>8,} bytes")
        return

    if a.cmd == "png":
        os.makedirs(a.out or ".", exist_ok=True)
        for i in a.idx:
            im = sf.to_image(i)
            if im is None:
                print(f"  {i}: 空槽")
                continue
            p = os.path.join(a.out or ".", f"spr{i:05d}.png")
            im.save(p)
            print(f"  {i}: {im.size[0]}x{im.size[1]} → {p}")
        return

    if a.cmd == "sheet":
        from PIL import Image
        ims = [(i, sf.to_image(i)) for i in range(a.lo, hi + 1)]
        ims = [(i, im) for i, im in ims if im]
        if not ims:
            raise SystemExit("這個範圍內沒有東西")
        wmax = max(im.size[0] for _, im in ims)
        htot = sum(im.size[1] + 4 for _, im in ims)
        sheet = Image.new("RGB", (wmax + 60, htot), (24, 24, 32))
        y = 0
        for i, im in ims:
            sheet.paste(im, (56, y))
            y += im.size[1] + 4
        sheet.save(a.out or "sheet.png")
        print(f"{len(ims)} 張 → {a.out}")
        return

    if a.cmd == "put":
        from PIL import Image
        repl = {}
        for spec in a.png:
            n, path = spec.split("=", 1)
            im = Image.open(path)
            i = int(n)
            _, bpp, _, _, _, _ = sf.sprites[i]
            if bpp == 1:
                im = im.convert("P")
                repl[i] = (1, im.size[0], im.size[1], im.tobytes())
            else:
                im = im.convert("RGB")
                buf = bytearray()
                for (r, g, b) in im.getdata():
                    buf += struct.pack("<H", ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3))
                repl[i] = (2, im.size[0], im.size[1], bytes(buf))
        data = sf.replace(repl)
        open(a.out, "wb").write(data)
        print(f"換掉 {sorted(repl)} → {a.out}（{len(data):,} bytes）")


if __name__ == "__main__":
    main()
