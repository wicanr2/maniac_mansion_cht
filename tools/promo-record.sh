set -eu
cd /w
P=promo; rm -f $P/v2.mp4 $P/dlx.mp4
export DISPLAY=:99
clk() { xdotool mousemove "$1" "$2"; sleep 1; xdotool click 1; sleep 1; }
mean() { import -window root -crop "$1" +repage -format "%[fx:mean]" info: 2>/dev/null || echo 0; }
gt() { python3 -c "print(1 if float('${1:-0}')>${2} else 0)" 2>/dev/null || echo 0; }

Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
sleep 2
tools/scummvm-src/build-ags/scummvm -p /w/game-cht/mansiond --auto-detect \
    --extrapath=/w/game-cht/mansiond -e adlib --no-fullscreen --no-aspect-ratio > $P/v2.log 2>&1 &
sleep 12
clk 477 465; clk 557 465; clk 900 375
ok=0
for i in $(seq 1 60); do
    sleep 1
    A=$(mean "600x110+330+520")
    if [ "$(gt "$A" 0.005)" = "1" ]; then ok=1; break; fi
done
echo "v2 進遊戲=$ok i=$i"
sleep 3
ffmpeg -y -hide_banner -loglevel error -f x11grab -framerate 25 -video_size 640x480 -i :99+320,199 \
    -t 55 -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -threads 2 "$P/v2.mp4" &
REC=$!
sleep 2
for xy in "340 528" "460 528" "580 528" "580 556" "460 584" "340 584"; do
    set -- $xy; xdotool mousemove "$1" "$2"; sleep 1.5
done
xdotool mousemove 580 584; sleep 1; xdotool click 1; sleep 2
xdotool mousemove 700 430; sleep 4
xdotool mousemove 400 420; sleep 4
xdotool mousemove 850 400; sleep 3
xdotool mousemove 640 300; sleep 5
wait $REC
pkill -f build-ags/scummvm || true; sleep 3; pkill Xvfb || true; sleep 2

Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
sleep 2
printf '[scummvm]\nags_ttf_font_size=24\nags_ttf_font_size_12=16\n' > $P/dlx.ini
tools/scummvm-src/build-ags/scummvm -p /w/deluxe/game-cht --auto-detect \
    --config=/w/$P/dlx.ini --no-fullscreen --no-aspect-ratio > $P/dlx.log 2>&1 &
sleep 12
ffmpeg -y -hide_banner -loglevel error -f x11grab -framerate 25 -video_size 640x400 -i :99+380,282 \
    -t 75 -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -threads 2 "$P/dlx.mp4" &
REC2=$!
clk 700 400; sleep 2                # 離開導覽 → 標題
clk 536 490; clk 616 490; sleep 3    # 選角（顯示中文簡介）
clk 963 400; sleep 3                 # START
hits=0
for i in $(seq 1 40); do
    A=$(mean "600x140+390+540")
    if [ "$(gt "$A" 0.02)" = "1" ]; then hits=$((hits+1)); [ $hits -ge 2 ] && break; sleep 2
    else hits=0; xdotool key Escape; sleep 1; xdotool mousemove 700 400; xdotool click 1; sleep 2; fi
done
sleep 2
xdotool mousemove 425 460; sleep 3
xdotool key x; sleep 1; xdotool mousemove 860 440; sleep 1; xdotool click 1
sleep 12
xdotool mousemove 700 470; sleep 3
wait $REC2
pkill -f build-ags/scummvm || true; pkill Xvfb || true
ls -l $P/v2.mp4 $P/dlx.mp4
echo REC2-DONE
