#!/bin/bash
# pass/fail loop：原版 v2 的 15 個指令，逐格點擊看句子列有沒有跟著變。
# 每格先點「走到」（第一列第三欄）當基準，再點目標格；兩張句子列一樣 = 這格點不動。
# 視窗座標用 xdotool 量，不要假設 Xvfb 會把視窗放在 (0,0)。
set -u
cd /w
BIN=${BIN:-tools/scummvm-src/build-ags/scummvm}
OUT=${OUT:-shots/verbclick}
mkdir -p $OUT && rm -f $OUT/*.png
export DISPLAY=:99
Xvfb :99 -screen 0 800x600x16 >/dev/null 2>&1 &
sleep 2
$BIN -p /w/game-cht/mansiond --auto-detect --no-fullscreen -e adlib \
    --no-aspect-ratio > $OUT/log.txt 2>&1 &
sleep 8
WID=$(xdotool search --name "Maniac Mansion" | tail -1)
eval $(xdotool getwindowgeometry --shell $WID)
echo "WID=$WID X=$X Y=$Y ${WIDTH}x${HEIGHT}"
# 指令區 topline = 312（螢幕像素）；列高 28
snap() { import -window root -crop "640x28+${X}+$((Y+312))" +repage "$OUT/$1.png" 2>/dev/null; }
full() { import -window root -crop "${WIDTH}x${HEIGHT}+${X}+${Y}" +repage "$OUT/$1.png" 2>/dev/null; }
clk() { xdotool mousemove $((X+$1)) $((Y+$2)); sleep 0.6; xdotool click 1; sleep 0.9; }

clk 165 240; clk 315 240; clk 600 150      # 選角 → 開始
sleep 4
for n in $(seq 1 8); do xdotool key Escape; sleep 1.5; done
sleep 3
full "00-ingame"

XS="21 145 273 417 545"
i=0
for y in 353 381 409; do
  for x in $XS; do
    i=$((i+1))
    # 基準用「走到」；輪到走到自己那格時改用「推」，否則基準與目標同字，
    # 句子列本來就不會變，會被誤判成沒反應。
    if [ "$i" = "3" ]; then clk 21 353; else clk 273 353; fi
    snap "c${i}_base"
    clk $x $y
    snap "c${i}_after"
  done
done
full "99-final"
pkill -f "$BIN" 2>/dev/null
echo VERBCLICK-DONE
