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

# ---- 2. 另一棵 source 樹（含 config.guess/config.sub）----
# [雷] 複製過來的樹裡有 Linux 那次的 config.mk / config.h / config.log。留著的話
#      configure 會被跳過、直接用「native g++ ＋ mingw as」去編 → 組譯器讀到 ELF 的
#      .type/.size 指示詞，噴一整片 "junk at end of line"。所以複製完一律清掉。
# [雷] exclude 要用 ./config.h 這種**錨定路徑**。寫成 config.h 會連
#      audio/softsynth/mt32/config.h（Munt 的版本標頭）一起排除掉，
#      編到 mt32emu 時就會噴 MT32EMU_VERSION_MAJOR 未宣告。
if [ ! -d "$WORK" ]; then
    mkdir -p "$WORK"
    tar -C /w/tools/scummvm-src -cf - \
        --exclude=.git --exclude='*.o' --exclude='*.a' --exclude=build-ags \
        --exclude=./config.mk --exclude=./config.h --exclude=./config.log . | tar -C "$WORK" -xf -
fi
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
        --disable-fluidsynth --disable-flac --disable-png --disable-freetype2 \
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
