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
pip install --quiet fonttools
T=maniac_mansion_cht/deluxe/tools
G=deluxe/game-cht

python3 $T/check_batches.py deluxe/dumps/english14.txt maniac_mansion_cht/translations/deluxe

cat maniac_mansion_cht/translations/deluxe/b*.tsv > deluxe/dumps/zh_all.tsv
echo "合併譯文 $(wc -l < deluxe/dumps/zh_all.tsv) 行"

rm -rf $G && mkdir -p $G
cp -r deluxe/game-orig-14/. $G/
rm -f $G/*.tra                       # 只留中文，免得自動挑到別的語言

python3 $T/tra_codec.py build deluxe/dumps/zh_all.tsv -o $G/Chinese.tra --utf8

# 字型：不動 upem（放大交給引擎的 ags_ttf_font_size），只依譯文精簡字集
python3 $T/make_ags_font.py /usr/share/fonts/truetype/wqy/wqy-zenhei.ttc \
    -o deluxe/fonts/agsfnt-zh.ttf --scale 1 --subset-from deluxe/dumps/zh_all.tsv --fail-on-missing
for i in 0 1 2 3 4 5 6 7; do cp deluxe/fonts/agsfnt-zh.ttf $G/agsfnt$i.ttf; done

printf '[language]\ntranslation=Chinese\n' > $G/acsetup.cfg

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
