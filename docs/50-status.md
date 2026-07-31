# 進度與待辦

最後更新：2026-07-31。

## 兩條產線

| | 瘋狂大樓（SCUMM v2, 1988） | Deluxe（AGS 重製版, 2004 v1.4） |
|---|---|---|
| 文字量 | 1139 行 | 1219 行 |
| 翻譯 | ✅ 完成（118 行刻意留原文，1 行抽不出來） | ✅ **1219 / 1219 完成** |
| 字型 | 倚天 16×15 原生點陣（`chinese_gb16x12.fnt`） | WQY Zen Hei TTF，依譯文精簡（1238 字 / 371 KB）；`agsfnt0`（GUI／句子列）縮 0.7 倍，其餘原尺寸 |
| 引擎修補 | 4 個檔 +134 行 | 1 個檔 +13 行（TTF 名目尺寸） |
| 實機驗證 | ✅ 多場景 | ✅ 多場景 |
| 本機發佈包 | ✅ `dist-all/`，與 Deluxe 共用同一支 binary | ✅ 同上 |
| 三平台包 | ✅ AppImage / Windows zip / macOS .app（full + patch 各一） | ✅ 同一批包裡 |

一支 `bin/scummvm` 同時編進 SCUMM 與 AGS 兩個引擎，兩邊的修補都在裡面；
`play.sh` 跑 v2 中文版，`play-deluxe.sh` 跑 Deluxe 中文版。

## Deluxe 驗證涵蓋（實機截圖為憑）

| 畫面／路徑 | 結果 |
|---|---|
| 片頭導覽（attract mode，多個房間） | ✅ 對白中文 |
| 標題／選角：提示與七位主角簡介 | ✅ 例如「溫蒂——想成為知名小說家，正在等一個大機會。」 |
| 開場三人對話 | ✅ 逐句中文 |
| 製作名單的分類標題 | ✅ 設計／美術／音樂／翻譯 |
| 句子列（指令 + 物件名） | ✅ 「走到 標示」「查看 標示」「走到 灌木叢」 |
| 動作回應對白 | ✅ 查看告示牌 →「警告！！」「……殘忍地大卸八塊。」 |
| 換場景後 | ✅ 物件名仍為中文 |
| 自動換行 | ✅ 長句正確折成兩行，不重疊 |
| 遊戲選單（F5） | ✅ 「有什麼可以為您效勞的？」＋存檔／載入／開始／離開，各自落在按鈕框內 |
| 從發佈包啟動 | ✅ `play-deluxe.sh` 直接進中文標題 |

## 已知限制

**指令列的九個按鈕是圖片，不是文字。** Deluxe 的 Give / PICKUP / USE / OPEN /
LOOKAT / PUSH / CLOSE / TALKTO / PULL 是手繪 sprite，存在 AGS 的 CLIB
（`Maniac.001`–`005`）裡，翻譯檔碰不到它。譯文裡的 `a_button_*` 只是
「索引 + 兩個 sprite 編號 + 熱鍵」的定義，改字串不會改圖。

要中文化得換掉 sprite，也就是解 CLIB → 改 `acsprset.spr` → 以鬆散檔覆蓋。
ScummVM 有 CLIB 讀取器可以參考，但要自己寫 sprite 檔的寫入端，是另一個
規模的子專案。目前**維持英文按鈕**，句子列（真正描述你要做什麼的那一行）
已是中文。

**物品欄的物品名未取得視覺確認。** 物品名走的是與句子列相同的 `drawString`
路徑（同一支字型、同一個編碼），而且物件名已經確認正確；但沒有實際拿到
物品做視覺確認。原因是自動化操作在門廊那段還沒解出可重複的拿取步驟。

**指令按鈕不吃合成滑鼠點擊。** 驗證時用 xdotool 點按鈕沒有反應，改用遊戲
自己的熱鍵（`a_button_*` 定義的 s/w/a/d/x…）就正常。這是自動化的限制，
不是遊戲的問題——真人用滑鼠玩不受影響。

## 三平台包（2026-07-31）

| 平台 | 包 | 驗證 |
|---|---|---|
| Linux | `maniac-mansion-cht-{full,patch}-x86_64.AppImage` | ✅ 容器內實跑：v2 進中文標題、Deluxe 出 `Translation initialized: Chinese` |
| Windows | `maniac-mansion-cht-{full,patch}-windows-x64.zip` | ✅ wine 實跑：v2 中文標題、Deluxe「請再選兩個人」 |
| macOS | `maniac-mansion-cht-{full,patch}-macos-universal.tar.gz` | ⚠️ CI 建置成功、雙弧與兩個引擎都在（`Engines (builtin): SCUMM / Adventure Game Studio`），但**沒有 Mac 可實跑**——請在 Mac 上先跑 `修復-macOS.command` 再開 |

三個雷都是**實跑才抓得到**的（靜態檢查看不出來），細節在 `60-packaging.md`：

1. AGS 的 `configure.engine` 寫著 deps `16bit mad`，帶 `--disable-mad` 會讓 configure **不報錯地**把 AGS 關掉，`config.mk` 從 `ENABLE_AGS = STATIC_PLUGIN` 變成 `# ENABLE_AGS`，跑 Deluxe 才出現 `Could not find suitable engine plugin`。
2. AGS 的 TTF 走的是 **ScummVM 的 FreeType**，不是它自帶的 `lib/freetype-2.1.3`；`--disable-freetype2` 會讓 Deluxe 一啟動就 `Game needs FreeType library`。
3. mingw：複製 source 樹時 `--exclude=config.h` 沒錨定路徑會連 Munt 的版本標頭一起排掉；`/usr/x86_64-w64-mingw32/bin` 進 PATH 會讓 native g++ 撿到 mingw 的 `as`。

## 待辦

1. 通關等級的長時間遊玩驗證（目前是多場景抽驗，不是全流程）。
2. 物品欄視覺確認。
3. 指令列 sprite 中文化（要寫 CLIB／sprite 寫入端，另案評估）。
4. 補 `.tra` 的 `gameencoding` hint，清掉啟動時那行 TRA keys 警告（無害）。
5. v1（C64 原版，SCUMM v1）尚未開始。

## 待你決定（授權相關，未定前不上傳）

* repo 裡的實機截圖。
* Deluxe 譯文的形態：`.tra` 的鍵**必然是英文原文**，所以中文譯檔等於夾帶
  完整英文台詞。要不要放上公開 repo 需要你決定；目前只留在本機。
