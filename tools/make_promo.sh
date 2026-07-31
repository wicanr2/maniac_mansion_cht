#!/usr/bin/env bash
set -eu
cd /w
# ===== 設計 token =====
BGD='#0a0a14'; EGA_BLUE='#2323c8'; EGA_YELLOW='#f8f04c'; EGA_RED='#b02020'; CREAM='#f2ead2'
FB=/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc
FR=/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc
test -f "$FB" && test -f "$FR"
W=1280; H=720; FPS=25
P=promo; T=$P/build; OUT=$P; mkdir -p "$T"
rm -f $T/*.mp4 $T/*.png

# ---- 卡片 ----
card() {  # $1 out  $2 主標  $3 英標  $4 副標
  convert -size ${W}x${H} "radial-gradient:#1b1b3a-${BGD}" -gravity center \
    -font "$FB" -fill "#5a4a10" -pointsize 96 -annotate +4+4 "$3" \
    -fill "$EGA_YELLOW" -pointsize 96 -annotate +0+0 "$3" \
    -fill "$CREAM"      -pointsize 62 -annotate +0+110 "$2" \
    -font "$FR" -fill "#9a9ab8" -pointsize 30 -annotate +0+200 "$4" "$1"
}
still() {  # $1 out  $2 遊戲截圖  $3 說明
  convert -size ${W}x${H} "xc:${BGD}" \
    \( "$2" -filter point -resize 1100x600 -background black \) -gravity center -geometry +0-30 -composite \
    -gravity south -font "$FR" -fill "$CREAM" -pointsize 34 -annotate +0+40 "$3" "$1"
}

card $T/c1.png "繁體中文化"       "瘋狂大樓"  "MANIAC MANSION ・ LucasArts 1987"
card $T/c2.png "2004 年的同人重製版也一起" "DELUXE" "Maniac Mansion Deluxe ・ Adventure Game Studio"
card $T/c3.png "patch-only ・ 不含遊戲資料" "取得"  "github.com/wicanr2/maniac_mansion_cht"

still $T/s1.png maniac_mansion_cht/screenshots/deluxe-title-zh.png    "Deluxe：640×400，對白 24px"
still $T/s2.png maniac_mansion_cht/screenshots/deluxe-dialog-zh.png   "1219 行譯文全部翻完"
still $T/s3.png maniac_mansion_cht/screenshots/deluxe-menu-zh.png     "選單與句子列都進了中文"
still $T/s4.png maniac_mansion_cht/screenshots/charselect-zh.png      "七個可選主角，簡介沿用軟體世界的中文說明書"

# ---- 靜態段（kb 的 CPU-safe 作法：不用 zoompan，靜圖 + fade）----
seg_still() {  # $1 png  $2 秒  $3 out
  local S=$2 FO
  FO=$(awk "BEGIN{printf \"%.2f\", $S-0.6}")
  ffmpeg -y -hide_banner -loglevel error -loop 1 -i "$1" -t "$S" -r $FPS \
    -vf "fade=t=in:st=0:d=0.6,fade=t=out:st=$FO:d=0.6,format=yuv420p" \
    -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$3"
}
# ---- 實機錄影段：nearest 放大到 1120 寬，置中，燒中文字幕 ----
seg_video() {  # $1 mp4  $2 ss  $3 秒  $4 字幕  $5 out
  local FO; FO=$(awk "BEGIN{printf \"%.2f\", $3-0.6}")
  ffmpeg -y -hide_banner -loglevel error -ss "$2" -i "$1" -t "$3" -r $FPS \
    -vf "scale=-2:620:flags=neighbor,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2-30:color=${BGD},\
drawtext=fontfile=${FR}:text='$4':fontcolor=${CREAM}:fontsize=34:x=(w-tw)/2:y=h-72:\
box=1:boxcolor=0x0a0a14aa:boxborderw=14,\
fade=t=in:st=0:d=0.5,fade=t=out:st=$FO:d=0.6,format=yuv420p" \
    -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$5"
}

seg_still $T/c1.png 4.0 $T/01.mp4
seg_video $P/v2.mp4  2  9.0 "1988 Enhanced DOS 版：15 個指令、物件名、對白全中文" $T/02.mp4
seg_video $P/v2.mp4 12  8.0 "指令列一列從 8 像素放寬到 14，24×24 的字才擺得下"      $T/03.mp4
seg_video $P/v2.mp4 28  8.0 "字型是倚天中文系統的原生點陣字，不是 TTF 縮小"          $T/04.mp4
seg_still $T/c2.png 4.0 $T/05.mp4
seg_still $T/s1.png 4.5 $T/06.mp4
seg_still $T/s2.png 4.5 $T/07.mp4
seg_still $T/s3.png 4.5 $T/08.mp4
seg_still $T/s4.png 4.5 $T/09.mp4
seg_still $T/c3.png 5.0 $T/10.mp4

for f in $T/[01]*.mp4; do echo "file '$(basename "$f")'" ; done > $T/list.txt
( cd $T && ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i list.txt -c copy silent.mp4 )

DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $T/silent.mp4)
echo "影片長度 ${DUR}s"
# ---- 配樂：Deluxe 遊戲內錄下來的真實音訊（rulebook/93：不自產）----
ffmpeg -y -hide_banner -loglevel error -stream_loop 3 -i $P/bgm.wav -t "$DUR" \
    -af "volume=1.6,afade=t=in:d=1.5,afade=t=out:st=$(awk "BEGIN{printf \"%.2f\", $DUR-3}"):d=3" \
    -ar 44100 -ac 2 $T/bgm-loop.wav
ffmpeg -y -hide_banner -loglevel error -i $T/silent.mp4 -i $T/bgm-loop.wav \
    -c:v copy -c:a aac -b:a 160k -shortest "$OUT/maniac-mansion-cht-promo.mp4"

# ---- README 用的靜音 GIF（公開只嵌 GIF，見 CLAUDE.md）----
ffmpeg -y -hide_banner -loglevel error -ss 4 -t 8 -i $P/v2.mp4 \
    -vf "scale=480:-1:flags=neighbor,fps=12,split[a][b];[a]palettegen[p];[b][p]paletteuse" \
    "$OUT/maniac-cht.gif"
chown -R 1000:1000 $P
ls -lh "$OUT/maniac-mansion-cht-promo.mp4" "$OUT/maniac-cht.gif"
ffprobe -v error -show_entries format=duration -show_entries stream=codec_type,codec_name \
        -of default=nw=1 "$OUT/maniac-mansion-cht-promo.mp4"
echo PROMO-OK
