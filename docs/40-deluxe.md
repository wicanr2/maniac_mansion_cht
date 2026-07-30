# Maniac Mansion Deluxe（AGS fan remake）中文化：現況

## 它不是 SCUMM，但確實可以用 ScummVM 跑

Maniac Mansion Deluxe 是 2004 年 Lucasfan Games 的同人重製版，用 **AGS（Adventure Game Studio）** 製作，不是 LucasArts 的 SCUMM 引擎。

不過 **ScummVM 2.6 起內建 AGS 引擎**，所以「掛進 ScummVM 執行」這件事是成立的——只是中文化路徑與 SCUMM 完全是另一條產線：

| | SCUMM v2（本作原版） | AGS（Deluxe） |
|---|---|---|
| 文字所在 | `*.LFL` 內的 script / object 區塊 | 遊戲資料檔內的 script / GUI |
| 抽填工具 | ScummTR | AGS 的翻譯機制（`.trs` → `.tra`） |
| 字型 | 引擎讀 `chinese_gb16x12.fnt` | AGS 自己的 `.wfn` 點陣字或 TTF |
| 需要的引擎修補 | 本專案的 12 處 | 理論上不需要（AGS 有原生翻譯與 TTF 支援） |

所以 SCUMM 那邊做的碼空間、字型烘製、renderer 修補**都不能沿用**；能沿用的只有譯名表（`docs/10-glossary.md`）。

## 安裝器的分析結果

手上兩個檔案：

| 檔案 | 大小 | 日期 | 備註 |
|---|---|---|---|
| `manicmdsetup.exe` | 5 826 271 | 2004-06-29 | 較接近初版 |
| `Maniac-Mansion-Deluxe_Win_EN-FR-ES-DE-IT.exe` | 6 598 337 | — | 多語版 |

兩個是**同一款私有安裝器**，證據：

* PE32 結構完全相同（4 個 section、`.text` 61440 / `.rdata` 8192 / `.data` 12288 / `.rsrc` 4096），程式碼只有 90 KB，其餘全是 overlay。
* overlay 的前 32 個位元組完全一致：`39 12 01 00 3f 03 00 00 cc 09 00 00 9e 6b 9e 1d …`
* 特徵字串：`_inst%d.exe`、`#InstallDir#`、`rundll32 desk.cpl,InstallScreenSaver %s`、`regsvr32 /s %s`、`Software\Microsoft\Windows\CurrentVersion\SharedDLLs`

不是 Inno Setup、NSIS、7z-SFX、CAB 或 RAR-SFX——全檔搜不到任何一種的 magic。overlay 是**多段 zlib 流**（能找到多個 `78 9c` / `78 da` / `78 01` 檔頭），中間夾私有的目錄結構。因此 `7z`、`innoextract`、`cabextract` 都吃不下。

同時也確認：全檔搜不到 `CLIB`、`SIGE`、`acsetup.cfg`、`Adventure Game Studio` 等 AGS 特徵字串，也就是**遊戲資料是壓縮在 overlay 裡的**，不能直接切出來。

## 取得資料檔：用 wine 實際安裝一次

比逆向這個私有安裝器格式便宜得多，而且結果可靠。安裝器的預設鈕就是 Next / Install，所以連續送 Enter 就能點完（`deluxe-install.sh`）：

```bash
docker build -t mm-cht:wine docker-wine/     # FROM mm-cht:dev + wine wine32 wine64
docker run --rm -v "$PWD:/work" -w /work mm-cht:wine bash /work/deluxe-install.sh
```

兩個踩過的坑：

* **`WINEPREFIX` 不能放在 bind mount 上**——容器裡是 root，而掛進來的目錄屬於 uid 1000，wine 會直接拒絕：`is not owned by you, refusing to create a configuration directory there`。prefix 留在容器內的 `/tmp`，裝完再把遊戲目錄複製出來。
* **安裝目的地不是 `Program Files`**，是 `C:\Program Files (x86)\LucasFan Games\MMD`。用 `find -iname "*Maniac*"` 找不到（資料夾叫 `MMD`）。

裝出來的內容：

| 檔案 | 說明 |
|---|---|
| `Maniac.exe`（9.4 MB） | AGS 主程式 + 內嵌 CLIB（`CLIB\x1a` 版本 11，`ac2game.ags`） |
| `Maniac.001` … `Maniac.005` | 分卷資料檔 |
| `speech.vox` | 語音 |
| `German.tra` / `French.tra` / `Spanish.tra` | **原廠翻譯檔** |
| `AGSflashlight.dll` | AGS 外掛（手電筒效果） |
| `winsetup.exe`、`Uninstal.exe`、`autorun.*`、`manual*.htm` | 設定／安裝周邊 |

## `.tra` 已經把可翻譯字串集送到手上

隨遊戲附的三份 `.tra` 讓這件事變簡單：**`.tra` 的鍵就是英文原文**，所以不需要 AGS Editor、也不需要 `.trs` 範本，直接解出來就是完整字串集。

| 檔案 | 對照組數 |
|---|---|
| `German.tra` | 1091 |
| `French.tra` | 1117 |
| `Spanish.tra` | 1126 |
| **原文聯集** | **1131** |

（三者數目不同是因為各語言各自漏翻了一些行；取聯集才是完整集合。規模和 SCUMM v2 原版的 1139 行相當。）

格式依 ScummVM `engines/ags/shared/game/tra_file.cpp` 與 `util/data_ext.cpp` 讀出來，不是猜的：

```
"AGSTranslation\0"        15 bytes
迴圈 {
    int32 blockID          1=Dict, 2=GameID, 3=TextOpts, 0=字串 ID 擴充區塊, -1=結束
    int32 blockLen
    ...
}
```

字串加密是逐位元組**減去** `"Avis Durgan"`（`decrypt_text()`），不是 XOR；寫回去用加法。

兩個「原版寫壞但引擎容忍」的細節，照抄才能 byte-perfect：

* **GameID 區塊長度少算 1**——ScummVM 的 `GetOverLeeway(kTraFblk_GameID)` 回 1 就是在容忍它。因此解析時位置要以「實際讀到哪」為準，不能硬跳 `blockLen`。
* **TextOpts 宣告 12 bytes 卻寫了 16**——多出來的那 4 個 `FF` 其實是 `-1` 結束標記，後面還跟著 4 個 0。

`deluxe/tools/tra_codec.py` 實作了 dump / keys / build 三個動作，並以「解出來 → 原樣重建 → 逐位元組比對」驗證過：**German / French / Spanish 三份全部 byte-perfect**（與 SCUMM 那邊要求 round-trip diff=0 是同一條紀律）。

```bash
python3 tra_codec.py dump German.tra -o de.tsv
python3 tra_codec.py keys German.tra French.tra Spanish.tra -o english.txt
python3 tra_codec.py build zh.tsv -o Chinese.tra --utf8
```

## 中文顯示：兩個機制看起來讓引擎不必改

讀 ScummVM 的 AGS 引擎原始碼後，有兩件事對中文化很關鍵：

1. **翻譯檔可以自己宣告編碼。** `init_translation()` 讀 `StrOptions["encoding"]`，值是 `utf-8` 就 `set_uformat(U_UTF8)`——**這個判斷與遊戲本身的版本無關**，所以 2004 年的 AGS 2.x 遊戲也能靠這個 hint 走 UTF-8 文字路徑。字典的鍵維持原文的單位元組編碼，引擎有對應的 mixed-encoding 處理。`tra_codec.py --utf8` 就是在寫這個區塊（新式字串 ID 區塊 `ext_sopts`）。
2. **TTF 可以用鬆散檔覆蓋內建點陣字。** `fonts.cpp` 載入字型時**先試 `agsfnt%d.ttf`**，失敗才回頭找 `agsfnt%d.wfn`（`ttf_font_renderer.cpp:121`、`wfn_font_renderer.cpp:124`）。所以把一份中文 TTF 放在遊戲目錄下命名成對應的槽位，就能取代原本的英文點陣字。

也就是說 Deluxe 這條線**目前看起來不需要引擎修補**，與 SCUMM v2 那邊完全相反。但這兩點都還只是讀碼得到的結論，**尚未實機驗證**——下一步就是拿一小段試譯跑 ScummVM 的 AGS 引擎確認。

## 待辦

1. 實機驗證上面兩點：小樣中文 `.tra` + 一份中文 TTF → 看是否正確顯示、行寬與換行是否合理。
   （我們自編的 ScummVM 目前是 `--disable-all-engines --enable-engine=scumm`，要另外編一份含 AGS 引擎的。）
2. 決定字型：AGS 的字型槽有大小設定，中文在低解析度下要挑點陣感清楚的；必要時把倚天 16×15 轉成 TTF 內嵌點陣。
3. 翻譯 1131 行：譯名沿用 `docs/10-glossary.md`，台詞獨立翻譯（Deluxe 有重寫與新增內容，不能直接套 v2 譯文）。
4. 產出物放在本 repo 的 `deluxe/`；**遊戲資料與原廠 `.tra` 不入公開 repo**。
5. 待確認的版權問題：`.tra` 的鍵一定是英文原文，等於中文譯檔裡會夾帶完整英文台詞。要不要放上公開 repo，先問過再說。
