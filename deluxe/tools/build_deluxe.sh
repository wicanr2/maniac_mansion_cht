#!/bin/bash
# Deluxe 中文版一鍵建置：檢查分批譯文 → Chinese.tra → 精簡字型 → 組出可玩的遊戲夾
#
# 在工作目錄（workplace）下跑，預期的相對路徑：
#   deluxe/game-orig-14/      wine 裝出來的 v1.4 原版遊戲夾
#   deluxe/dumps/english14.txt 原文聯集（tra_codec.py keys 產生）
#   maniac_mansion_cht/       本 repo
# 產出 deluxe/game-cht/，可直接用含 AGS 引擎的 ScummVM 開起來。
set -eu
cd /w
pip install --quiet fonttools freetype-py
T=maniac_mansion_cht/deluxe/tools
G=deluxe/game-cht

python3 $T/check_batches.py deluxe/dumps/english14.txt maniac_mansion_cht/translations/deluxe

cat maniac_mansion_cht/translations/deluxe/b*.tsv > deluxe/dumps/zh_all.tsv
echo "合併譯文 $(wc -l < deluxe/dumps/zh_all.tsv) 行"

rm -rf $G && mkdir -p $G
cp -r deluxe/game-orig-14/. $G/
rm -f $G/*.tra                       # 只留中文，免得自動挑到別的語言

python3 $T/tra_codec.py build deluxe/dumps/zh_all.tsv -o $G/Chinese.tra --utf8

# 字型：全部槽位同一份、同一個尺寸。
# 遊戲跑在 640×400（見下方 acsetup.cfg 的 upscale），對白與 GUI 都用 24px；
# 24px 在 640 畫面上等於原本 320 畫面的 12px，字形細節放得下，也不會撐破選單按鈕框。
# 高解析模式下遊戲改用 13/14 號字型槽，所以 0–20 全部給同一份，免得漏槽掉回內建點陣字。
python3 $T/make_ags_font.py /usr/share/fonts/truetype/wqy/wqy-zenhei.ttc \
    -o deluxe/fonts/agsfnt-zh.ttf --scale 1 --subset-from deluxe/dumps/zh_all.tsv --fail-on-missing
for i in $(seq 0 20); do cp deluxe/fonts/agsfnt-zh.ttf $G/agsfnt$i.ttf; done

# 指令列那九顆按鈕是 CLIB 裡的手繪 sprite，翻譯機制碰不到。做法是把中文烘成同尺寸的
# sprite，寫成一份**鬆散的 acsprset.spr 放在遊戲夾**——引擎的 AssetManager 預設
# kAssetPriorityDir，目錄會排在 CLIB 前面，所以遊戲夾裡這一份會蓋過 Maniac.exe 裡的那份，
# 玩家原本的檔案完全不用動（實測：把 Give 換成橘色那張，畫面上就只有 Give 變橘）。
python3 $T/ags_clib.py extract deluxe/game-orig-14/Maniac.exe acsprset.spr -o /tmp/acsprset.spr
python3 $T/make_deluxe_buttons.py /tmp/acsprset.spr -o $G/acsprset.spr \
    --preview deluxe/spr/preview-zh.png

# upscale=1 讓 AGS 把這款 2.x 遊戲以 640×400 跑（engine/main/game_file.cpp:192），
# 中文才有足夠的像素畫得清楚；純資料設定，不必動引擎。
printf '[language]\ntranslation=Chinese\n[override]\nupscale=1\n' > $G/acsetup.cfg

# 回讀驗證：把產出的 .tra 解回來，逐行與來源比對
python3 - <<'PY'
import sys
sys.path.insert(0, "/w/maniac_mansion_cht/deluxe/tools")
from tra_codec import parse
info = parse("/w/deluxe/game-cht/Chinese.tra")
src = {}
for line in open("/w/deluxe/dumps/zh_all.tsv", encoding="utf-8"):
    if "\t" in line:
        k, v = line.rstrip("\n").split("\t", 1)
        src[k] = v
bad = 0
for k, v in info["pairs"]:
    k, v = k.decode("latin-1"), v.decode("utf-8")
    if src.get(k) != v:
        print("回讀不符:", repr(k), repr(v), repr(src.get(k))); bad += 1
        if bad > 5: break
print(f"回讀 {len(info['pairs'])} 組；來源 {len(src)} 組；{'完全一致' if not bad else str(bad)+' 組不符'}")
if bad or len(info['pairs']) != len(src):
    raise SystemExit(1)
PY

ls -l $G/Chinese.tra $G/agsfnt0.ttf
echo BUILD-OK
