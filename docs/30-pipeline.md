# 從原版重建中文版

需要自備《Maniac Mansion》Enhanced DOS 版（v2）的 `00.LFL … 53.LFL`。本 repo 不含遊戲資料。

## 環境

一個 docker image 打通全部步驟：

```dockerfile
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    scummvm xvfb x11-utils xdotool imagemagick ffmpeg \
    python3 python3-pil python3-pip python3-venv \
    fonts-wqy-microhei fonts-wqy-zenhei fonts-noto-cjk \
    build-essential cmake pkg-config nasm git curl file \
    libsdl2-dev libsdl2-net-dev zlib1g-dev libpng-dev libfreetype6-dev \
    libogg-dev libvorbis-dev libflac-dev libmad0-dev libmpeg2-4-dev \
    liba52-dev libfluidsynth-dev libcurl4-openssl-dev \
    zstd zip unzip p7zip-full unrar-free gdb valgrind \
    && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv --system-site-packages /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir freetype-py
ENV PATH="/opt/venv/bin:${PATH}"
```

系統內建的 `/usr/games/scummvm` 只用來對照原版行為（它不含本專案的 patch，跑中文版會看到亂碼）。**注意 `/usr/games` 不在非登入 shell 的 PATH 裡，要用絕對路徑。**

## 步驟

### 1. 取得並修補工具

```bash
git clone --depth 1 https://github.com/dwatteau/scummtr.git      tools/scummtr-src
git clone --depth 1 https://github.com/scummvm/scummvm.git       tools/scummvm-src
git clone --depth 1 https://github.com/scummvm/scummvm-tools.git tools/scummvm-tools-src  # descumm，選用

cd tools/scummtr-src  && git apply ../../patches/scummtr-maniacv2-lossless.patch
cd ../scummvm-src     && git apply ../../patches/scummvm-maniac-zhtw.patch
```

建置參數見 `20-patches.md`。

### 2. 抽字

```bash
cd game-orig/mansiond
scummtr -g maniacv2 -r -w -of ../../dumps/mm_v2_raw.txt   # 回填用（1141 行）
scummtr -g maniacv2 -r -w -h -of ../../dumps/mm_v2_ctx.txt # 帶 script context，管線判斷行別用
```

`-r`（raw，保留原編碼）是必要的；`-c` 會轉碼破壞中文。**不要用 `-A aov`** —— 它是「保護 actor/object/verb 名不被改長度」，而中文化指令列本來就要改長度，而且它在 v2 上另有一個會讓檔案膨脹的 bug（見 `00-engine-verification.md`）。

### 3. 驗證可逆性（每次改工具都要重跑）

```bash
cp mm_v2_raw.txt scummtr.txt
scummtr -g maniacv2 -r -w -if
for f in *.LFL; do cmp -s "$f" "../../game-orig/mansiond/$f" || echo "DIFF $f"; done
```

預期輸出為空 —— **54 個 LFL 全部 byte-perfect**。

### 4. 合併譯文、編碼、烘字型、回填

```bash
python3 tools/merge_translation.py dumps/mm_v2_raw.txt dumps/mm_v2_ctx.txt \
        translations/b0{1,2,3,4,5,6,7,8}.txt -o dumps/mm_v2_zh.txt

python3 tools/cht_codec.py dumps/mm_v2_zh.txt \
        -r dumps/mm_v2_raw.txt -c dumps/mm_v2_ctx.txt \
        -t cht_table.json -o dumps/scummtr_zh.txt

python3 tools/build_cht_font.py cht_table.json \
        -o game-cht/mansiond/chinese_gb16x12.fnt --preview font-preview.png

cd game-cht/mansiond && cp ../../dumps/scummtr_zh.txt scummtr.txt
rm -f *scummio-tmp && scummtr -g maniacv2 -r -w -if
```

三個工具各自負責的事：

* **`merge_translation.py`** —— 併批、對齊固定寬度（`@` 補位、verb 排版空白）、把寫成空行的譯文還原成原文（scummtr 不收空行）。指令列是例外：一律補到 5 bytes，不補到原長度。
* **`cht_codec.py`** —— 配碼位、產 `cht_table.json`、編成 latin-1 + CRLF；順便做像素級斷行（只作用在對白行，純 ASCII 行一律不動）與位元組自檢。
* **`build_cht_font.py`** —— 依碼表烘 `chinese_gb16x12.fnt`（2232 字位 × 24 bytes = 53568 bytes）。

### 5. 實機驗證

```bash
Xvfb :99 -screen 0 640x480x16 &
DISPLAY=:99 tools/scummvm-src/scummvm -p game-cht/mansiond \
    --auto-detect --no-fullscreen -e adlib --no-aspect-ratio &
DISPLAY=:99 import -window root shot.png
```

啟動 log 出現 `Loading CJK Font`、偵測結果標示 `Chinese (Simplified)`，就代表 ZH_CHN 路徑有進去。

驗收項目：

- [ ] 指令列 15 個全中文、兩列、間距不重疊
- [ ] 句子列中文，下緣無殘影
- [ ] 對白逐字正確，**無字元級亂碼**（有 → 撞碼，回頭檢查碼空間）
- [ ] **無截字**（有 → renderer 字高／字寬硬編碼，回頭檢查第 4、5 項 patch）
- [ ] 長訊息會分頁而不是被裁掉
- [ ] 片頭字幕（純 ASCII）維持兩行、不需要按鍵翻頁
- [ ] 物品欄中文，不出現半個字

## 常見卡點

| 症狀 | 原因 |
|---|---|
| `ERROR: Modifying Maniac Mansion V2 is known to corrupt it` | 沒套 ScummTR patch，或沒開 `SCUMMRP_OK_TO_CORRUPT_MANIACV2` |
| `ERROR: char > 0x80 in line N` | 沒開 `SCUMMTR_CJK_CUSTOM_CODESPACE` |
| `ERROR: Empty lines are forbidden` | 譯文有真正的空行；`merge_translation.py` 會自動還原成原文 |
| `ERROR: Script error at 0x... in 07.LFL (roomOps)` | 原版資料遺留的孤立字串，無害（見 `00-engine-verification.md`） |
| 中文變成橫條噪點 | 字高被截 → 第 4 項 patch |
| 字距整排錯開 | 字寬算成 8 → 第 5 項 patch |
| 字幕多出一個怪字並被截斷 | 撞到空白壓縮碼 → 碼空間首碼範圍 |
| import 中途失敗後再跑報「already exists」 | 殘留 `*.LFL~~scummio-tmp`，先 `rm -f *scummio-tmp` 再從原版重新複製 LFL |
