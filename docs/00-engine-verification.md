# 引擎與工具鏈驗證結論（SCUMM v2 / Maniac Mansion Enhanced DOS）

驗證日期 2026-07-30。所有結論以 ScummVM 源碼、scummtr 源碼、descumm 反組譯與實際 byte 比對為依據，不引用其他 SCUMM 版本的經驗推論。

## 版本與 gameid

| 項目 | 值 | 來源 |
|---|---|---|
| 遊戲資料 | `mansiond/00.LFL … 53.LFL` + `MANIAC.EXE`（54 個 LFL） | 解壓 Enhanced (1988).zip |
| 索引檔 magic | `0x0100` = Enhanced V2 | `ScummEngine_v2::readIndexFile()` |
| ScummVM gameid | `maniac`，SCUMM v2，platform DOS | 偵測表 |
| scummtr gameid | **`maniacv2`**（不是 `maniac`）；C64 原版為 `maniacv1` | `scummtr -L` |
| Maniac Mansion NES | scummtr 源碼中被註解掉，不支援 | `src/ScummRp/scummrp.cpp:640` |

## U1：ZH_CHN 路徑對 v2 是關閉的

`ScummEngine::loadCJKFont()`（`engines/scumm/charset.cpp`）進入中文分支的條件是：

```cpp
} else if (_language == Common::KO_KOR ||
           (_game.version >= 7 && (_language == Common::JA_JPN || _language == Common::ZH_TWN)) ||
           (_game.version >= 3 && _language == Common::ZH_CHN)) {
```

本作是 v2，**連 `version >= 3` 這道 gate 都過不了**，根本走不到裡層的 GID 白名單。Zak 是 v3，所以當年只需要把 `GID_ZAK` 加進白名單；本作要動的是兩層：

1. 外層版本 gate 放行 v2。
2. 內層 `case Common::ZH_CHN:` 的 GID 白名單加入 `GID_MANIAC`（目前只有 FT / LOOM / INDY3 / INDY4 / MONKEY / MONKEY2 / TENTACLE）。

字型自動偵測那一側**沒有版本限制**，`detectLanguage()` 只要在遊戲夾看到 `chinese_gb16x12.fnt` 就回 `ZH_CHN`（`engines/scumm/detection_internal.h:220`），所以中文開關對 v2 一樣有效。

## U2：v2 的 CJK 渲染路徑與尺寸

- `setupCharsetRenderer()`：`_game.version <= 2` 且非 NES → **`CharsetRendererV2`**，它繼承 `CharsetRendererV3`。
- 雙位元組字的取字與繪製路徑在 `CharsetRendererV3::printChar()` 已存在且不分版本：
  `charPtr = (_useCJKMode && chr > 127) ? get2byteCharPtr(chr) : _fontPtr + chr * 8;`
- ZH_CHN 的字型規格：`_2byteWidth = _2byteHeight = 12`、`_newLineCharacter = 0x21`，索引公式 `idx = (lead-0xA1)*94 + (trail-0xA1)`（GB2312 EUC）。
- `is2ByteCharacter(ZH_CHN, c)` 的判定是 **`c >= 0x80`**，也就是任何高位 byte 都會被當成雙位元組首碼。這是「譯文不可混入單一 latin-1 高位字元」的引擎層根據。

尺寸相關的硬編碼有兩處會把 12×12 中文截成噪點，且**其中一處是 v2 專屬、Zak(v3) 沒踩到的**：

| 位置 | 現況 | 影響 |
|---|---|---|
| `CharsetRendererV3::getDrawHeightIntern()` | 固定 `return 8` | 中文字高被截成 8 列 |
| `CharsetRendererV3::getDrawWidthIntern()` | 轉呼叫 `getCharWidth()` | 見下 |
| **`CharsetRendererV2::getCharWidth()`** | 固定 `return 8`（覆寫了 V3） | 中文字寬算成 8，字距全錯 |

## U3：scummtr 對 v2 的可逆性（原本不通，已解）

### 原始狀況

scummtr 0.6.0 直接拒絕寫入 v2：

```
ERROR: Modifying Maniac Mansion V2 is known to corrupt it
```

出處 `src/ScummTr/scummtr.cpp:399`，來自 upstream commit `07b5141`（2022-02-26，issue #16）。作者的說明是：用 ScummTR 改過 MM V2 後，遊戲在 ScummVM 裡**永遠跑 Demo 模式**；EN 與 FR 版都能重現，判定為 ScummRP/ScummTR 自身的 bug，於是整條 import 路徑封閉。

拆掉該保護後做「英文原封回填」，**40 個 LFL 被改動**，證明保護是實的。損壞分兩類，根因各自獨立：

### 根因一：`OldRoom::_cleanup()` 清掉共用的物件圖位移

v2 room header 佈局（依 `engines/scumm/room.cpp` 的 v2 分支）：

| 位移 | 欄位 |
|---|---|
| `0x00` | room size (uint16) |
| `0x0A` | IM00 位移 |
| `0x14` | numObjects (byte) |
| `0x16` / `0x17` | numSounds / numScripts (byte) |
| `0x18` / `0x1A` | EXCD / ENCD 位移 |
| `0x1C` 起 | numObjects × uint16 **物件圖位移(OI)**，緊接 numObjects × uint16 **物件腳本位移(OC)** |

`_findMostLikelyOIId()` 對「多個物件共用同一份影像」或「整室物件都沒有自己的影像、OI 一律指向影像區結尾」無法判定歸屬，標成 `_oiId[i] == -1`；`_cleanup()` 便把這些位移寫成 0。程式碼註解自己就寫明前提未達成：

```cpp
// Erase bad OI offsets
// _findMostLikelyOIId has to be perfect before using this
```

這是不可逆的：`_subblockUpdated()` 尾端**本來就會**把 OI/OC 全表跟著 `sizeDiff` 重定位

```cpp
for (int i = 0; i < (int)_oiSize.size() * 2; ++i)
    _updateOffset(_oObjTOC() + 2 * i, minOffset, sizeDiff, subblock._tag);
```

所以只要不清零，位移仍然正確。經比對，**39 個受損檔的差異 100% 落在 OI 表、新值全為 0、原值全等於表中其他合法位移**（零長度／共用影像的特徵），而原始檔中不存在任何 `OI == 0`，判定條件毫無歧義。

這道保護原本擋的是「使用者匯入改過的物件影像」時歸屬判斷錯誤；純文字回填從不動 OI 區塊，因此保留原值嚴格優於清零。

### 根因二：`_eraseOffsetsInRange()` 抹掉原版自帶的死索引

`LFLFile` 與 `OldLFLFile` 建構時會抹掉「位移超過該 LFL 檔尾」的索引項（`el.offset = -1; el.roomId = -1`，寫回索引就是 `0xFFFF` / `0xFF`）。00.LFL 的 6 個 byte 差異正是這樣來的——每筆資源是 roomId(1B) + offset(2B)，剛好 2 筆：

| 資源 | roomId | offset | 該檔大小 | 判定 |
|---|---|---|---|---|
| sound #1 | 33 | 0x3E77 = 15991 | 33.LFL = 11699 | 超出檔尾 |
| sound #49 | 41 | 0x160F = 5647 | 41.LFL = 5564 | 超出檔尾 |

也就是**原版遊戲資料本身就帶著兩筆指向檔尾外的死音效索引**（永遠不會被載入），scummtr 順手清掉。00.LFL 無法靠「還原原始檔」解決，因為它存的是所有資源的位移，室內文字變長時必須跟著更新。

### 修補與驗收

`patches/scummtr-maniacv2-lossless.patch`（24 行新增），兩處都以巨集開關包住，預設行為不變：

- `SCUMMTR_PRESERVE_AMBIGUOUS_OI` — `_cleanup()` 不清零。
- `SCUMMTR_KEEP_DANGLING_INDEX_ENTRIES` — 建構時不抹死索引。

建置：

```bash
cmake .. -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS="-DSCUMMTR_PRESERVE_AMBIGUOUS_OI -DSCUMMTR_KEEP_DANGLING_INDEX_ENTRIES -DSCUMMRP_OK_TO_CORRUPT_MANIACV2"
```

驗收（抽字 → 原封回填 → 逐檔 byte 比對）：**54 個 LFL 全部 byte-perfect**。

### 旗標選擇

| 旗標 | 結果 |
|---|---|
| `-r -w` | ✅ 54 檔 byte-perfect |
| `-c -l en -w` | ✅ 54 檔 byte-perfect（純 ASCII 下與 `-r` 等價） |
| `-r -w -A aov` | ❌ 5 個檔膨脹（07/20/23/45/53.LFL），**另一個獨立 bug** |

`-A aov` 的作用是「保護 actor/object/verb 名不被改長度」。中文化 verb 需要改長度，本來就不能用它，所以這個 bug 不擋路。**定案指令：`-r -w`**（CJK 必須 `-r` 保留原編碼；`-c` 會轉碼破壞中文）。

抽字結果：1139 行，涵蓋 `SCv2`(499) / `ONv2`(379) / `OCv2`(261) 三類區塊。

## U4：verb bar

15 個指令，畫面下方 5 欄 × 3 列（由手冊截圖與遊戲畫面確認）：

```
Push   Open    Walk to   Unlock    Turn on
Pull   Close   Pick up   New kid   Turn off
Give   Read    What is   Use       Fix
```

12px 中文放進 8px 列距需同步改 `drawVerb()` 與 `findVerbAtPos()`（只改前者會造成看到的 verb 與實際點到的 verb 錯列）。

## U5：防拷

原版防拷是二樓「安全門」的密碼鍵盤，需查說明書附的密碼查詢表（7 個 SECTION × 37 列 × A–I 欄的圖形符號）。軟體世界中文說明書第十一章「使用密碼」有完整說明，密碼表掃描件也在手冊裡。

ScummVM 的處理：`copy_protection` 這個 ExtraGuiOption **預設 false，也就是預設繞過**，不需額外處理。

另有一件要注意的事（`engines/scumm/resource.cpp:1901`）：GOG 與 Steam 販售的 MM v2 是**破解版**，其 keypad script（script 44，199 bytes）被改壞導致遊戲中所有鍵盤謎題失效；ScummVM 以 md5 `11adc9b47497b26ac2b9627e0982b3fe` 偵測並修回。我們手上這份要在實機跑起來後確認有無出現 `Removing bad copy protection crack from keypad script` 警告。

## 已知缺口（待處理，非放棄）

07.LFL 的 script #59（索引位置 `0x234D`–`0x2456`）在 `stopScript(0)` 之後接了一段不可及的字串常數：

```
0x2440: 62 00 | 49 74 27 73 20 61 6c 72 65 61 64 79 20 66 75 6c 6c 2e 00
        stopScript(0) | "It's already full." NUL
```

scummtr 與 descumm **在完全相同的位置失步**（`ERROR: do_room_ops_old: unknown subop 12!`），所以這是原版資料的遺留物、不是工具 bug；upstream commit `4e89048` 標記的「original script bug」指的就是這裡。後果是這一句台詞抽不出來，會留在英文。

處理方式：等實機驗證確認該字串是否真的會顯示；若會，用同長度就地覆寫（英文 18 bytes，中文「裡面已經滿了。」為 14 bytes，塞得進去）。

全面涵蓋率掃描結果：除此一句外，77 個 EX/EN 區段**零漏字**，其餘偵測到的未涵蓋字串都是二進位雜訊。

## 後續驗證結果（2026-07-30 當日完成）

- **中文渲染已實機驗證**：指令列 15 個全中文兩列排版、句子列、物件名、對白、片頭與選角資料都正確顯示，無撞碼、無截字。啟動 log 出現 `Loading CJK Font`，偵測結果標示 `Chinese (Simplified)`。
- **U2 補充**：除了 `getDrawHeightIntern` 之外，v2 還有兩個高度／寬度相關的點是 v3 不會遇到的
  —— `CharsetRendererV2::getCharWidth()` 固定回 8（覆寫了 V3），以及 `getFontHeight()` 在 CJK 模式一律回 13
  會把「沒有中文的原版字幕」第二行擠出 16px 文字區。詳見 `20-patches.md` 第 5、6 項。
- **新發現的第三道牆**：v2 腳本字串的空白壓縮會佔用高位元，且**控制碼也會被壓縮**
  （`0x01–0x03 | 0x80` = `0x81–0x83`），碼空間首碼因此收窄到 `0x88–0x9F`。詳見 `20-patches.md`。

## 尚未驗證

- 完整通關流程（目前驗到開場過場、選角、大門外場景；謎題流程未逐一走過）。
- MT-32／AdLib 音源支援情形。
- Deluxe（AGS fan remake）的安裝器解包與 AGS 版本。
- 07.LFL 那句孤立字串 `"It's already full."` 在遊戲中是否真的會顯示。
