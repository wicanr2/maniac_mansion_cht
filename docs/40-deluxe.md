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

## 取得資料檔的作法

用 wine 在容器內實際安裝一次，再把安裝出來的檔案撈出來。比逆向這個私有安裝器格式便宜得多，而且結果可靠。

```bash
docker build -t mm-cht:wine docker-wine/     # FROM mm-cht:dev + wine wine32 wine64
docker run --rm -v "$PWD:/work" -w /work/deluxe mm-cht:wine bash -c '
  export HOME=/tmp WINEPREFIX=/tmp/wp DISPLAY=:99 WINEDEBUG=-all
  Xvfb :99 -screen 0 1024x768x24 & sleep 2
  wineboot -i; wine manicmdsetup.exe   # 需要時用 xdotool 點過安裝畫面
'
```

## 後續步驟（尚未進行）

1. 解出遊戲資料，確認 AGS 版本（看 `acsetup.cfg` 與主 exe 的 `CLIB` 版本號）。
2. 用 AGS 的翻譯機制抽字：`agstra` / `AGS Editor` 可以從遊戲產生 `.trs` 範本。
3. 決定字型路徑：AGS 支援 TTF，所以中文很可能不需要自製點陣字；若該版本只吃 `.wfn`，就要烘一份。
4. 譯名沿用 `docs/10-glossary.md`；台詞獨立翻譯（Deluxe 有重寫與新增的內容）。
5. 產出物放在本 repo 的 `deluxe/` 子目錄。
