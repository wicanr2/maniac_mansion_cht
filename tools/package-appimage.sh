#!/bin/bash
# 打 AppImage：full（內嵌遊戲，本機用）與 patch（只有引擎＋中文資料，可公開）兩種。
# 容器裡沒有 FUSE，所以 appimagetool 一律用 --appimage-extract-and-run 跑。
set -eux
cd /w
BIN=tools/scummvm-src/build-ags/scummvm
OUT=dist-all
mkdir -p $OUT tools/appimage

if [ ! -f tools/appimage/appimagetool ]; then
    curl -fsSL -o tools/appimage/appimagetool \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x tools/appimage/appimagetool
fi

build_appdir() {   # $1 = full | patch
    local KIND=$1
    local D=/tmp/MM-$KIND.AppDir
    rm -rf "$D"; mkdir -p "$D/usr/bin" "$D/usr/lib" "$D/usr/share/cht"

    cp "$BIN" "$D/usr/bin/scummvm"
    ldd "$BIN" | awk '/=> \//{print $3}' | sort -u | while read -r so; do
        case "$so" in /lib/x86_64-linux-gnu/libc.so.6|/lib64/ld-linux-x86-64.so.2) continue;; esac
        cp -L "$so" "$D/usr/lib/" 2>/dev/null || true
    done

    # 中文資料（字型與 Deluxe 翻譯檔）——兩種包都要，否則玩家看不到中文
    cp game-cht/mansiond/chinese_gb16x12.fnt "$D/usr/share/cht/"
    cp deluxe/game-cht/Chinese.tra deluxe/game-cht/acsetup.cfg "$D/usr/share/cht/"
    cp deluxe/fonts/agsfnt-zh.ttf "$D/usr/share/cht/agsfnt-zh.ttf"
    cat > "$D/usr/share/cht/安裝到-Deluxe.sh" <<'SH'
#!/bin/sh
# 用法：安裝到-Deluxe.sh <Maniac Mansion Deluxe 遊戲夾>
# 中文字型要佔滿 0–14 號字型槽：640×400 模式下遊戲改用 13/14 號槽，漏了就掉回內建點陣字。
set -eu
G=${1:?用法: $0 <遊戲夾>}
H=$(dirname "$(readlink -f "$0")")
cp "$H/Chinese.tra" "$H/acsetup.cfg" "$G/"
i=0; while [ $i -le 14 ]; do cp "$H/agsfnt-zh.ttf" "$G/agsfnt$i.ttf"; i=$((i+1)); done
echo "裝好了。啟動時記得帶 --config=$H/scummvm.ini"
SH
    chmod +x "$D/usr/share/cht/安裝到-Deluxe.sh"

    if [ "$KIND" = full ]; then
        mkdir -p "$D/usr/share/game" "$D/usr/share/deluxe"
        cp game-cht/mansiond/*.LFL game-cht/mansiond/chinese_gb16x12.fnt "$D/usr/share/game/"
        cp -r deluxe/game-cht/. "$D/usr/share/deluxe/"
    fi

    # 對白 24px；句子列（font_640 位置 1 → 12 號槽）16px，
    # 不然字的下緣會被指令列按鈕蓋掉
    printf '[scummvm]\nags_ttf_font_size=24\nags_ttf_font_size_12=16\n' > "$D/usr/share/cht/scummvm.ini"

    cat > "$D/AppRun" <<'SH'
#!/bin/sh
# 瘋狂大樓 繁體中文版。第一個參數可選：deluxe = 跑 Deluxe 重製版中文版。
HERE=$(dirname "$(readlink -f "$0")")
export LD_LIBRARY_PATH="$HERE/usr/lib:$LD_LIBRARY_PATH"
BIN="$HERE/usr/bin/scummvm"
CHT="$HERE/usr/share/cht"
case "${1:-}" in
  deluxe)
    shift
    if [ -d "$HERE/usr/share/deluxe" ]; then
      exec "$BIN" -p "$HERE/usr/share/deluxe" --auto-detect \
           --config="$CHT/scummvm.ini" --no-aspect-ratio "$@"
    fi
    echo "此為 patch 版，請自備 Maniac Mansion Deluxe 遊戲夾："
    echo "  1. sh \"$CHT/安裝到-Deluxe.sh\" <遊戲夾>"
    echo "  2. $0 deluxe --path=<遊戲夾>"
    exec "$BIN" --config="$CHT/scummvm.ini" --no-aspect-ratio "$@"
    ;;
  *)
    if [ -d "$HERE/usr/share/game" ]; then
      exec "$BIN" -p "$HERE/usr/share/game" --auto-detect \
           --extrapath="$HERE/usr/share/game" -e adlib --no-aspect-ratio "$@"
    fi
    echo "此為 patch 版，請自備已回填中文的 Maniac Mansion（v2）遊戲夾："
    echo "  中文字型在 $CHT/chinese_gb16x12.fnt，複製進遊戲夾即可"
    exec "$BIN" --extrapath="$CHT" -e adlib --no-aspect-ratio "$@"
    ;;
esac
SH
    chmod +x "$D/AppRun"

    cat > "$D/maniac-cht.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Maniac Mansion CHT
Comment=瘋狂大樓 繁體中文版（ScummVM）
Exec=AppRun
Icon=maniac-cht
Categories=Game;AdventureGame;
Terminal=false
DESK

    # 圖示：用遊戲標題畫面裁一塊（AppImage 規範要求有 icon）
    convert maniac_mansion_cht/screenshots/ingame-zh.png -resize 256x256^ \
            -gravity north -extent 256x256 "$D/maniac-cht.png"
    echo "$D"
}

for KIND in full patch; do
    D=$(build_appdir $KIND)
    ARCH=x86_64 ./tools/appimage/appimagetool --appimage-extract-and-run \
        "$D" "$OUT/maniac-mansion-cht-$KIND-x86_64.AppImage" >/dev/null 2>&1
    chmod +x "$OUT/maniac-mansion-cht-$KIND-x86_64.AppImage"
done
ls -lh $OUT/*.AppImage
echo APPIMAGE-OK
