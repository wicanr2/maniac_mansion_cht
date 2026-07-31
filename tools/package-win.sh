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
    # mingw 執行期 DLL：不附的話玩家端會跳「找不到 libgcc_s_seh-1.dll」
    for dll in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do
        f=$(find /usr/lib/gcc/x86_64-w64-mingw32 /usr/x86_64-w64-mingw32 -name "$dll" 2>/dev/null | head -1)
        [ -n "$f" ] && cp "$f" "$D/"
    done

    cp game-cht/mansiond/chinese_gb16x12.fnt "$D/cht/"
    cp deluxe/game-cht/Chinese.tra deluxe/game-cht/acsetup.cfg "$D/cht/"
    cp deluxe/game-cht/agsfnt0.ttf "$D/cht/agsfnt0.ttf"
    cp deluxe/game-cht/agsfnt1.ttf "$D/cht/agsfnt-speech.ttf"
    printf '[scummvm]\r\nags_ttf_font_size=16\r\n' > "$D/cht/scummvm.ini"

    if [ "$KIND" = full ]; then
        mkdir -p "$D/game" "$D/deluxe"
        cp game-cht/mansiond/*.LFL game-cht/mansiond/chinese_gb16x12.fnt "$D/game/"
        cp -r deluxe/game-cht/. "$D/deluxe/"
        printf '@echo off\r\nstart "" "%%~dp0scummvm.exe" -p "%%~dp0game" --auto-detect --extrapath="%%~dp0game" -e adlib --no-aspect-ratio\r\n' \
            > "$D/玩瘋狂大樓（中文版）.bat"
        printf '@echo off\r\nstart "" "%%~dp0scummvm.exe" -p "%%~dp0deluxe" --auto-detect --config="%%~dp0cht\\scummvm.ini" --no-aspect-ratio\r\n' \
            > "$D/玩 Deluxe 重製版（中文版）.bat"
    else
        printf '@echo off\r\nrem 自備遊戲夾：把 cht\\chinese_gb16x12.fnt 複製進去，再把下面的路徑改成你的遊戲夾\r\nstart "" "%%~dp0scummvm.exe" --extrapath="%%~dp0cht" -e adlib --no-aspect-ratio\r\n' \
            > "$D/啟動（自備遊戲）.bat"
    fi

    cat > "$D/README.txt" <<TXT
瘋狂大樓 繁體中文化（Windows $KIND 版）

scummvm.exe 是自編的 ScummVM，同時含 SCUMM 與 AGS 兩個引擎，並含本專案的修補：
  engines/scumm —— v2 的 CJK 路徑、16x15 倚天字型、640x400 hi-res 文字表面
  engines/ags   —— 可用 ags_ttf_font_size 覆寫 TTF 名目尺寸（Deluxe 用 16）

cht\\ 是中文資料：SCUMM v2 的字型、Deluxe 的譯文與字型。
TXT

    ( cd /tmp && zip -qr "/w/$OUT/maniac-mansion-cht-$KIND-windows-x64.zip" "mmwin-$KIND" -x '*.DS_Store' )
    # zip 內第一層改成有意義的名字
    ( cd /tmp && rm -rf "maniac-mansion-cht-$KIND" && mv "mmwin-$KIND" "maniac-mansion-cht-$KIND" \
      && rm -f "/w/$OUT/maniac-mansion-cht-$KIND-windows-x64.zip" \
      && zip -qr "/w/$OUT/maniac-mansion-cht-$KIND-windows-x64.zip" "maniac-mansion-cht-$KIND" )
}

pack full
pack patch
ls -lh $OUT/*.zip
echo WIN-PACK-OK
