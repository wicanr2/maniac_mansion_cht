#!/bin/bash
# 把 CI 產出的 engine-only .app 注入中文資料（與遊戲，full 版）打成可交付的 tar.gz。
#
# 為什麼要這一步：.app 只能在 macOS host build，而 CI 拿不到遊戲資料，也不該拿到
# 倚天字型衍生物與含英文原文的 .tra。所以 CI 只出引擎，中文資料在本機注入。
#
# [雷] 改動已簽名的 .app 之後簽章就失效了。這裡直接把 _CodeSignature 移除
#      （「未簽」勝過「壞簽」），並附一個修復指令讓使用者在 Mac 上重簽。
set -eux
cd /w
SRC=${1:?用法: package-macos.sh <CI 下載的 tar.gz>}
OUT=dist-all
mkdir -p $OUT

pack() {   # $1 = full | patch
    local KIND=$1
    local D=/tmp/mmmac-$KIND
    rm -rf "$D"; mkdir -p "$D"
    tar xzf "$SRC" -C "$D"
    local APP="$D/ScummVM.app"
    test -d "$APP"

    mkdir -p "$APP/Contents/Resources/cht"
    cp game-cht/mansiond/chinese_gb16x12.fnt "$APP/Contents/Resources/cht/"
    cp deluxe/game-cht/Chinese.tra deluxe/game-cht/acsetup.cfg "$APP/Contents/Resources/cht/"
    cp deluxe/fonts/agsfnt-zh.ttf "$APP/Contents/Resources/cht/agsfnt-zh.ttf"
    printf '[scummvm]\nags_ttf_font_size=24\n' > "$APP/Contents/Resources/cht/scummvm.ini"
    cat > "$APP/Contents/Resources/cht/安裝到-Deluxe.sh" <<'SH'
#!/bin/sh
# 用法：安裝到-Deluxe.sh <Maniac Mansion Deluxe 遊戲夾>
# 中文字型要佔滿 0–14 號字型槽：640×400 模式下遊戲改用 13/14 號槽。
set -eu
G=${1:?用法: $0 <遊戲夾>}
H=$(cd "$(dirname "$0")" && pwd)
cp "$H/Chinese.tra" "$H/acsetup.cfg" "$G/"
i=0; while [ $i -le 14 ]; do cp "$H/agsfnt-zh.ttf" "$G/agsfnt$i.ttf"; i=$((i+1)); done
echo "裝好了。啟動時記得帶 --config=$H/scummvm.ini"
SH
    chmod +x "$APP/Contents/Resources/cht/安裝到-Deluxe.sh"

    if [ "$KIND" = full ]; then
        mkdir -p "$APP/Contents/Resources/game" "$APP/Contents/Resources/deluxe"
        cp game-cht/mansiond/*.LFL game-cht/mansiond/chinese_gb16x12.fnt "$APP/Contents/Resources/game/"
        cp -r deluxe/game-cht/. "$APP/Contents/Resources/deluxe/"

        # 啟動包裝：CFBundleExecutable 仍叫 scummvm，實際 binary 改名 scummvm.bin，
        # 由 shell wrapper 帶好參數直接進遊戲，玩家不必自己輸路徑。
        mv "$APP/Contents/MacOS/scummvm" "$APP/Contents/MacOS/scummvm.bin"
        cat > "$APP/Contents/MacOS/scummvm" <<'SH'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
RES="$DIR/../Resources"
exec "$DIR/scummvm.bin" -p "$RES/game" --auto-detect \
     --extrapath="$RES/game" -e adlib --no-aspect-ratio "$@"
SH
        chmod +x "$APP/Contents/MacOS/scummvm"

        # Deluxe 另給一支啟動器（.app 只能有一個進入點）
        cat > "$D/玩 Deluxe 重製版（中文版）.command" <<'SH'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/ScummVM.app"
exec "$APP/Contents/MacOS/scummvm.bin" -p "$APP/Contents/Resources/deluxe" \
     --auto-detect --config="$APP/Contents/Resources/cht/scummvm.ini" --no-aspect-ratio
SH
        chmod +x "$D/玩 Deluxe 重製版（中文版）.command"
    fi

    rm -rf "$APP/Contents/_CodeSignature"
    cat > "$D/修復-macOS.command" <<'SH'
#!/bin/bash
# macOS 會擋未簽名的 app。在這裡跑一次就能開。
cd "$(dirname "$0")"
xattr -cr ScummVM.app
codesign --force --deep --sign - ScummVM.app
echo "好了，可以打開 ScummVM.app 了。"
SH
    chmod +x "$D/修復-macOS.command"

    tar czf "$OUT/maniac-mansion-cht-$KIND-macos-universal.tar.gz" -C "$D" .
}

pack full
pack patch
ls -lh $OUT/*macos*.tar.gz
echo MAC-PACK-OK
