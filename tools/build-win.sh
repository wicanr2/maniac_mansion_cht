#!/bin/bash
# 交叉編 Windows 版 ScummVM（SCUMM + AGS），mingw-w64。
# [HARD] source 要另外複製一棵樹（scummvm-win），而且**不能排除 config.guess / config.sub**，
#        少了它們 configure 判不出 endianness 會直接失敗。
set -eux
cd /w
SDLVER=2.30.9
WORK=/w/tools/scummvm-win
PREFIX=/usr/x86_64-w64-mingw32

# ---- 1. mingw 的 SDL2 開發檔（Ubuntu 套件庫沒有，得從官方 release 拿）----
if [ ! -f "$PREFIX/include/SDL2/SDL.h" ]; then
    cd /tmp
    curl -fsSL -o SDL2-mingw.tar.gz \
      "https://github.com/libsdl-org/SDL/releases/download/release-${SDLVER}/SDL2-devel-${SDLVER}-mingw.tar.gz"
    tar xf SDL2-mingw.tar.gz
    cp -r SDL2-${SDLVER}/x86_64-w64-mingw32/* "$PREFIX/"
fi

# ---- 1b. libmad（AGS 引擎的相依：configure.engine 寫著 deps "16bit mad"）----
# 少了它 configure 會靜靜地把 AGS 關掉（config.mk 裡變成 "# ENABLE_AGS"），
# 編出來的 exe 跑 Deluxe 會說 "Could not find suitable engine plugin"。
if [ ! -f "$PREFIX/lib/libmad.a" ]; then
    cd /tmp
    curl -fsSL -o libmad.tar.gz \
      "https://downloads.sourceforge.net/mad/libmad-0.15.1b.tar.gz"
    rm -rf libmad-0.15.1b && tar xf libmad.tar.gz
    cd libmad-0.15.1b
    # 1998 年的 configure 會帶 -fforce-mem，現代 gcc 早就移除這個旗標
    sed -i 's/-fforce-mem//g' configure
    ./configure --host=x86_64-w64-mingw32 --prefix="$PREFIX" \
        --enable-static --disable-shared > /tmp/libmad-conf.log 2>&1 || { tail -20 /tmp/libmad-conf.log; exit 1; }
    make -j"$(nproc)" > /tmp/libmad-make.log 2>&1 || { tail -20 /tmp/libmad-make.log; exit 1; }
    make install > /dev/null
    cd /w
fi

# ---- 1c. FreeType（AGS 的 TTF 一定要它）----
# 一開始以為 AGS 自帶 lib/freetype-2.1.3 就夠，實跑才知道不是：帶了
# --disable-freetype2 之後，Deluxe 一啟動就 "Game needs FreeType library,
# which was not included in this build!"。ScummVM 是靠 freetype-config
# 這支腳本偵測的，所以 FreeType 要加 --enable-freetype-config 編。
if [ ! -f "$PREFIX/bin/freetype-config" ]; then
    cd /tmp
    curl -fsSL -o freetype.tar.xz \
      "https://download.savannah.gnu.org/releases/freetype/freetype-2.13.2.tar.xz"
    rm -rf freetype-2.13.2 && tar xf freetype.tar.xz
    cd freetype-2.13.2
    ./configure --host=x86_64-w64-mingw32 --prefix="$PREFIX" \
        --enable-static --disable-shared --enable-freetype-config \
        --with-zlib=no --with-bzip2=no --with-png=no --with-harfbuzz=no --with-brotli=no \
        > /tmp/ft-conf.log 2>&1 || { tail -20 /tmp/ft-conf.log; exit 1; }
    make -j"$(nproc)" > /tmp/ft-make.log 2>&1 || { tail -20 /tmp/ft-make.log; exit 1; }
    make install > /dev/null
    cd /w
fi

# ---- 2. 另一棵 source 樹（含 config.guess/config.sub）----
# [雷] 複製過來的樹裡有 Linux 那次的 config.mk / config.h / config.log。留著的話
#      configure 會被跳過、直接用「native g++ ＋ mingw as」去編 → 組譯器讀到 ELF 的
#      .type/.size 指示詞，噴一整片 "junk at end of line"。所以複製完一律清掉。
# [雷] exclude 要用 ./config.h 這種**錨定路徑**。寫成 config.h 會連
#      audio/softsynth/mt32/config.h（Munt 的版本標頭）一起排除掉，
#      編到 mt32emu 時就會噴 MT32EMU_VERSION_MAJOR 未宣告。
# [雷·2026-08-01] 這裡本來寫 `if [ ! -d "$WORK" ]`，只在第一次複製；之後每次重跑都是拿
#      **7/30 的舊 source** 再 make 一次。結果 Windows 版少了 24x24 的所有修改（字型尺寸偵測、
#      畫布 240、指令列重排），拿到 24x24 的字型檔卻用 16x15 的 metrics 去讀 → 每個字取 30 bytes
#      當 16x15 畫，畫面上就是一團藍色雜訊。Linux/AppImage 直接編 scummvm-src 所以沒事。
#      現在改成每次都同步(rsync 只搬有變動的檔案，.o 留著讓 make 增量編)。
mkdir -p "$WORK"
python3 - "$WORK" <<'PYSYNC'
import os, shutil, sys
src, dst = "/w/tools/scummvm-src", sys.argv[1]
skipdir = {".git", "build-ags"}
n = 0
for root, dirs, files in os.walk(src):
    dirs[:] = [d for d in dirs if d not in skipdir]
    rel = os.path.relpath(root, src)
    for f in files:
        if f.endswith((".o", ".a", ".log")) or (rel == "." and f in ("config.mk", "config.h")):
            continue
        s = os.path.join(root, f)
        d = os.path.join(dst, rel, f) if rel != "." else os.path.join(dst, f)
        if os.path.exists(d) and os.path.getsize(s) == os.path.getsize(d) and \
           abs(os.path.getmtime(s) - os.path.getmtime(d)) < 1:
            continue
        if os.path.exists(d) and open(s, "rb").read() == open(d, "rb").read():
            continue
        os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.copy2(s, d); n += 1
print("同步了 %d 個檔案到 %s" % (n, dst))
PYSYNC
rm -f "$WORK/config.mk" "$WORK/config.h" "$WORK/config.log"
test -f "$WORK/config.guess" && test -f "$WORK/config.sub"

# ---- 3. configure + make ----
cd "$WORK"
# [雷] 不要把 $PREFIX/bin 放進 PATH——裡面是 mingw 的 target binutils（as/ld/ar），
#      native g++ 會撿到它們而混用工具鏈。SDL 只要指到 sdl2-config 就好。
export SDL_CONFIG="$PREFIX/bin/sdl2-config"
if [ ! -f config.mk ]; then
    ./configure --host=x86_64-w64-mingw32 \
        --disable-all-engines --enable-engine=scumm --enable-engine=ags \
        --enable-release --disable-debug \
        --with-sdl-prefix="$PREFIX" \
        --with-freetype2-prefix="$PREFIX" \
        --disable-fluidsynth --disable-flac --disable-png \
        --disable-jpeg --disable-gif --disable-mpeg2 --disable-vpx --disable-tremor \
        --disable-mikmod --disable-openmpt --disable-fribidi --disable-retrowave \
        --disable-vorbis --disable-faad --disable-theoradec --disable-a52 \
        --disable-libcurl --disable-sndio --disable-timidity --disable-eventrecorder \
        > configure.log 2>&1 || { tail -40 configure.log; exit 1; }
    grep -qiE "Disabling engine SCUMM" config.log && { echo "### SCUMM 被剔除"; exit 13; } || true
    grep -qiE "Disabling engine AGS"   config.log && { echo "### AGS 被剔除";   exit 14; } || true
fi
make -j"$(nproc)" > build.log 2>&1 || { tail -40 build.log; exit 1; }
ls -l scummvm.exe
x86_64-w64-mingw32-strip scummvm.exe || true
ls -l scummvm.exe
echo WIN-BUILD-OK
