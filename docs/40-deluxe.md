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

不是 Inno Setup、NSIS、7z-SFX、CAB 或 RAR-SFX——全檔搜不到任何一種的 magic。overlay 是**多段 zlib 流**（能找到多個 `78 9c` / `78 da` / `78 01` 檔頭），中間夾私有的目錄結構，所以 `7z`、`innoextract`、`cabextract` 都吃不下。

**後來查到它是什麼了：Clickteam Install Creator。** ScummVM 自己就有解包器（`common/compression/clickteam.cpp`），而且 AGS 的偵測表裡直接列了「從安裝檔內讀遊戲」的項目：

```
GAME_ENTRY("maniacmansiondeluxe", "clk:manicmdsetup.exe:Maniac.exe", ...)   // v1.05
GAME_ENTRY("maniacmansiondeluxe", "clk:Maniac-Mansion-Deluxe_Win_EN-FR-ES-DE-IT.exe:Maniac.exe", ...)  // v1.4
```

也就是說連裝都不必裝也能跑。不過中文化要往遊戲目錄丟 `.tra` 與字型檔，還是裝出鬆散檔比較好處理。

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

## 改用 v1.4 多語版

手上兩個安裝器裝出來的是不同版本：

| 安裝器 | `Maniac.exe` | ScummVM 偵測 | 翻譯檔 |
|---|---|---|---|
| `manicmdsetup.exe` | 9 395 050 | v1.05 Multi | 德／法／西 3 份 |
| `Maniac-Mansion-Deluxe_Win_EN-FR-ES-DE-IT.exe` | 10 409 172 | v1.4 | **14 份**（含俄文、保加利亞文） |

定案用 **v1.4**：字串多（原文聯集 1219 行 vs 1131）、翻譯樣本多，而且**俄文與保加利亞文的存在證明這款遊戲的字型本來就吃非拉丁字集**。

順帶一提，俄文版的 `TextOpts` 是 `(-1, -1, -1)`，也就是**沒有**切換字型槽——它靠的是遊戲內建字型在 0x80–0xFF 已經畫好西里爾字母。這條路對中文不適用（1000 多個漢字塞不進 256 個碼位），所以中文得走下一節的 UTF-8 + TTF。

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

## 中文顯示：翻譯與字型替換都不必改引擎，只有字型尺寸要

讀 ScummVM 的 AGS 引擎原始碼後，有兩件事對中文化很關鍵：

1. **翻譯檔可以自己宣告編碼。** `init_translation()` 讀 `StrOptions["encoding"]`，值是 `utf-8` 就 `set_uformat(U_UTF8)`——**這個判斷與遊戲本身的版本無關**，所以 2004 年的 AGS 2.x 遊戲也能靠這個 hint 走 UTF-8 文字路徑。字典的鍵維持原文的單位元組編碼，引擎有對應的 mixed-encoding 處理。`tra_codec.py --utf8` 就是在寫這個區塊（新式字串 ID 區塊 `ext_sopts`）。
2. **TTF 可以用鬆散檔覆蓋內建點陣字。** `fonts.cpp` 載入字型時**先試 `agsfnt%d.ttf`**，失敗才回頭找 `agsfnt%d.wfn`（`ttf_font_renderer.cpp:121`、`wfn_font_renderer.cpp:124`）。所以把一份中文 TTF 放在遊戲目錄下命名成對應的槽位，就能取代原本的英文點陣字。

**已實機驗證成立。** 45 行小樣試譯 + 一份 CJK 字型丟進遊戲目錄，ScummVM 的 AGS 引擎直接把繁體中文畫出來：

```
Translation initialized: Chinese (format: utf-8)
```

畫面上「我確定看到佛瑞德博士把珊蒂帶進來。」「現在只能靠我們把她救出來。」逐字正確，沒有亂碼。**編碼與字型替換這兩件事完全不必動引擎**——與 SCUMM v2 那邊要 4 個檔 134 行相比是另一個世界。（唯一需要修補的是字型尺寸，13 行，見下。）

實作細節：

* **翻譯的選取**：在遊戲目錄放一個 `acsetup.cfg`，內容 `[language]` / `translation=Chinese`（對應 `Chinese.tra`）。ScummVM 的 `config.cpp` 讀的就是這個鍵；命令列 `--language=` 那條路要求 `.tra` 檔名包含語言描述，繞比較多。
* **字型**：把 CJK 字型檔複製成 `agsfnt0.ttf` … `agsfnt14.ttf` 放遊戲目錄即可覆蓋內建點陣字（要鋪到 14 的原因見下節）。`.ttc` 也能直接吃（FreeType 會取第一個 face）。
* **一個無害的警告**：`UTF-8 translation in the ASCII/ANSI game, but no encoding hint for TRA keys conversion`。字典的鍵（英文原文）若含重音字元才需要這個 hint，本作的鍵是純 ASCII，所以不影響；之後補一個 `gameencoding` 提示可以清掉。

### 字太小：純資料改不動，最後加了 13 行引擎修補

AGS 的字型槽在 2.x 遊戲裡沒有 size 欄位，`ttf_font_renderer.cpp` 因此走 `if (fontSize <= 0) fontSize = 8;` 這條相容性分支，中文就以 8px em 渲染，細得像雜訊。

先試了純資料的作法：用 fontTools 把 `unitsPerEm` 改小（字形座標不動），同樣的 8px em 就會畫出比例上更大的字。**字形確實變大了，但版面壞掉**——字互相疊、上下兩行也疊。

拆下去看原因（實測過，不是猜的）：

* 字型這邊完全正常。用 FreeType 直接量，`upem 1024 → 512` 之後在 8px ppem 下，「我」的 advance 從 8px 變 16px、字模從 8×9 變 16×17，**推進寬與字形是一起放大的**。
* 壞的是**行距**。`alfont_set_font_size_ex()` 被 AGS 以 `ALFONT_FLG_SELECT_NOMINAL_SZ` 呼叫（「always choose the first result」），所以 `face_h` 就是要求的那個數字 8；而行距與 `FontMetrics.NominalHeight` 都取自這個**名目高度**，不是實際字形高度。字形放大兩倍、行距還是 8px → 上下兩行必疊。

也就是說「名目尺寸」這個數字同時決定了渲染尺寸與行距，**只有引擎那邊能改**。所以加了一段 13 行的修補：`ags_ttf_font_size` 這個 config 鍵有設就覆寫，沒設就完全維持原行為（`patches/scummvm-ags-cjk-fontsize.patch`）。

實測 12 / 16 / 20 三種尺寸，**16 最合**：兩行不重疊、字距正常，與遊戲原本約 10px 的英文並置也不突兀。設定方式是遊戲的 ScummVM 設定加一行 `ags_ttf_font_size=16`。

字型本身就用**沒有動過 upem 的原字型**，再用 `make_ags_font.py --subset-from` 依譯文精簡（全量 1238 字 → 371 KB，而不是整份 14 MB）。

### 但 320×200 下 16px 的中文還是糊——改跑 640×400

16px 中文在 320×200 的畫面上要再被顯示層放大一次，筆畫等於一格一格地被複製，橫豎粗細不均。而且 16px 對**選單**又太大：`F5` 的存檔／載入／開始／離開四個按鈕框是固定尺寸的圖，16px 中文會撐出框外。當時是把 `agsfnt0`（GUI 與句子列）用 `--scale 0.7` 縮字形擋過去，但那只是把「糊」換成「小」。

**真正的解法是讓遊戲本身跑在 640×400。** AGS 對 3.1 以前的遊戲留了一條 upscale 路徑（`engine/main/game_file.cpp:192`）：

```cpp
if (loaded_game_file_version < kGameVersion_310 && usetup.override_upscale) { ... }
```

`override_upscale` 讀的就是 `acsetup.cfg` 的 `[override] upscale`（`engine/main/config.cpp:411`），所以只要在遊戲夾的設定加兩行：

```ini
[override]
upscale=1
```

啟動訊息就從 `Game native resolution: 320 x 200` 變成 `640 x 400`——**純資料設定，不必再動引擎**。畫面配置與美術完全不變（AGS 內部把座標一起放大），差別只在文字可用的像素多了一倍。

在 640×400 下把字級開到 24（等於原本 320 畫面的 12px），中文的筆畫細節放得下，選單按鈕也還在框裡，`agsfnt0` 不必再縮 0.7 了。

### `font_320` / `font_640` 是字型槽編號表，不是位移

之前記成「改了沒作用」，實際上是**改對了但看不出來**：這兩行各有 21 個數字，對應 21 種文字情境（對白、GUI、句子列…）該用**哪一號字型槽**。俄文版把 `13 14 14…` 改成 `4 5 5…`，是因為它把西里爾字型放在別的槽。我們是**每個槽都放同一份中文字型**，所以改編號當然畫面不變。

證據不是推論：把 `font_640` 的值改成 32（超過字型槽數）後，遊戲直接噴 `SetSpeechFont: invalid font number`。

這件事對打包有實際影響——**320 模式用的是 {1, 0, 3} 號槽，640 模式改用 {13, 14} 號槽**。所以中文字型必須鋪滿 0–14 號槽，漏了就掉回內建點陣字（畫面上會變回英文點陣字或空白）。實際載入哪些槽有辦法確認：引擎修補裡帶了一行 `debug(1, "AGS: loading TTF font %d at size %d")`，用 `-d1` 跑一次就會逐一列出，實測是 0–14 共 15 個。

### 選字型：24px 下比的是筆畫會不會黏在一起

640×400、24px 這個尺寸下，字型好不好看幾乎只取決於**筆畫在小 ppem 下會不會糊成一團**，跟字型本身的設計感關係不大。實測比了三種：

| 字型 | 24px 實機結果 |
|---|---|
| **WQY Zen Hei**（採用） | 筆畫分得開，「選」「個」的內部結構還看得出來 |
| 華康超圓體 | 圓頭筆畫在小尺寸互相吃掉，整體糊成塊；20px 也一樣 |
| 華康少女文字 W7 | 手寫風，與這款 B 級恐怖片戲仿的調性不合 |

比對圖 `shots/pick-24.png` 是同一句「請再選兩個人。」在同一個尺寸下的實機截圖疊起來，不是憑印象選的。

順帶踩到一個字型缺字：譯文原本用 U+2027（`‧`）當人名間隔號，**WQY 沒有這個字**（華康有），FreeType 會安靜地畫成空白。改用三種字型都有的 U+00B7（`·`）。`make_ags_font.py --fail-on-missing` 會在烘字時查 cmap 擋下這種問題——同一個機制先前也擋下過 U+22EF。

## 待辦

1. 補 `gameencoding` hint，清掉 TRA keys 的警告。
2. 通關等級的長時間遊玩驗證（目前是多場景抽驗）。
3. 指令列的九個按鈕是 CLIB 內的手繪 sprite，翻譯機制碰不到，維持英文（見 `50-status.md`）。
4. 產出物放在本 repo 的 `deluxe/`；**遊戲資料與原廠 `.tra` 不入公開 repo**。
5. 待確認的版權問題：`.tra` 的鍵一定是英文原文，等於中文譯檔裡會夾帶完整英文台詞。要不要放上公開 repo，先問過再說。
