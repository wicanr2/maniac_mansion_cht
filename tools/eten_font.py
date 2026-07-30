#!/usr/bin/env python3
"""倚天中文系統 (ETEN 3.53) 點陣字讀取。

檔案格式：無檔頭，每字 (W+7)//8 * H bytes，每列 MSB-first、由上而下。

Big5 分區索引（非線性）：
    raw(hi,lo) = (hi-0xA1)*157 + (lo-0x40 if lo < 0x7F else lo-0x62)
    r <= raw(0xA3,0xBF)  → 符號區，idx = r，取自 SPCFONT
    r <= raw(0xC6,0x7E)  → 常用字，idx = r - raw(0xA4,0x40)，取自 STDFONT
    否則                  → 次常用，idx = 5401 + (r - raw(0xC9,0x40))，取自 STDFONT

[雷] STDFONT 只有漢字，全形標點在 SPCFONT。只帶 STDFONT 會讓
「，。！？「」（）」全部缺字。
"""

DIM15 = (16, 15)
ROWBYTES15 = 2
STRIDE15 = ROWBYTES15 * DIM15[1]     # 30

# Python big5 codec 與 Big5 表對不上的少數符號，手動補
MANUAL_BIG5 = {
    "～": b"\xa1\xe3",
    "…": b"\xa1\x4b",
    "—": b"\xa1\x56",
    "‧": b"\xa1\x45",
}


def raw(hi, lo):
    return (hi - 0xA1) * 157 + ((lo - 0x40) if lo < 0x7F else (lo - 0x62))


LAST_SPC = raw(0xA3, 0xBF)      # 407
BASE_A440 = raw(0xA4, 0x40)
LAST_COMMON = raw(0xC6, 0x7E)
BASE_C940 = raw(0xC9, 0x40)
N_COMMON = 5401


def big5_bytes(ch):
    if ch in MANUAL_BIG5:
        return MANUAL_BIG5[ch]
    try:
        b = ch.encode("big5")
    except UnicodeEncodeError:
        return None
    return b if len(b) == 2 else None


class EtenFont:
    """16x15 倚天字型（STDFONT.15 + SPCFONT.15 + SPCFSUPP.15）。"""

    def __init__(self, stdfont, spcfont=None, spcfsupp=None):
        self.std = open(stdfont, "rb").read()
        self.spc = open(spcfont, "rb").read() if spcfont else b""
        self.sup = open(spcfsupp, "rb").read() if spcfsupp else b""

    def locate(self, ch):
        """回傳 (blob, idx)；查不到回 None。"""
        b = big5_bytes(ch)
        if not b:
            return None
        r = raw(b[0], b[1])
        if r <= LAST_SPC:
            return (self.spc, r) if self.spc else None
        if r <= LAST_COMMON:
            return self.std, r - BASE_A440
        return self.std, N_COMMON + (r - BASE_C940)

    def bitmap(self, ch):
        """回傳 15 列 x 16 欄的 0/1 陣列；缺字回 None。"""
        loc = self.locate(ch)
        if loc is None:
            return None
        blob, idx = loc
        off = idx * STRIDE15
        if off + STRIDE15 > len(blob):
            return None
        rows = []
        for y in range(DIM15[1]):
            v = (blob[off + 2 * y] << 8) | blob[off + 2 * y + 1]
            rows.append([(v >> (15 - x)) & 1 for x in range(DIM15[0])])
        return rows


def embolden(rows):
    """程式加粗：每列與左移一格 OR，筆劃水平膨脹 1px（15 點只有偏細的明體）。"""
    out = []
    for r in rows:
        out.append([r[x] | (r[x - 1] if x > 0 else 0) for x in range(len(r))])
    return out


def box_downscale(rows, w, h, thresh=0.45):
    """面積加權縮放後二值化。thresh 越高筆劃越細、越不易黏連。"""
    sh, sw = len(rows), len(rows[0])
    out = []
    for y in range(h):
        y0, y1 = y * sh / h, (y + 1) * sh / h
        line = []
        for x in range(w):
            x0, x1 = x * sw / w, (x + 1) * sw / w
            acc = area = 0.0
            for sy in range(int(y0), min(sh, int(y1) + 1)):
                fy = min(y1, sy + 1) - max(y0, sy)
                if fy <= 0:
                    continue
                for sx in range(int(x0), min(sw, int(x1) + 1)):
                    fx = min(x1, sx + 1) - max(x0, sx)
                    if fx <= 0:
                        continue
                    acc += rows[sy][sx] * fy * fx
                    area += fy * fx
            line.append(1 if area and acc / area >= thresh else 0)
        out.append(line)
    return out


def ascii_art(rows):
    return "\n".join("".join("█" if v else "·" for v in r) for r in rows)
