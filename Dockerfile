FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# 開發／擷取／影片／打包一條龍：
#  - scummvm + xvfb + imagemagick：headless 實機驗證與截圖
#  - freetype + freetype-py：烘 embedded-bitmap 中文字型（WQY Zen Hei Sharp face 2）
#  - build-essential 等：自編 patched ScummVM 與 scummtr
#  - wine：Deluxe（AGS fan remake）階段解私有安裝器用
RUN apt-get update && apt-get install -y --no-install-recommends \
    scummvm xvfb x11-utils xdotool imagemagick ffmpeg \
    python3 python3-pil python3-pip python3-venv \
    fonts-wqy-microhei fonts-wqy-zenhei fonts-noto-cjk \
    build-essential cmake pkg-config nasm git curl file \
    libsdl2-dev libsdl2-net-dev zlib1g-dev libpng-dev libfreetype6-dev \
    libogg-dev libvorbis-dev libflac-dev libmad0-dev libmpeg2-4-dev \
    liba52-dev libfluidsynth-dev libcurl4-openssl-dev \
    zstd zip unzip p7zip-full unrar-free gdb valgrind \
    && rm -rf /var/lib/apt/lists/*

# freetype-py 走獨立 venv，不動系統 python（venv 內含 system-site-packages 以沿用 python3-pil）
RUN python3 -m venv --system-site-packages /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir freetype-py
ENV PATH="/opt/venv/bin:${PATH}"

WORKDIR /work
