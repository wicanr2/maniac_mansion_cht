#!/bin/bash
# 把 CI 產出的 engine-only .app 注入中文資料（與遊戲，full 版）打成可交付的 tar.gz。
#
# 為什麼要這一步：.app 只能在 macOS host build，而 CI 拿不到遊戲資料，也不該拿到
# 倚天字型衍生物與含英文原文的 .tra。所以 CI 只出引擎，中文資料在本機注入。
#
# [雷] 改動已簽名的 .app 之後簽章就失效了。這裡直接把 _CodeSignature 移除
#      （「未簽」勝過「壞簽」），並附一個修復指令讓使用者在 Mac 上重簽。
#
# [雷·2026-08-06] full 與 patch 的 .app 內部結構原本不一樣：full 把真正的 binary
#      改名成 scummvm.bin、再放一支同名 shell wrapper 帶好參數；patch 則是 binary
#      直接叫 scummvm。結果拿 patch 版要更新 full 版的玩家會發現啟動器（呼叫
#      scummvm.bin）找不到檔案，於是把**舊版的 scummvm.bin 複製回來**——等於整包
#      更新完卻還是跑舊引擎，回報「修的都沒生效」（GitHub issue #2）。
#      現在兩種包一律都是 scummvm.bin + wrapper，覆蓋單一檔案就能換引擎。
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
    printf '[scummvm]\nags_ttf_font_size=24\nags_ttf_font_size_12=24\nags_gui_y_0=138\nags_gui_ctrl_h_0_0=14\n' > "$APP/Contents/Resources/cht/scummvm.ini"
    # 指令列九顆按鈕的中文圖：預先烘好的 18 張放在 cht_buttons.bin（我們自己的美術，
    # 不含遊戲資料），patch_buttons.py 只用標準函式庫把它們貼進玩家自己的 sprite 檔。
    cp maniac_mansion_cht/deluxe/tools/cht_buttons.bin \
       maniac_mansion_cht/deluxe/tools/ags_clib.py \
       maniac_mansion_cht/deluxe/tools/ags_spr.py \
       maniac_mansion_cht/deluxe/tools/patch_buttons.py "$APP/Contents/Resources/cht/"
    cat > "$APP/Contents/Resources/cht/安裝到-Deluxe.sh" <<'SH'
#!/bin/sh
# 用法：安裝到-Deluxe.sh <Maniac Mansion Deluxe 遊戲夾>
# 中文字型要佔滿 0–14 號字型槽：640×400 模式下遊戲改用 13/14 號槽。
set -eu
G=${1:?用法: $0 <遊戲夾>}
H=$(cd "$(dirname "$0")" && pwd)
cp "$H/Chinese.tra" "$H/acsetup.cfg" "$G/"
i=0; while [ $i -le 14 ]; do cp "$H/agsfnt-zh.ttf" "$G/agsfnt$i.ttf"; i=$((i+1)); done
# 指令列的九顆按鈕是遊戲資料裡的圖，換成中文要另外處理（純標準函式庫，不必 pip）
if command -v python3 >/dev/null 2>&1; then
    python3 "$H/patch_buttons.py" "$G" || echo "指令列按鈕沒裝成，其餘中文不受影響。"
else
    echo "找不到 python3 → 指令列按鈕維持英文，其餘中文正常。"
fi
echo "裝好了。啟動時記得帶 --config=$H/scummvm.ini"
SH
    chmod +x "$APP/Contents/Resources/cht/安裝到-Deluxe.sh"

    # 兩種包共用的結構：真 binary 叫 scummvm.bin，CFBundleExecutable（scummvm）是
    # 一支 wrapper。full 版的 wrapper 直接帶好遊戲路徑進 1988 原版；patch 版沒有
    # 遊戲資料，wrapper 就開 ScummVM 自己的遊戲清單。
    mv "$APP/Contents/MacOS/scummvm" "$APP/Contents/MacOS/scummvm.bin"

    if [ "$KIND" = full ]; then
        mkdir -p "$APP/Contents/Resources/game" "$APP/Contents/Resources/deluxe"
        cp game-cht/mansiond/*.LFL game-cht/mansiond/chinese_gb16x12.fnt "$APP/Contents/Resources/game/"
        cp -r deluxe/game-cht/. "$APP/Contents/Resources/deluxe/"

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
    else
        cat > "$APP/Contents/MacOS/scummvm" <<'SH'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/scummvm.bin" "$@"
SH
        chmod +x "$APP/Contents/MacOS/scummvm"

        # 給「已經有完整版、只想換新引擎與新中文資料」的人用：把舊版資料夾拖進來即可。
        cat > "$D/更新我的完整版.command" <<'SH'
#!/bin/bash
# 把舊的「完整版」資料夾更新成這一版：換引擎 + 換中文資料，遊戲檔原封不動。
cd "$(dirname "$0")"
NEW="$PWD"
echo "把舊的完整版資料夾拖進這個視窗，然後按 Enter："
echo "（就是裡面有 ScummVM.app 跟「玩 Deluxe 重製版（中文版）.command」的那個資料夾）"
read -r OLD
# 從 Finder 拖進來的路徑可能帶引號，或把空白寫成 "\ "
OLD=$(printf '%s' "$OLD" | sed "s/^'//; s/'\$//; s/\\\\ / /g; s/[[:space:]]*\$//")
OLDAPP="$OLD/ScummVM.app"
if [ ! -d "$OLDAPP/Contents/MacOS" ]; then
    echo "找不到 $OLDAPP，沒有動任何東西。"; read -r _; exit 1
fi

# 1. 引擎：新的真 binary 一律叫 scummvm.bin，同名的 scummvm 一律改寫成 wrapper
#    （舊版若把真 binary 放在 scummvm，留著它只會佔 58 MB 又永遠不會被執行）
cp "$NEW/ScummVM.app/Contents/MacOS/scummvm.bin" "$OLDAPP/Contents/MacOS/scummvm.bin"
if [ -d "$OLDAPP/Contents/Resources/game" ]; then
    cat > "$OLDAPP/Contents/MacOS/scummvm" <<'W'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
RES="$DIR/../Resources"
exec "$DIR/scummvm.bin" -p "$RES/game" --auto-detect \
     --extrapath="$RES/game" -e adlib --no-aspect-ratio "$@"
W
else
    cat > "$OLDAPP/Contents/MacOS/scummvm" <<'W'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/scummvm.bin" "$@"
W
fi
chmod +x "$OLDAPP/Contents/MacOS/scummvm"

CHT="$NEW/ScummVM.app/Contents/Resources/cht"
# 2. 1988 原版：字型（新版多了「暫繼續」三個字，暫停訊息才畫得出來）
[ -d "$OLDAPP/Contents/Resources/game" ] && cp "$CHT/chinese_gb16x12.fnt" "$OLDAPP/Contents/Resources/game/"
# 3. Deluxe：譯文與設定（指令列失效就是舊譯文造成的）
if [ -d "$OLDAPP/Contents/Resources/deluxe" ]; then
    sh "$CHT/安裝到-Deluxe.sh" "$OLDAPP/Contents/Resources/deluxe" >/dev/null
fi
# 4. 重簽：改過的 .app 舊簽章會失效。
#    Apple Silicon 上「沒有有效簽章」= 完全跑不起來，所以這一步失敗一定要講出來，
#    不能吞掉——不然玩家只會看到 app 點了沒反應。
xattr -cr "$OLDAPP" 2>/dev/null
rm -rf "$OLDAPP/Contents/_CodeSignature"
if codesign --force --deep --sign - "$OLDAPP"; then
    SIGNED=yes
else
    SIGNED=no
fi

echo
echo "更新完成：$OLD"
if [ "$SIGNED" = yes ]; then
    echo "直接開那邊的 ScummVM.app 或「玩 Deluxe 重製版（中文版）.command」就是新版了。"
else
    echo "但是重新簽章失敗了。請在終端機手動跑這一行再開："
    echo "  codesign --force --deep --sign - \"$OLDAPP\""
    echo "（Apple Silicon 上沒有簽章的 app 會直接跑不起來。）"
fi
read -r _
SH
        chmod +x "$D/更新我的完整版.command"
    fi

    if [ "$KIND" = patch ]; then
        cat > "$D/README.txt" <<'TXT'
瘋狂大樓 繁體中文化 — macOS（patch 版，不含遊戲資料）

先跑「修復-macOS.command」，再開 ScummVM.app。
（.app 的簽章在注入中文資料時就失效了，那支指令做的是 xattr -cr + 用你自己的機器重簽。）

■ 你手上已經有「完整版」（遊戲在 ScummVM.app 裡面）
  跑「更新我的完整版.command」，把舊資料夾拖進去就好：它會換掉引擎
  （ScummVM.app/Contents/MacOS/scummvm.bin）、Deluxe 的中文譯文與字型、
  1988 原版的中文字型，遊戲檔本身不動，最後幫你重簽一次。

  ※ 不要只複製 ScummVM.app —— 你的遊戲資料在舊的那一份裡面。
  ※ 也不要反過來把舊的 scummvm.bin 複製到新的 .app：那等於還在跑舊引擎。

■ 你自己有 Maniac Mansion Deluxe 的遊戲夾
  sh ScummVM.app/Contents/Resources/cht/安裝到-Deluxe.sh /你的/MMD
  啟動時帶上 --config=ScummVM.app/Contents/Resources/cht/scummvm.ini

■ 1988 原版（SCUMM v2）
  中文在 *.LFL 裡面，要照 repo 的 docs/30-pipeline.md 自己回填一次，
  字型用 ScummVM.app/Contents/Resources/cht/chinese_gb16x12.fnt。

https://github.com/wicanr2/maniac_mansion_cht
TXT
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
