set -u
cd /w
OUT=shots/scumm-agsbin
mkdir -p $OUT && rm -f $OUT/*.png
export DISPLAY=:99
Xvfb :99 -screen 0 640x480x16 >/dev/null 2>&1 &
sleep 2
tools/scummvm-src/build-ags/scummvm -p /w/game-cht/mansiond --auto-detect \
    --no-fullscreen -e adlib --no-aspect-ratio > $OUT/run.log 2>&1 &
SVM=$!
sleep 8
import -window root $OUT/01-title.png
xdotool mousemove 165 280; sleep 1; xdotool click 1; sleep 1
xdotool mousemove 315 280; sleep 1; xdotool click 1; sleep 1
import -window root $OUT/02-select.png
xdotool mousemove 600 190; sleep 1; xdotool click 1; sleep 3
for n in 1 2 3 4 5 6; do xdotool key Escape; sleep 2; done
sleep 3
import -window root $OUT/03-ingame.png
kill $SVM 2>/dev/null
grep -ciE "error" $OUT/run.log || true
echo SCUMM-ON-AGSBIN-DONE
