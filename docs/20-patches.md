# 引擎與工具修補清單

| 檔案 | 對象 | 規模 |
|---|---|---|
| `patches/scummvm-maniac-zhtw.patch` | ScummVM（`engines/scumm/`，4 個檔） | +134 / −3 |
| `patches/scummvm-ags-cjk-fontsize.patch` | ScummVM（`engines/ags/`，1 個檔；Deluxe 用） | +13 / −0 |
| `patches/scummtr-maniacv2-lossless.patch` | ScummTR（`src/ScummRp/`、`src/ScummTr/`） | +44 / −0 |

ScummTR 那份的三處改動都以巨集開關包住，預設行為與上游完全相同。

## 走 hi-res 文字表面（決定其餘一切的選擇）

**中文字用倚天中文系統 (ETEN 3.53) 的 16×15 原生點陣字，畫在放大 2 倍的文字表面上。**

這與 ScummVM SCI 引擎中文化的作法同源：SCI 在 `ZH_TWN` 下切 `GFX_SCREEN_UPSCALED_640x400`，原始美術照舊 2× nearest 放大，但中文字改用 hi-res 字型直接繪進 display buffer，繞過整體 nearest 放大 → 同一畫面「美術照原樣、中文銳利」。SCUMM 對應的機制就是 `_textSurfaceMultiplier = 2`。

選它的理由是**幾何上的必然**，不是偏好：

* 指令畫面（`kVerbVirtScreen`）總共只有 56 個邏輯像素要容納五列文字（句子列 + 指令 3 列 + 物品欄 2 列），列距上限 11px。
* 倚天沒有 12 點字（光碟只有 15 點與 24 點），而把 15 點機器縮到 12×12 實測會讓「讀」「觸」這類筆畫多的字糊成一團。
* 文字表面放大 2 倍之後，**16×15 的字模只佔 8×7.5 個邏輯像素**——與原版 8×8 的 ASCII 幾乎同尺寸。於是指令列 3 列 × 8px、16px 的文字區兩行、行距全都不必改。

也就是說：拉畫布不只解決了字形來源，還讓**整批版面修補變成不需要**。第一版（12×12 字型、不拉畫布）為了塞下 12px 中文，動了指令列 2 列重排、物品欄列距、句子列清除高度、行距、自動分頁共五處版面邏輯；改走 hi-res 之後這些全部撤掉，patch 從 6 檔 173 行縮到 **4 檔 134 行**。

### 邏輯像素 vs 字模像素

這是最容易搞錯的地方。慣例照抄引擎裡現成的 m=2 CJK 使用者（`CharsetRendererTownsV3`）：

| 函式 | 回傳 | 值 |
|---|---|---|
| `getCharWidth()` | **邏輯**推進寬 | 8 |
| `getFontHeight()` | **邏輯**行高 | 8 |
| `getDrawWidthIntern()` | **字模**寬（給 `drawBits1`） | 16 |
| `getDrawHeightIntern()` | **字模**高 | 15 |

換算由 `printChar()` 裡本來就有的這段負責，不必自己算：

```cpp
if (is2byte) {
    origWidth /= _vm->_textSurfaceMultiplier;
    height /= _vm->_textSurfaceMultiplier;
}
_left += origWidth;
```

## 碼空間

自訂雙位元組編碼：**首碼 `0x88–0x9F`（24 個）、尾碼 `0xA1–0xFD`（93 個）→ 2232 個字位**，本作實際用掉 1000 字。字型索引 `idx = (lead - 0x88) * 93 + (trail - 0xA1)`，每字 `((16+7)/8) * 15 = 30` bytes——**與倚天 `STDFONT.15` 的原生 stride 完全相同**，所以漢字與標點都是直接搬 30 bytes，不做任何縮放。

首碼範圍是推導出來的。SCUMM v2 的腳本字串有空白壓縮：「位元組 | 0x80」表示「這個字元後面接一個空白」，解壓在 `ScummEngine_v2::decodeParseString()`：

```cpp
insertSpace = (c & 0x80) != 0;
c &= 0x7f;                       // ← 中文首碼會在這裡被砍掉
```

所以首碼必須避開所有壓縮得出來的值：

| 來源 | 壓縮後 |
|---|---|
| 可列印 ASCII `0x20–0x7E` \| `0x80` | `0xA0–0xFE` |
| SCUMM 控制碼 `0x01–0x03` \| `0x80` | `0x81–0x83` |

第一版取 `0x80–0x9F` 時只算了第一列，結果片頭字幕 `by\001     Ron` 的 `\001` 後面接空白、被壓成 `0x81`，落進首碼區被誤判成中文，畫面上多出一個亂碼字並把整行截掉。收窄到 `0x88–0x9F` 後，首碼與「壓縮碼／原始控制碼 `0x01–0x07`／原始 ASCII `0x20–0x7E`」三者都不重疊，可證明無歧義。

## ScummVM（4 個檔）

### `charset.cpp`（7 處）

1. **`loadCJKFont()` 的版本 gate** —— 原本是 `_game.version >= 3 && _language == ZH_CHN`，把 SCUMM v1/v2 整批擋在外面。Zak 是 v3，當年只需在裡層的 GID 白名單加一筆；本作是 v2，連外層版本判斷都過不了。
2. **ZH_CHN 分支加入 `GID_MANIAC`** —— 設 `fontFile = "chinese_gb16x12.fnt"`、`numChar = 2232`。字型檔名沿用原本的，因為 `detection_internal.h` 的 `detectLanguage()` 就是看這個檔名決定要不要切 ZH_CHN，而它**沒有版本限制**，偵測那一側不必改。
3. **字模尺寸與 hi-res** —— `_textSurfaceMultiplier = 2`，字模尺寸**由字型檔的大小決定**：`numChar × 30` bytes 是 16×15（倚天 15 點）、`numChar × 72` 是 24×24（倚天 24 點）。這樣換字型檔就等於換尺寸，不必另外開設定。
4. **`get2byteCharPtr()`** —— 自訂索引公式，並對範圍外的組合回第 0 個字形而不是算出負索引。
5. **`CharsetRendererCommon::getFontHeight()`** —— CJK 模式原本回 `MAX(_2byteHeight + 1, _fontHeight)`；hi-res 下這裡要的是**邏輯**行高，改回 `MAX(_2byteHeight / _textSurfaceMultiplier, _fontHeight)`——16×15 得 8（與原版同）、24×24 得 12。比照 `CharsetRendererTownsV3` 的做法。
6. **`CharsetRendererV3::getDrawWidthIntern()` / `getDrawHeightIntern()`** —— 回**字模**尺寸（`_2byteWidth` / `_2byteHeight`）。後者原本固定回 8，會把中文字截成上半段，畫面上看起來像橫條噪點而不是「字太小」。
7. **`CharsetRendererV3::printChar()`** —— hi-res 模式下**所有**文字都畫到文字表面。原本 `hasTwoBuffers == false` 的畫面（指令列所在的 `kVerbVirtScreen`、片頭字幕的 `kTextVirtScreen`）會把字直接畫進 1 倍的虛擬螢幕；若只把中文導到 2 倍的文字表面、ASCII 留在虛擬螢幕，兩邊清除時機不一致，畫面會出現前後兩則訊息疊字。ASCII 由 `drawBits1()` 既有的 `scale2x` 自動放大。

### `gfx.cpp`（2 處）

8. **`drawStripToScreen()` 補上底圖 2× nearest 放大** —— 這是整條 hi-res 路真正缺的一塊。原本的合成迴圈會跑 `(height*m) × (width*m)` 個目的像素，但 `src` 是**線性**讀取 1 倍的底圖：

   ```cpp
   for (int h = height * m; h > 0; --h)
       for (int w = width * m; w > 0; w -= 4) {
           uint32 temp = *text32++;                       // 2x 的文字表面
           *dst32++ = ((temp ^ *src32++) & mask) ^ temp;   // 1x 的底圖，線性讀
   ```

   m=2 時底圖整片錯位 → 雪花。這正是「DOS 版 SCUMM 不能設 `_textSurfaceMultiplier=2`」這個結論的成因；缺的其實只是「底圖也要放大」這一步。補上一條專用合成迴圈（每兩個目的列才前進一個來源列、每個來源像素橫向用兩次）之後就成立了。

   代價：這條路徑直接送 `copyRectToScreen`，跳過 `postProcessDOSGraphics()`，因此與 CGA / Hercules 這類需要後處理的 render mode 不相容（預設 EGA/VGA 下那個函式本來就會立刻 return）。

9. **`restoreCharsetBg()` 補清文字表面** —— 原本的 `clearTextSurface()` 只在 `vs->hasTwoBuffers` 時執行，因為原設計裡 `kTextVirtScreen` / `kVerbVirtScreen` 的文字是直接畫進虛擬螢幕、由前面的 `memset` 清掉。第 7 項把所有文字改到文字表面之後這些畫面就沒人清，畫面會疊字。這裡只清該虛擬螢幕對應的那一塊，不動其他畫面（例如指令列）已經畫好的文字。

### `script_v2.cpp`（1 處）

10. **`decodeParseString()` 讓中文原樣通過** —— 首碼落在 `0x88–0x9F` 時，該位元組與下一個原樣寫進緩衝區，不做 `&= 0x7f`、也不補空白。**沒有這一項，中文完全進不了對白。**

### `verbs.cpp`（1 處）

11. **`redrawV2Inventory()` 的雙位元組安全截字** —— 原本 `strncpy(msg, tmp, maxChars)` 是按 byte 截斷，可能把雙位元組字砍成半個（只留首碼）→ 畫面上出現一個亂碼字。改成往前掃到最後一個完整的字再切。

## ScummVM／AGS（Deluxe 用，1 個檔）

12. **`ttf_font_renderer.cpp` 允許用 config 覆寫 TTF 名目尺寸** —— AGS 3.0 以前的遊戲資料裡字型槽沒有 size 欄位，替換進去的 TTF 一律以 8px 載入，中文無法閱讀。這個「名目尺寸」同時決定行距（`FontMetrics.NominalHeight`），所以**不能靠改字型檔繞過**：把字型的 `unitsPerEm` 改小確實會讓字形與推進寬一起放大（用 FreeType 量過），但行距仍停在 8px，上下兩行必疊。

    修補做兩件事，兩個鍵都是沒設就完全維持原行為：

    * `ags_ttf_font_size` —— 全域覆寫。Deluxe 用 24（畫面跑 640×400）。
    * `ags_ttf_font_size_<槽號>` —— 單一字型槽覆寫。同一個遊戲裡不同槽的可用空間不一樣：Deluxe 的句子列上方只有約 18px 的空檔，24px 的字下緣會被指令列按鈕的圖蓋掉，所以句子列那一槽（12）另外設 16。詳見 `40-deluxe.md`。

## ScummTR（2 個檔）

### A. `block.cpp` `OldRoom::_cleanup()` — 保留共用的物件圖位移

以 `SCUMMTR_PRESERVE_AMBIGUOUS_OI` 開關包住。根因分析見 `00-engine-verification.md`。

### B. `block.cpp` `LFLFile` / `OldLFLFile` 建構子 — 保留原版自帶的死索引

以 `SCUMMTR_KEEP_DANGLING_INDEX_ENTRIES` 開關包住。同上。

### C. `text.cpp` `_spaceCharToBit()` / `_spaceBitToChar()` — CJK 通道

以 `SCUMMTR_CJK_CUSTOM_CODESPACE` 開關包住。原本 `_spaceCharToBit()` 遇到任何 ≥ 0x80 的位元組就 `throw Text::Error("char > 0x80 in line %i")`，中文連 import 都進不去。改成：首碼落在 `0x88–0x9F` 時，該位元組與下一個原樣通過、不參與空白壓縮。`_spaceBitToChar()`（匯出方向）同步處理，這樣中文版本也能再抽出來比對。

## 建置參數

```bash
# ScummTR
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="\
  -DSCUMMTR_PRESERVE_AMBIGUOUS_OI \
  -DSCUMMTR_KEEP_DANGLING_INDEX_ENTRIES \
  -DSCUMMTR_CJK_CUSTOM_CODESPACE \
  -DSCUMMRP_OK_TO_CORRUPT_MANIACV2"

# ScummVM
./configure --backend=sdl --enable-release --disable-debug \
  --disable-all-engines --enable-engine=scumm
```

## 回歸測試

每次改完 ScummTR 都要重跑「英文原封回填 → 逐檔 byte 比對」，確認 **54 個 LFL 全部 byte-perfect**。這個測試同時證明：CJK 通道沒有影響原本的 ASCII 行為，而且未翻譯的行在回填後與原版完全一致。
