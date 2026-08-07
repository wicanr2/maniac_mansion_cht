#!/bin/bash
# 打 Windows zip：full（內嵌遊戲，本機用）與 patch（只有引擎＋中文資料，可公開）。
set -eux
cd /w
EXE=tools/scummvm-win/scummvm.exe
MINGW=/usr/lib/gcc/x86_64-w64-mingw32/*-posix
SDLDLL=tools/sdl2-mingw/SDL2.dll   # 由 build-win.sh 的容器 docker cp 出來（SDL2 只裝在編譯容器裡）
OUT=dist-all
mkdir -p $OUT

pack() {   # $1 = full | patch
    local KIND=$1
    local D=/tmp/mmwin-$KIND
    rm -rf "$D"; mkdir -p "$D/cht"

    cp "$EXE" "$D/"
    cp "$SDLDLL" "$D/"
    # mingw 執行期 DLL：不附的話玩家端會跳「找不到 libgcc_s_seh-1.dll」。
    # [雷] 這一步要在 **mm-cht:mingw** 容器裡跑；在 dev 容器裡 find 一定落空，
    #      而原本寫成 `[ -n "$f" ] && cp` 會安靜略過 —— 打出來的包看起來正常，
    #      玩家開了才發現缺 DLL。所以找不到就直接失敗。
    for dll in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do
        f=$(find /usr/lib/gcc/x86_64-w64-mingw32 /usr/x86_64-w64-mingw32 -name "$dll" 2>/dev/null | head -1)
        [ -n "$f" ] || { echo "### 找不到 $dll —— 請在 mm-cht:mingw 容器裡打包"; exit 3; }
        cp "$f" "$D/"
    done

    cp game-cht/mansiond/chinese_gb16x12.fnt "$D/cht/"
    cp deluxe/game-cht/Chinese.tra deluxe/game-cht/acsetup.cfg "$D/cht/"
    cp deluxe/fonts/agsfnt-zh.ttf "$D/cht/agsfnt-zh.ttf"
    printf '[scummvm]\r\naspect_ratio=false\r\nfiltering=false\r\nags_ttf_font_size=24\r\nags_ttf_font_size_12=24\r\nags_gui_y_0=138\r\nags_gui_ctrl_h_0_0=14\r\n' > "$D/cht/scummvm.ini"

    # [雷] scummvm.exe 旁邊放 scummvm.ini = ScummVM 的 portable 模式
    #      （backends/platform/sdl/win32/win32.cpp: detectPortableConfigFile()）。
    #      沒有這個檔的話，玩家直接雙擊 scummvm.exe 會吃到預設值，其中
    #      **aspect_ratio 校正會把 240 列非整數拉成 288 列** —— 美術看起來還好，
    #      但 24x24 中文字的一像素筆劃會被抹成一團綠色雜訊（實測 wine 重現）。
    printf '[scummvm]\r\naspect_ratio=false\r\nfiltering=false\r\nags_ttf_font_size=24\r\nags_ttf_font_size_12=24\r\nags_gui_y_0=138\r\nags_gui_ctrl_h_0_0=14\r\n' > "$D/scummvm.ini"
    # 中文字型要佔滿 0–14 號槽（640×400 模式下遊戲改用 13/14 號槽）
    # 指令列九顆按鈕的中文圖：預先烘好的 18 張放在 cht_buttons.bin（我們自己的美術，
    # 不含遊戲資料），patch_buttons.py 只用標準函式庫把它們貼進玩家自己的 sprite 檔。
    cp maniac_mansion_cht/deluxe/tools/cht_buttons.bin \
       maniac_mansion_cht/deluxe/tools/ags_clib.py \
       maniac_mansion_cht/deluxe/tools/ags_spr.py \
       maniac_mansion_cht/deluxe/tools/patch_buttons.py "$D/cht/"
    printf '@echo off\r\nsetlocal\r\nif "%%~1"=="" (echo 用法： %%~nx0 ^<Maniac Mansion Deluxe 遊戲夾^> ^& pause ^& exit /b 1)\r\ncopy /y "%%~dp0Chinese.tra" "%%~1" >nul\r\ncopy /y "%%~dp0acsetup.cfg" "%%~1" >nul\r\nfor /l %%%%i in (0,1,14) do copy /y "%%~dp0agsfnt-zh.ttf" "%%~1\\agsfnt%%%%i.ttf" >nul\r\nrem 指令列按鈕要靠 Python 貼圖；沒有 Python 就維持英文，其餘中文不受影響\r\nwhere py >nul 2>&1 && (py "%%~dp0patch_buttons.py" "%%~1") || (where python >nul 2>&1 && (python "%%~dp0patch_buttons.py" "%%~1") || echo 找不到 Python，指令列按鈕維持英文。)\r\necho 裝好了。\r\npause\r\n' \
        > "$D/cht/安裝到-Deluxe.bat"

    if [ "$KIND" = full ]; then
        mkdir -p "$D/game" "$D/deluxe"
        cp game-cht/mansiond/*.LFL game-cht/mansiond/chinese_gb16x12.fnt "$D/game/"
        cp -r deluxe/game-cht/. "$D/deluxe/"
        printf '@echo off\r\nstart "" "%%~dp0scummvm.exe" -p "%%~dp0game" --auto-detect --extrapath="%%~dp0game" -e adlib --no-aspect-ratio --no-filtering\r\n' \
            > "$D/玩瘋狂大樓（中文版）.bat"
        printf '@echo off\r\nstart "" "%%~dp0scummvm.exe" -p "%%~dp0deluxe" --auto-detect --no-aspect-ratio --no-filtering\r\n' \
            > "$D/玩 Deluxe 重製版（中文版）.bat"
        # 萬一解壓縮把中文檔名弄壞，還有一組純 ASCII 的可以點
        cp "$D/玩瘋狂大樓（中文版）.bat"        "$D/play-maniac.bat"
        cp "$D/玩 Deluxe 重製版（中文版）.bat"  "$D/play-deluxe.bat"
    else
        printf '@echo off\r\nrem 自備遊戲夾：把 cht\\chinese_gb16x12.fnt 複製進去，再把下面的路徑改成你的遊戲夾\r\nstart "" "%%~dp0scummvm.exe" --extrapath="%%~dp0cht" -e adlib --no-aspect-ratio --no-filtering\r\n' \
            > "$D/啟動（自備遊戲）.bat"
        cp "$D/啟動（自備遊戲）.bat" "$D/play.bat"
    fi

    cat > "$D/README.txt" <<TXT
瘋狂大樓 繁體中文化（Windows $KIND 版）

scummvm.exe 是自編的 ScummVM，同時含 SCUMM 與 AGS 兩個引擎，並含本專案的修補：
  engines/scumm —— v2 的 CJK 路徑、16x15 倚天字型、640x400 hi-res 文字表面
  engines/ags   —— 可用 ags_ttf_font_size 覆寫 TTF 名目尺寸（Deluxe 用 24）

scummvm.ini 放在 scummvm.exe 旁邊，ScummVM 會以 portable 模式讀它。
裡面關掉了 aspect ratio 校正——開著的話畫面高度會被非整數拉伸，
24x24 的中文字會被抹成雜訊。**請不要刪掉這個檔。**

cht\\ 是中文資料：SCUMM v2 的字型、Deluxe 的譯文與字型。
自備 Deluxe 遊戲的話，把 cht\\安裝到-Deluxe.bat 拖到遊戲夾上（或帶遊戲夾路徑執行）即可。
TXT

    # [雷] Info-ZIP 的 zip 不會設 UTF-8 旗標（general purpose bit 11），
    #      中文檔名到了 Windows 檔案總管會用系統 ANSI（台灣是 CP950）解碼 → 檔名變亂碼，
    #      玩家找不到 .bat 就會直接雙擊 scummvm.exe，於是吃到預設的 aspect ratio 校正。
    #      Python 的 zipfile 對非 ASCII 檔名會自動設這個旗標，所以改用它打包。
    ( cd /tmp && rm -rf "maniac-mansion-cht-$KIND" && mv "mmwin-$KIND" "maniac-mansion-cht-$KIND" )
    rm -f "/w/$OUT/maniac-mansion-cht-$KIND-windows-x64.zip"
    python3 - "$KIND" "/w/$OUT/maniac-mansion-cht-$KIND-windows-x64.zip" <<'PY'
import os, sys, zipfile
kind, out = sys.argv[1], sys.argv[2]
root = "/tmp/maniac-mansion-cht-%s" % kind
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for dirpath, _, files in os.walk(root):
        for f in sorted(files):
            if f == ".DS_Store":
                continue
            full = os.path.join(dirpath, f)
            z.write(full, os.path.relpath(full, "/tmp"))
bad = [i.filename for i in zipfile.ZipFile(out).infolist()
       if any(ord(c) > 127 for c in i.filename) and not (i.flag_bits & 0x800)]
assert not bad, "這些檔名沒帶 UTF-8 旗標: %s" % bad
print("zip 內非 ASCII 檔名都帶了 UTF-8 旗標")
PY
}

pack full
pack patch
ls -lh $OUT/*.zip
echo WIN-PACK-OK
