# 引擎與工具修補清單

| 檔案 | 對象 | 規模 |
|---|---|---|
| `patches/scummvm-maniac-zhtw.patch` | ScummVM（`engines/scumm/`，9 個檔） | +235 / −17 |
| `patches/scummvm-maniac-cht-all.patch` | 上面那份 ＋ `engines/ags/`（2 個檔），發行版用的完整 diff | +287 / −17 |
| `patches/scummvm-ags-cjk-fontsize.patch` | ScummVM（`engines/ags/`，1 個檔；Deluxe 字級） | +13 / −0 |
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

## ScummVM（8 個檔）

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

### `scumm.cpp`（1 處）

11. **24×24 時把畫布加高** —— 指令區要放 6 列文字（句子列 1 + 指令 3 + 物品欄 2），一列 14 個邏輯像素（字模 12 + 2 的行距）共 84，而原版的 144–200 只有 56。上方那條字幕帶也要跟著加高：它原本是 16 像素 = 剛好兩行 8 像素的字，CJK 行高變成 14 之後兩行要 28，不加高的話第二行會畫到帶子外面，而 `restoreCharsetBg()` 只清帶子那麼高，上一則訊息的殘影就留在下面、新的字疊上去糊成一團（片頭製作名單第二行就是這樣壞的）。

    所以畫面總高從 200 改成 **240**（字幕帶 28 + 房間 128 + 指令區 84），`initScreens(16, 144)` 跟著改成 `initScreens(28, 156)`——房間仍是完整的 128 列。這一步要在 `initGraphics()` 之前做，所以放在 `loadCJKFont()` 之後。

### `verbs.cpp`（3 處）

12. **`redrawV2Inventory()` 的雙位元組安全截字** —— 原本 `strncpy(msg, tmp, maxChars)` 是按 byte 截斷，可能把雙位元組字砍成半個（只留首碼）→ 畫面上出現一個亂碼字。改成往前掃到最後一個完整的字再切。

13. **`initV2MouseOver()` 的 14 格制** —— 24×24 時指令區一列從 8 改成 14、物品欄從相對 32 移到 56。這些矩形同時是**點擊判定區**，改了之後滑鼠命中會自己跟著走（實測點「查看」會正確反白）。`o2_verbOps()` 那邊把腳本給的 8 格制絕對座標（句子列 144、指令三列 152/160/168）換算成以 156 起算的 14 格制。

13b. **`checkExecVerbs()` 的分區界線也要跟著 14 格制**（GitHub issue #1 第二輪） ——
    這裡自己又算了一次「句子列到哪、物品欄從哪開始」，而且寫死 `topline + 8` 與
    `inventoryArea = 32`。14 格制下指令三列落在相對 14–55，於是 `y >= 32` 的那一段
    （第二列的下半 + 整個第三列）被判成**物品欄點擊**，交給 `checkV2Inventory()`；
    那支又要求 `y >= 56` 才算數，所以直接 return 0 —— 點下去什麼都不會發生。
    反白照常，因為 hover 走的是 `initV2MouseOver()` 的矩形（早就是 14 格制）。
    症狀因此是「文字完整、滑過會變色、第一列點得動、二三列點不動」。

    修法是四處共用同一個來源 `getSentenceLineHeight()`：
    `inventoryArea = 4 * rowH`（8 → 32、14 → 56，非中文行為完全不變）。
    這個數字先前散在 `initV2MouseOver` / `checkV2Inventory` / `redrawV2Inventory` /
    `checkExecVerbs` 四個地方，改了三個漏一個就是這個 bug。

    驗收用可重跑的迴圈（`workplace/verbclick-test.sh`）：15 格逐一「先點走到當基準 →
    點目標格 → 比對句子列的像素雜湊」。修之前 10 格沒反應，修之後 14 格全變
    （「走到」那格因為基準就是它，本來就不會變）。

### `string.cpp` / `gfx_gui.cpp` / `scumm.h`（句子列殘影，GitHub issue #1）

14. **句子列的清除高度跟著字高走** —— `ScummEngine_v2::drawSentence()` 與 `printMessageAndPause()`
    都寫死「清掉指令區最上面 8 條掃描線」再重畫。24×24 的中文句子佔 14 條，只清 8 條的話
    下面 6 條會留著上一句。改成呼叫新的 `getSentenceLineHeight()`（24×24 時回傳 14，其餘回傳 8）。

15. **`restoreBackground()` 要一併清文字表面** —— 上一項改完症狀還在，因為真正的原因更底層：
    hi-res 模式的中文是畫在**文字表面**上的，而 `restoreBackground()` 只在
    `hasTwoBuffers`（房間畫面）或 `_macScreen` 時清文字表面。指令列這種沒有雙緩衝的虛擬螢幕
    原本靠 `fill()` 把字一起蓋掉，文字表面沒人清 → 句子列每次重畫都疊上去。
    這與先前 `restoreCharsetBg()` 的修補同源，補上同一個條件即可。

    使用者回報的畫面就是這個：按空白鍵暫停，英文的暫停訊息疊在中文句子上（issue #1）。

    補完這一項之後浮出一個原本被蓋住的排版錯誤：`redrawV2Inventory()` 的物品欄起點寫成
    相對 48，但 `initV2MouseOver()` 的 `invTop` 是 56（句子列 14 + 指令三列 42）。
    差的這 8 列剛好吃掉指令第三列的下半截。之前看不出來，是因為那個清除只作用在
    虛擬螢幕緩衝區、而中文畫在文字表面上；文字表面也一起清了之後才顯形。兩處改成一致的 56。

### `dialogs.cpp`（v1/v2 的三則系統訊息，1 處）

16. **補上 ZH_CHN 的暫停／重新開始／離開訊息** —— 這三則是各語言各自寫死在直譯器裡的
    （`getStaticResString()` 的 `strMap1`），官方沒有中文版，所以中文版會冒出英文
    `Game paused, press SPACE to continue.`。補一組用本專案碼空間編出來的中文字串，
    限定 `GID_MANIAC + version 2 + ZH_CHN` 才生效（位元組要配遊戲夾裡的字型才畫得出來）。
    結尾的 `(y/n)y` 保持 ASCII——引擎是拿字串**最後一個字元**當「確定」鍵。
    為此碼表補了「暫」「繼」「續」三個字（碼位往後追加，既有字的碼不動）。

## ScummVM／AGS（Deluxe 用，2 個檔）

12. **`ttf_font_renderer.cpp` 允許用 config 覆寫 TTF 名目尺寸** —— AGS 3.0 以前的遊戲資料裡字型槽沒有 size 欄位，替換進去的 TTF 一律以 8px 載入，中文無法閱讀。這個「名目尺寸」同時決定行距（`FontMetrics.NominalHeight`），所以**不能靠改字型檔繞過**：把字型的 `unitsPerEm` 改小確實會讓字形與推進寬一起放大（用 FreeType 量過），但行距仍停在 8px，上下兩行必疊。

    修補做兩件事，兩個鍵都是沒設就完全維持原行為：

    * `ags_ttf_font_size` —— 全域覆寫。Deluxe 用 24（畫面跑 640×400）。
    * `ags_ttf_font_size_<槽號>` —— 單一字型槽覆寫。同一個遊戲裡不同槽的可用空間不一樣：Deluxe 的句子列上方只有約 18px 的空檔，24px 的字下緣會被指令列按鈕的圖蓋掉，所以句子列那一槽（12）另外設 16。詳見 `40-deluxe.md`。

17. **`main_game_file.cpp` 讓 GUI 幾何可以用 config 覆寫** —— AGS 2.x 的 GUI 座標寫死在
    遊戲資料裡，換成中文之後不一定夠用：Deluxe 的句子列是 `gAction` 上一個只有 10 個
    遊戲像素高的 label，塞得下英文卻塞不下 24px 的中文。三個鍵都是沒設就維持原行為：
    `ags_gui_y_<gui>`、`ags_gui_ctrl_y_<gui>_<ctrl>`、`ags_gui_ctrl_h_<gui>_<ctrl>`。
    詳見 `40-deluxe.md`。

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
