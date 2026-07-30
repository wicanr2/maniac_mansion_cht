# 從原版重建中文版

需要自備兩樣東西，本 repo 都不含：

* 《Maniac Mansion》Enhanced DOS 版（v2）的 `00.LFL … 53.LFL`。
* 倚天中文系統 3.53 的點陣字檔 `STDFONT.15`、`SPCFONT.15`、`SPCFSUPP.15`，放在 `font-src/`。**三個都要**——`STDFONT.15` 只有漢字，全形標點在 `SPCFONT.15` 裡（漏帶會讓「，。！？「」」全部缺字）。

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

python3 tools/build_eten_font.py cht_table.json --eten-dir font-src --embolden \
        -o game-cht/mansiond/chinese_gb16x12.fnt --preview font-preview.png

cd game-cht/mansiond && cp ../../dumps/scummtr_zh.txt scummtr.txt
rm -f *scummio-tmp && scummtr -g maniacv2 -r -w -if
```

三個工具各自負責的事：

* **`merge_translation.py`** —— 併批、對齊固定寬度（`@` 補位、verb 排版空白）、把寫成空行的譯文還原成原文（scummtr 不收空行）。
* **`cht_codec.py`** —— 配碼位、產 `cht_table.json`、編成 latin-1 + CRLF；順便做像素級斷行（只作用在對白行，純 ASCII 行一律不動）與位元組自檢。
* **`build_eten_font.py`** —— 依碼表把倚天字形重排成 `chinese_gb16x12.fnt`（2232 字位 × 30 bytes = 66960 bytes）。stride 與倚天原生格式相同，漢字直接搬 30 bytes、不縮放；Big5 缺字才落到 TTF 備援。**`Big5 缺字 N 字` 這行是品質指標**：本作只該有 1 字（`・`），若一大批缺字就先懷疑索引公式或漏帶 `SPCFONT.15`。

`tools/build_cht_font.py` 是早期 12×12（WQY embedded bitmap）版本的烘字工具，留著備查，正式流程不用它。

### 5. 實機驗證

```bash
Xvfb :99 -screen 0 640x480x16 &
DISPLAY=:99 tools/scummvm-src/scummvm -p game-cht/mansiond \
    --auto-detect --no-fullscreen -e adlib --no-aspect-ratio &
DISPLAY=:99 import -window root shot.png
```

啟動 log 出現 `Loading CJK Font`、偵測結果標示 `Chinese (Simplified)`，就代表 ZH_CHN 路徑有進去。視窗會是 **640×400**（hi-res 文字表面），所以 Xvfb 開 640×480 剛好裝得下。

驗收項目：

- [ ] 原始美術 2× 放大正常，**沒有雪花／橫向錯位**（有 → `drawStripToScreen()` 的底圖放大沒生效）
- [ ] 指令列 15 個全中文，維持原版 5 欄 × 3 列、間距不重疊
- [ ] 句子列中文，下緣無殘影
- [ ] 對白逐字正確，**無字元級亂碼**（有 → 撞碼，回頭檢查碼空間）
- [ ] **無截字**（有 → renderer 字高／字寬，回頭檢查 `getDrawWidthIntern` / `getDrawHeightIntern`）
- [ ] 前後兩則訊息不疊字（有 → `restoreCharsetBg()` 沒清文字表面）
- [ ] 片頭字幕（純 ASCII）維持兩行、不需要按鍵翻頁
- [ ] 物品欄中文，不出現半個字

## 常見卡點

| 症狀 | 原因 |
|---|---|
| `ERROR: Modifying Maniac Mansion V2 is known to corrupt it` | 沒套 ScummTR patch，或沒開 `SCUMMRP_OK_TO_CORRUPT_MANIACV2` |
| `ERROR: char > 0x80 in line N` | 沒開 `SCUMMTR_CJK_CUSTOM_CODESPACE` |
| `ERROR: Empty lines are forbidden` | 譯文有真正的空行；`merge_translation.py` 會自動還原成原文 |
| `ERROR: Script error at 0x... in 07.LFL (roomOps)` | 原版資料遺留的孤立字串，無害（見 `00-engine-verification.md`） |
| 中文變成橫條噪點 | 字模高被截 → `getDrawHeightIntern()` |
| 畫面整片雪花／橫向錯位 | `_textSurfaceMultiplier=2` 但底圖沒放大 → `drawStripToScreen()` |
| 前後兩則訊息疊在一起 | 文字表面沒清 → `restoreCharsetBg()` |
| 字幕多出一個怪字並被截斷 | 撞到空白壓縮碼 → 碼空間首碼範圍 |
| 大批中文缺字（畫面空白或全是同一個字） | 漏帶 `SPCFONT.15`，或 Big5 分區索引寫錯 —— 用「`STDFONT.15` 的 idx=0 必須是『一』」當 oracle |
| import 中途失敗後再跑報「already exists」 | 殘留 `*.LFL~~scummio-tmp`，先 `rm -f *scummio-tmp` 再從原版重新複製 LFL |

## Deluxe（AGS 重製版）的重建流程

Deluxe 走的是完全不同的產線（`.tra` 翻譯檔 + TTF），工具在 `deluxe/tools/`：

```bash
# 1. 取遊戲資料：wine 裝一次 v1.4 多語版（見 40-deluxe.md）
#    裝完在 C:\Program Files (x86)\LucasFan Games\MMD

# 2. 抽原文（.tra 的鍵就是英文原文，14 份取聯集 = 1219 行）
python3 deluxe/tools/tra_codec.py keys game-orig-14/*.tra -o dumps/english14.txt

# 3. 檢查分批譯文（鍵對位／行數／token／後綴／字元／編碼，七項）
python3 deluxe/tools/check_batches.py dumps/english14.txt translations/deluxe

# 4. 產生 Chinese.tra（--utf8 會寫入 encoding hint）
cat translations/deluxe/b*.tsv > dumps/zh_all.tsv
python3 deluxe/tools/tra_codec.py build dumps/zh_all.tsv -o game-cht/Chinese.tra --utf8

# 5. 精簡字型（--fail-on-missing 會擋下缺字，例如 U+22EF）
python3 deluxe/tools/make_ags_font.py /usr/share/fonts/truetype/wqy/wqy-zenhei.ttc \
    -o agsfnt-zh.ttf --scale 1 --subset-from dumps/zh_all.tsv --fail-on-missing
for i in 0 1 2 3 4 5 6 7; do cp agsfnt-zh.ttf game-cht/agsfnt$i.ttf; done

# 6. 指定翻譯 + 字型尺寸
printf '[language]\ntranslation=Chinese\n' > game-cht/acsetup.cfg
printf '[scummvm]\nags_ttf_font_size=16\n' > scummvm.ini

# 7. 跑起來（binary 需含 AGS 引擎）
scummvm -p game-cht --auto-detect --config=scummvm.ini
```

`build-ags` 這份建置同時開了 SCUMM 與 AGS 兩個引擎，一支 binary 兩邊都能跑：

```bash
../configure --backend=sdl --enable-release --disable-debug \
  --disable-all-engines --enable-engine=ags --enable-engine=scumm
```

### Deluxe 的驗收項目

- [ ] 啟動 log 出現 `Translation initialized: Chinese (format: utf-8)`
- [ ] 標題／選角的提示與人物簡介是中文且不重疊
- [ ] 開場對白逐句中文，長句會自動折行
- [ ] 句子列組句正確（例如「查看 標示」）
- [ ] 動作回應是中文（查看告示牌 →「警告！！」）
- [ ] **省略號等標點畫得出來**（畫成空心方框 = 字型缺字，回頭看 `--fail-on-missing`）
- [ ] 指令按鈕維持英文是已知限制（sprite，不是文字）
