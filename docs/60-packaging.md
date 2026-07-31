# 三平台打包

一支 binary 同時編進 **SCUMM 與 AGS** 兩個引擎：`play.sh` 跑 1988 年的 v2 中文版，`play-deluxe.sh`／`deluxe` 參數跑 2004 年的 Deluxe 中文版。

每個平台各出兩種包：

| | 內含遊戲 | 去處 | 啟動方式 |
|---|---|---|---|
| **full** | ✅ 整份中文化遊戲 | 只留本機 `dist-all/`（gitignore） | 啟動器直指內嵌遊戲，開了就能玩 |
| **patch** | ❌ 只有引擎＋中文資料 | 可公開發佈，玩家自備遊戲 | 需自己指路徑；中文資料在 `cht/` |

## patch 版的中文資料長什麼樣

`cht/` 裡放的是「引擎之外、玩家自己要塞進遊戲夾」的東西：

| 檔案 | 給誰 |
|---|---|
| `chinese_gb16x12.fnt` | SCUMM v2（倚天 16×15 點陣字） |
| `Chinese.tra`、`acsetup.cfg` | Deluxe（譯文＋選語言＋`upscale=1`） |
| `agsfnt-zh.ttf` | Deluxe 的中文字型（一份） |
| `安裝到-Deluxe.sh` / `.bat` | 把上面三個裝進遊戲夾 |
| `scummvm.ini` | 只有一行 `ags_ttf_font_size=24` |

字型只放**一份**、由安裝腳本複製成 `agsfnt0.ttf` … `agsfnt14.ttf`。要鋪到 14 是因為 640×400
模式下遊戲改用 13/14 號字型槽（見 `40-deluxe.md`）；直接塞 15 份進包裡會多 5 MB，
而 zip 對重複檔案沒有去重。

## 一個會靜靜壞掉的相依：AGS 需要 libmad

`engines/ags/configure.engine` 這一行是關鍵：

```
add_engine ags "Adventure Game Studio" yes "" "" "16bit mad" "theoradec midi universaltracker mpeg2"
```

`deps` 欄寫著 **`16bit mad`**。所以交叉編時若帶了 `--disable-mad`，configure **不會報任何錯**，只是把 AGS 關掉——`config.mk` 裡從

```
ENABLE_AGS = STATIC_PLUGIN
```

變成

```
# ENABLE_AGS
```

編出來的 binary 跑 v2 一切正常，跑 Deluxe 才會在啟動時跳 **`Could not find suitable engine plugin`**。這個坑只有實跑才抓得到，靜態檢查看不出來（`engines/ags/detection.o` 照樣會被編出來，因為偵測外掛與引擎本體是分開的）。

Windows 與 macOS 兩邊都改成**自源碼編 libmad 0.15.1b 靜態庫**。它 1998 年的 `configure` 會帶 `-fforce-mem`，現代編譯器早就移除這個旗標，要先 `sed` 掉。

建置後的守門檢查：

```bash
grep -E "^ENABLE_AGS" config.mk    # 必須是 ENABLE_AGS = STATIC_PLUGIN
```

## Linux — AppImage

`tools/package-appimage.sh`。容器裡沒有 FUSE，`appimagetool` 一律加 `--appimage-extract-and-run`。

AppRun 吃一個可選參數：不給就跑 v2 中文版，給 `deluxe` 就跑 Deluxe 中文版。

```bash
./maniac-mansion-cht-full-x86_64.AppImage            # 瘋狂大樓（v2）
./maniac-mansion-cht-full-x86_64.AppImage deluxe     # Deluxe 重製版
```

## Windows — mingw-w64 交叉編

`tools/build-win.sh` + `tools/package-win.sh`。三個踩過的雷：

1. **複製 source 樹時 exclude 要用錨定路徑** `./config.h`。寫成 `config.h` 會連 `audio/softsynth/mt32/config.h`（Munt 的版本標頭）一起排除，編 mt32emu 時噴 `MT32EMU_VERSION_MAJOR` 未宣告。
2. **不要把 `/usr/x86_64-w64-mingw32/bin` 放進 PATH**。那裡是 target binutils（`as`／`ld`），native g++ 會撿到 mingw 的 `as`，於是「native 編譯器產 ELF 組語 → COFF 組譯器讀它」，噴一整片 `junk at end of line`、`.type pseudo-op used outside of .def/.endef`。SDL 只要 `SDL_CONFIG` 指到 `sdl2-config` 就好。
3. **複製過來的樹要清掉舊 `config.mk`**，否則 `if [ ! -f config.mk ]` 這種守門會讓 configure 整個被跳過，直接沿用 Linux 那次的設定（CXX 還是 `g++`）。

執行期 DLL 要一起附：`SDL2.dll`、`libgcc_s_seh-1.dll`、`libstdc++-6.dll`、`libwinpthread-1.dll`。

驗證用 wine 實跑，不是只看檔案有沒有產出——Deluxe 少了 AGS 的那個問題就是這樣抓到的。

## macOS — GitHub Actions

`.github/workflows/build-mac.yml` + `tools/build-mac.sh`，跑 `macos-14`（Apple Silicon）runner。

`.app` 只能在 macOS host 做（codesign 是 macOS 限定），Linux 端做不出來也測不出 SDL 與 Gatekeeper 的雷。幾條沿用先前專案的結論：

* **不要 `brew install sdl2`** —— 2026 年起那是 sdl2-compat shim，runtime 才 `dlopen libSDL3`，打包抓不到 → 玩家端「Failed loading SDL3 library」。改自源碼編 pinned 真 SDL2 靜態庫。
* **universal 不能單次雙 `-arch`**（autoconf 版本解析會炸）→ 每個架構各編一次再 `lipo -create`。
* ScummVM 的 `configure` 不是 autoconf：`CXXFLAGS`／`LDFLAGS` 只能用**環境變數前綴**。

CI 產出的是 **engine-only** 的 `.app`：烘出來的倚天字型是商業字型衍生物、Deluxe 的 `.tra` 夾帶英文原文，兩者都不進公開 repo。中文資料與遊戲在本機用 `tools/package-macos.sh` 注入：

```bash
gh run download <run-id> --name maniac-cht-macos
bash tools/package-macos.sh maniac-cht-macos-app.tar.gz
```

**改動已簽名的 `.app` 之後簽章就失效**，所以注入完直接把 `_CodeSignature` 移掉（「未簽」勝過「壞簽」），並附一支 `修復-macOS.command`（`xattr -cr` + `codesign --force --deep --sign -`）。Linux 端無法代簽也無法實測，**這一包要請使用者在 Mac 上跑一次修復指令再開來確認**。
