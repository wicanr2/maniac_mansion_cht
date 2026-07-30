# 引擎與工具修補清單

兩份 patch，共 217 行新增（含中文註解）／12 行刪除：

| 檔案 | 對象 | 規模 |
|---|---|---|
| `patches/scummvm-maniac-zhtw.patch` | ScummVM（`engines/scumm/`，6 個檔） | +173 / −12 |
| `patches/scummtr-maniacv2-lossless.patch` | ScummTR（`src/ScummRp/`、`src/ScummTr/`） | +44 / −0 |

ScummTR 那份的兩處改動都以巨集開關包住，預設行為與上游完全相同。

## 碼空間（先講這個，其餘修補都建立在它上面）

自訂雙位元組編碼：**首碼 `0x88–0x9F`（24 個）、尾碼 `0xA1–0xFD`（93 個）→ 2232 個字位**，本作實際用掉 1000 字。字型索引 `idx = (lead - 0x88) * 93 + (trail - 0xA1)`。

首碼範圍是**推導出來的，不是沿用慣例**。SCUMM v2 的腳本字串有一套空白壓縮：「位元組 | 0x80」表示「這個字元後面接一個空白」，解壓在 `ScummEngine_v2::decodeParseString()`：

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

（`0x04–0x07` 是帶參數的控制碼，ScummTR 的 `_spaceCharToBit` 不壓縮它們，但首碼避開 `0x84–0x87` 仍留了餘裕。）

## ScummVM

### 1. `charset.cpp` `loadCJKFont()` — 讓 v2 進得了 ZH_CHN 路徑

原本的 gate 是 `_game.version >= 3 && _language == ZH_CHN`，把 SCUMM v1/v2 整批擋在外面。Zak 是 v3，當年只需要在裡層的 GID 白名單加一筆；本作是 v2，連外層版本判斷都過不了，所以兩層都要動。

### 2. `charset.cpp` ZH_CHN 分支 — 加入 `GID_MANIAC`

設 `fontFile = "chinese_gb16x12.fnt"`、`numChar = 2232`。字型檔名沿用原本的，因為 `detection_internal.h` 的 `detectLanguage()` 就是看這個檔名決定要不要切 ZH_CHN，而它**沒有版本限制**，所以偵測那一側不必改。

### 3. `charset.cpp` `get2byteCharPtr()` — 自訂索引公式

原本是 GB2312 區位碼 `(lead-0xA1)*94 + (trail-0xA1)`；本作換成 `(lead-0x88)*93 + (trail-0xA1)`，並對範圍外的組合回第 0 個字形而不是算出負索引。

### 4. `charset.cpp` `CharsetRendererV3::getDrawHeightIntern()` — CJK 字高

原本固定 `return 8`。中文 12px 會被截成上半 8 列，畫面上看起來像橫條噪點而不是「字太小」。

### 5. `charset.h` / `charset.cpp` `CharsetRendererV2::getCharWidth()` — CJK 字寬

**這是 v2 專屬的雷。** `CharsetRendererV2` 覆寫了 `getCharWidth()` 並固定回 8，而 `CharsetRendererV3::getDrawWidthIntern()` 是轉呼叫 `getCharWidth()`，所以 v2 的中文字寬會全部算成 8，字距整排錯開。Zak 走 `CharsetRendererV3`，不會遇到。

實作從標頭移到 `.cpp`，因為要讀 `ScummEngine` 的成員。

### 6. `charset.cpp` `CharsetRendererCommon::getFontHeight()` — 行距只在需要時放大

CJK 模式原本一律回 `MAX(_2byteHeight + 1, _fontHeight)` = 13。但 v2 的文字區高度是腳本呼叫 `initScreens(b, h)` 給的 `b`（見 `initVirtScreen(kTextVirtScreen, adj, _screenWidth, b, ...)`），片頭字幕那類畫面只給 **16px = 剛好兩行 8px**。行距一律 13 的話，這些**沒有中文**的原版字幕第二行會被文字區裁掉一半。

改成：只有 `_force2ByteCharHeight` 為真（這則訊息確實含雙位元組字）才用 13px，否則維持原版 8px。這個旗標是引擎既有機制（SegaCD / Indy4 日文版就這樣用）。

### 7. `string.cpp` `CHARSET_1()` — 補上 `_force2ByteCharHeight`

`drawString()` 那條路徑會設這個旗標，但 v2 對白走的 `CHARSET_1()` 不會。在它組合雙位元組字的地方補上，第 6 項才成立。

### 8. `script_v2.cpp` `decodeParseString()` — 中文原樣通過

首碼落在 `0x88–0x9F` 時，把該位元組與下一個位元組原樣寫進緩衝區，不做 `&= 0x7f`、也不補空白。**沒有這一項，中文完全進不了對白。**

### 9. `actor.cpp` `actorTalk()` — 中文訊息自動分頁

中文行高 13px、英文 8px，同一段訊息在中文下高了 1.6 倍，可能超出文字區（被裁）或蓋到畫面下方的指令列。

作法是把超出上限的換行控制碼 `0xFF 0x01` **就地改成等待點擊 `0xFF 0x03`**：兩個位元組換兩個位元組，長度不變、不必搬移緩衝區，而且 `0x03` 是原版資料本來就在用的分頁碼（例如門鈴那段長描述），`countNumberOfWaits()` 也認得，所以按一下就翻頁、talk delay 會跟著重算。

每頁行數上限**依當前畫面的文字區高度推算**，不寫死：`_screenB > 0` 時用它（片頭 16 / 13 = 1 行），否則用房間畫面高度（144 / 13 ≈ 11 行）。並且只對真的含中文的訊息生效——純 ASCII 的原版字幕維持 8px 兩行，不該被改成一頁一頁按。

### 10. `script_v2.cpp` `o2_verbOps()` — 指令列改 2 列排版

原版 15 個指令是 5 欄 × 3 列 × 8px（畫面 y 152–175，共 24px）。中文字高 12px 塞不進 8px 列距，但 24px 剛好等於 2 列 × 12px，所以改成 8 + 7 的兩列，**完整留在原有區帶內，不動畫面其他部分**。

欄距 40px；譯文用 `@` 補到 5 bytes，`drawVerb()` 算出的 `curRect.right = left + (6-1)*8 = left + 40` 剛好等於欄距，中文指令最寬 2 字 = 24px，相鄰指令的可點範圍不會重疊。`drawVerb()` 用 `curRect.top/left` 定位、`curRect.bottom` 由實際字串範圍決定，所以看到的位置與點到的位置自然一致，`findVerbAtPos()` 不必改。

判斷條件是「資源長度剛好 6」，因此：片頭裝飾用的長字串、選角名牌、存檔欄位都不受影響；指令若還是英文（原始長度 8–10）這段也不會生效，patch 會自動失效而不是弄壞畫面。

### 11. `verbs.cpp` `initV2MouseOver()` / `redrawV2Inventory()` — 物品欄列距與截字

物品欄兩列改成 11px 列距、起點下移到 34（指令畫面 56px 的配置：句子列 0–11、指令兩列 11–35、物品欄 34–55）。

另外原本的 `strncpy(msg, tmp, maxChars)` 是按 byte 截斷，可能把雙位元組字砍成半個（只留首碼）→ 畫面上出現一個亂碼字。改成往前掃到最後一個完整的字再切。

### 12. `string.cpp` `ScummEngine_v2::drawSentence()` — 句子列清除高度

原本只清 8px，中文句子列高 12px 會在下緣留下殘影。清到 11px（指令第一列從 11 開始，各自負責自己的區塊）。

## ScummTR

### A. `block.cpp` `OldRoom::_cleanup()` — 保留共用的物件圖位移

以 `SCUMMTR_PRESERVE_AMBIGUOUS_OI` 開關包住。詳細根因分析見 `00-engine-verification.md`。

### B. `block.cpp` `LFLFile` / `OldLFLFile` 建構子 — 保留原版自帶的死索引

以 `SCUMMTR_KEEP_DANGLING_INDEX_ENTRIES` 開關包住。同上。

### C. `text.cpp` `_spaceCharToBit()` / `_spaceBitToChar()` — CJK 通道

以 `SCUMMTR_CJK_CUSTOM_CODESPACE` 開關包住。原本 `_spaceCharToBit()` 遇到任何 ≥ 0x80 的位元組就 `throw Text::Error("char > 0x80 in line %i")`，中文連 import 都進不去。改成：首碼落在 `0x88–0x9F` 時，該位元組與下一個原樣通過、不參與空白壓縮。`_spaceBitToChar()`（匯出方向）同步處理，這樣中文版本也能再抽出來比對。

### 建置參數

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
