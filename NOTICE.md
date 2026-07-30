# 版權與授權說明

## 本專案的產出（MIT）

`patches/`、`tools/`、`translations/`、`docs/`、`cht_table.json` 為本專案原創，採 MIT 授權（見 `LICENSE`）。

## 修改到的第三方軟體

| 專案 | 授權 | 本專案的改動 |
|---|---|---|
| [ScummVM](https://www.scummvm.org/) | GPLv3+ | `patches/scummvm-maniac-zhtw.patch`（`engines/scumm/` 共 6 個檔） |
| [ScummTR](https://github.com/dwatteau/scummtr) | MIT | `patches/scummtr-maniacv2-lossless.patch`（`src/ScummRp/block.cpp`、`src/ScummTr/text.cpp`） |

**散布修改過的 ScummVM 二進位檔時，必須依 GPLv3 一併提供對應的完整原始碼。** 本 repo 只提供 patch，套用對象是上游原始碼，因此使用者取得的原始碼與二進位檔一致。

## 字型

`chinese_gb16x12.fnt` 由 `tools/build_cht_font.py` 從 **WenQuanYi Zen Hei**（GPLv2 + 字體例外條款）的 embedded bitmap strike 產生。字型檔本身不入版控，由使用者在本機產生。

`tools/eten_font.py` 只是倚天中文系統點陣字檔格式的讀取實作，**不含任何字型資料**。

## 遊戲本體

《Maniac Mansion》的所有權利屬於原權利人。本 repo **不含**任何遊戲資料（`*.LFL`）、美術或音樂。`screenshots/` 內的截圖僅用於說明中文化成果。

## 說明書掃描件

軟體世界貴族版第 068 號《瘋狂大樓》中文說明書，掃描由「骨灰集散地」說明書補完計劃完成。依其公告要求：請勿在掃描檔加上其他符號或用來牟利。掃描件本身不入本 repo。
