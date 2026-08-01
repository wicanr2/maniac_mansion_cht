#!/bin/bash
# 在 GitHub Actions macos-14 runner 上編瘋狂大樓中文版的 ScummVM universal binary（arm64 + x86_64）。
#
# 為什麼是 CI 而不是本機：macOS 的 .app 需要 codesign / iconutil，只有 macOS host 有；
# Linux 端做不出來也測不出來（尤其 SDL 與 Gatekeeper 的雷）。
#
# 幾條踩過的規則（沿用 mac-app-cross-pack 的實戰結論）：
#   * 不要 brew install sdl2 —— 2026 年起那是 sdl2-compat shim，runtime 才 dlopen libSDL3，
#     打包抓不到 → 玩家端「Failed loading SDL3 library」。改自源碼編 pinned 真 SDL2 靜態庫。
#   * universal 不能單次雙 -arch（autoconf 版本解析會炸）→ 每弧各編一次再 lipo 合併。
#   * ScummVM 的 configure 不是 autoconf：CXXFLAGS/LDFLAGS 只能用環境變數前綴。
#   * 引擎要同時開 SCUMM 與 AGS（v2 中文版與 Deluxe 中文版共用一支 binary）。
#     AGS 的 TTF 走它自己 bundle 的 FreeType 2.1.3，所以 --disable-freetype2 沒問題。
set -euxo pipefail
MIN=13.4
SDLVER=2.30.9
ROOT="$PWD"
SVM="$ROOT/scummvm"
WORK="$ROOT/_macbuild"; mkdir -p "$WORK"

# ---- 1. SDL2 per-arch，自源碼靜態編 ----
curl -fsSL -o "$WORK/SDL2.tar.gz" \
  "https://github.com/libsdl-org/SDL/releases/download/release-${SDLVER}/SDL2-${SDLVER}.tar.gz"
for arch in arm64 x86_64; do
  rm -rf "$WORK/sdl-src-$arch"; mkdir -p "$WORK/sdl-src-$arch"
  tar xf "$WORK/SDL2.tar.gz" -C "$WORK/sdl-src-$arch" --strip-components=1
  P="$WORK/sdl-$arch"
  runner=""; [ "$arch" = x86_64 ] && runner="arch -x86_64"
  ( cd "$WORK/sdl-src-$arch"
    $runner env CFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
                LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
      ./configure --prefix="$P" --disable-shared --enable-static \
        --host="$( [ "$arch" = x86_64 ] && echo x86_64-apple-darwin || echo aarch64-apple-darwin )" \
        >/dev/null
    $runner make -j"$(sysctl -n hw.ncpu)" >/dev/null
    make install >/dev/null )
done

# ---- 1b. libmad per-arch（AGS 的相依，configure.engine 寫著 deps "16bit mad"）----
# 沒有它 configure 會靜靜地關掉 AGS，編出來的 binary 跑 Deluxe 會說
# "Could not find suitable engine plugin"——而且 configure 不會報錯，只有
# config.mk 裡從 "ENABLE_AGS = STATIC_PLUGIN" 變成 "# ENABLE_AGS"。
curl -fsSL -o "$WORK/libmad.tar.gz" \
  "https://downloads.sourceforge.net/mad/libmad-0.15.1b.tar.gz"
# libmad 附的 config.sub/config.guess 是 2004 年的，認不得 aarch64-apple-darwin，
# 會噴 "config.sub -apple-darwin23.6.0 failed"。直接借 ScummVM 樹裡的新版
# （比去 savannah 抓穩：那邊的 gitweb 網址會 404）。
cp "$SVM/config.sub" "$SVM/config.guess" "$WORK/"
for arch in arm64 x86_64; do
  rm -rf "$WORK/mad-src-$arch"; mkdir -p "$WORK/mad-src-$arch"
  tar xf "$WORK/libmad.tar.gz" -C "$WORK/mad-src-$arch" --strip-components=1
  P="$WORK/sdl-$arch"          # 與 SDL 裝在同一個 prefix，方便 configure 找
  runner=""; [ "$arch" = x86_64 ] && runner="arch -x86_64"
  cp "$WORK/config.sub" "$WORK/config.guess" "$WORK/mad-src-$arch/"
  chmod +x "$WORK/mad-src-$arch/config.sub" "$WORK/mad-src-$arch/config.guess"
  ( cd "$WORK/mad-src-$arch"
    sed -i '' 's/-fforce-mem//g' configure     # 1998 年的旗標，現代 clang 不認
    $runner env CFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
                LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
      ./configure --prefix="$P" --enable-static --disable-shared \
        --host="$( [ "$arch" = x86_64 ] && echo x86_64-apple-darwin || echo aarch64-apple-darwin )" \
        >/dev/null
    $runner make -j"$(sysctl -n hw.ncpu)" >/dev/null
    make install >/dev/null )
done

# ---- 1b2. libogg + libvorbis per-arch（Deluxe 的音效是 OGG）----
# [雷·2026-08-01] 原本帶 --disable-vorbis，Deluxe 在 macOS／Windows 上就「有音樂沒音效」：
# MMD 的 66 個音效（腳步、蟲鳴、開關門，多半 0.05-2.6 秒）是 OGG Vorbis，音樂是 MIDI。
# 少了 vorbis 時 ags/engine/media/audio/sound.cpp 的 my_load_ogg() 直接 return nullptr，
# 不警告也不報錯，音效就靜靜消失（GitHub issue #2）。
curl -fsSL --retry 3 -o "$WORK/libogg.tar.gz" "https://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.gz"
curl -fsSL --retry 3 -o "$WORK/libvorbis.tar.gz" "https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.gz"
for arch in arm64 x86_64; do
  P="$WORK/sdl-$arch"
  runner=""; [ "$arch" = x86_64 ] && runner="arch -x86_64"
  host="$( [ "$arch" = x86_64 ] && echo x86_64-apple-darwin || echo aarch64-apple-darwin )"
  for lib in ogg vorbis; do
    rm -rf "$WORK/$lib-src-$arch"; mkdir -p "$WORK/$lib-src-$arch"
    tar xf "$WORK/lib$lib.tar.gz" -C "$WORK/$lib-src-$arch" --strip-components=1
    extra=""; [ "$lib" = vorbis ] && extra="--with-ogg=$P"
    # libvorbis 的 configure 是靠 pkg-config 找 libogg 的，只給 --with-ogg 會噴
    # "must have Ogg installed!"，所以要把剛裝好的 ogg.pc 路徑帶進去。
    ( cd "$WORK/$lib-src-$arch"
      $runner env CFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
                  LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
                  PKG_CONFIG_PATH="$P/lib/pkgconfig" \
        ./configure --prefix="$P" --enable-static --disable-shared --host="$host" $extra >/dev/null
      $runner make -j"$(sysctl -n hw.ncpu)" >/dev/null
      make install >/dev/null )
  done
done

# ---- 1c. FreeType per-arch（AGS 的 TTF 一定要它）----
# AGS 雖然 bundle 了 lib/freetype-2.1.3，但 ScummVM 的 AGS 引擎要的是
# USE_FREETYPE2；帶 --disable-freetype2 的話 Deluxe 一啟動就
# "Game needs FreeType library, which was not included in this build!"。
# ScummVM 靠 freetype-config 偵測，所以要 --enable-freetype-config。
# savannah 偶爾回 502，所以備幾個鏡像輪流試
for url in \
  "https://download.savannah.gnu.org/releases/freetype/freetype-2.13.2.tar.xz" \
  "https://downloads.sourceforge.net/project/freetype/freetype2/2.13.2/freetype-2.13.2.tar.xz" \
  "https://github.com/freetype/freetype/archive/refs/tags/VER-2-13-2.tar.gz"
do
  if curl -fsSL --retry 3 --retry-delay 5 -o "$WORK/freetype.tar.xz" "$url"; then
    echo "FreeType 取自 $url"
    break
  fi
  echo "取不到，換下一個：$url"
done
test -s "$WORK/freetype.tar.xz"
for arch in arm64 x86_64; do
  rm -rf "$WORK/ft-src-$arch"; mkdir -p "$WORK/ft-src-$arch"
  tar xf "$WORK/freetype.tar.xz" -C "$WORK/ft-src-$arch" --strip-components=1
  P="$WORK/sdl-$arch"
  runner=""; [ "$arch" = x86_64 ] && runner="arch -x86_64"
  ( cd "$WORK/ft-src-$arch"
    $runner env CFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
                LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
      ./configure --prefix="$P" --enable-static --disable-shared --enable-freetype-config \
        --with-zlib=no --with-bzip2=no --with-png=no --with-harfbuzz=no --with-brotli=no \
        --host="$( [ "$arch" = x86_64 ] && echo x86_64-apple-darwin || echo aarch64-apple-darwin )" \
        >/dev/null
    $runner make -j"$(sysctl -n hw.ncpu)" >/dev/null
    make install >/dev/null )
done

# ---- 2. ScummVM per-arch（SCUMM + AGS）----
for arch in arm64 x86_64; do
  P="$WORK/sdl-$arch"
  runner=""; [ "$arch" = x86_64 ] && runner="arch -x86_64"
  ( cd "$SVM"
    make distclean >/dev/null 2>&1 || true
    find . -name '*.o' -delete 2>/dev/null || true
    $runner env \
      CXXFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
      CFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
      LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
      ./configure --disable-all-engines --enable-engine=scumm --enable-engine=ags \
        --enable-release --disable-debug \
        --with-sdl-prefix="$P/bin" \
        --with-mad-prefix="$P" \
        --with-freetype2-prefix="$P" \
        --with-ogg-prefix="$P" --with-vorbis-prefix="$P" \
        --disable-fluidsynth --disable-flac --disable-png \
        --disable-jpeg --disable-gif --disable-mpeg2 --disable-vpx --disable-tremor \
        --disable-mikmod --disable-openmpt --disable-fribidi --disable-retrowave \
        --disable-faad --disable-theoradec --disable-a52 \
        --disable-libcurl --disable-sndio --disable-timidity --disable-sparkle \
        --disable-eventrecorder
    # 守門：兩個引擎都要在
    grep -qiE "Disabling engine SCUMM" config.log && { echo "### SCUMM 被剔除"; exit 13; } || true
    grep -qiE "Disabling engine AGS"   config.log && { echo "### AGS 被剔除";   exit 14; } || true
    # Deluxe 的音效是 OGG，少了 vorbis 會「有音樂沒音效」且不報錯，所以在這裡擋下來
    grep -qE "^USE_VORBIS = 1" config.mk || { echo "### 沒編進 vorbis，Deluxe 會沒音效"; exit 15; }
    $runner make -j"$(sysctl -n hw.ncpu)"
    cp scummvm "$WORK/scummvm-$arch" )
done

# ---- 3. lipo 合成 universal ----
lipo -create "$WORK/scummvm-arm64" "$WORK/scummvm-x86_64" -output "$WORK/scummvm-universal"
lipo -info "$WORK/scummvm-universal"
lipo -info "$WORK/scummvm-universal" | grep -q arm64 && \
lipo -info "$WORK/scummvm-universal" | grep -q x86_64 || { echo "### 非雙弧"; exit 20; }

# ---- 4. 組 .app 並 ad-hoc 簽章 ----
APP="$ROOT/dist/ScummVM.app"; rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$WORK/scummvm-universal" "$APP/Contents/MacOS/scummvm"
cp "$SVM"/gui/themes/*.zip "$APP/Contents/Resources/" 2>/dev/null || true
cp "$SVM"/dists/engine-data/*.dat "$APP/Contents/Resources/" 2>/dev/null || true

# 注意：這裡**不放**任何中文資料。烘出來的倚天字型是商業字型的衍生物、
# Deluxe 的 .tra 夾帶英文原文，兩者都不進公開 repo，所以 CI 產出的是
# engine-only 的 .app，中文資料在本機組包時才注入（與遊戲資料同一個道理）。

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>scummvm</string>
<key>CFBundleIdentifier</key><string>org.scummvm.maniaccht</string>
<key>CFBundleName</key><string>ScummVM 瘋狂大樓中文版</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>maniac-cht</string>
<key>LSMinimumSystemVersion</key><string>$MIN</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
lipo -info "$APP/Contents/MacOS/scummvm"

# ---- 5. 打包（tar.gz 保 perm；APFS dmg 在 Windows/WSL 讀不到，Linux 端也做不出來）----
mkdir -p "$ROOT/dist"
OUTNAME="${OUTNAME:-maniac-cht-macos-app.tar.gz}"
tar czf "$ROOT/dist/$OUTNAME" -C "$ROOT/dist" ScummVM.app
echo "=== BUILD_OK:dist/$OUTNAME ==="
ls -la "$ROOT/dist"
