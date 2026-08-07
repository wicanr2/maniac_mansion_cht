#!/bin/bash
# 同一個 pass/fail loop，但跑的是發行用的 Windows 包（wine）。
set -u
export HOME=/tmp WINEPREFIX=/tmp/wp DISPLAY=:99 WINEDEBUG=-all
OUT=/w/shots/verbclick-wine
mkdir -p $OUT && rm -f $OUT/*.png
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
sleep 2
wineboot -i >/dev/null 2>&1
sleep 5
rm -rf /tmp/wt && mkdir -p /tmp/wt && cd /tmp/wt
unzip -q /w/dist-all/maniac-mansion-cht-full-windows-x64.zip
cd maniac-mansion-cht-full
wine scummvm.exe -p game --auto-detect --extrapath=game -e adlib --no-aspect-ratio \
    > $OUT/run.log 2>&1 &
sleep 25
WID=$(xdotool search --name "Maniac Mansion" | tail -1)
eval $(xdotool getwindowgeometry --shell $WID)
echo "WID=$WID X=$X Y=$Y ${WIDTH}x${HEIGHT}"
snap() { import -window root -crop "640x28+${X}+$((Y+312))" +repage "$OUT/$1.png" 2>/dev/null; }
full() { import -window root -crop "${WIDTH}x${HEIGHT}+${X}+${Y}" +repage "$OUT/$1.png" 2>/dev/null; }
clk() { xdotool mousemove $((X+$1)) $((Y+$2)); sleep 0.6; xdotool click 1; sleep 0.9; }

clk 165 240; clk 315 240; clk 600 150
sleep 4
for n in $(seq 1 8); do xdotool key Escape; sleep 1.5; done
sleep 3
full "00-ingame"

XS="21 145 273 417 545"
i=0
for y in 353 381 409; do
  for x in $XS; do
    i=$((i+1))
    if [ "$i" = "3" ]; then clk 21 353; else clk 273 353; fi
    snap "c${i}_base"
    clk $x $y
    snap "c${i}_after"
  done
done
full "99-final"
pkill -f scummvm.exe
echo WINE-VERBCLICK-DONE
