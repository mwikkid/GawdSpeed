#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Earl Scioneaux, III
#
# Builds the ffmpeg command-line tool that ships inside GawdSpeed (spec §8.1):
# a pinned ffmpeg release plus LAME (for MP3 export), static, universal
# (arm64 + x86_64), decode-focused, network off, never --enable-nonfree.
#
# Output: build/ffmpeg/ffmpeg and build/ffmpeg/BUILDINFO.txt (versions,
# checksums and the exact configure lines, which go in the release notices).
# The app's build copies build/ffmpeg/ffmpeg into Contents/Helpers if present.
#
# Every GitHub Release must attach the two source archives below and this
# script (GPL corresponding source, spec §7.3, §7.7).

set -euo pipefail
cd "$(dirname "$0")/.."

FFMPEG_VERSION=9.0.2
FFMPEG_SHA256=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
LAME_VERSION=3.100
LAME_SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
MACOS_MIN=14.0

SRC=build/ffmpeg-src
WORK=build/ffmpeg-work
OUT=build/ffmpeg
JOBS=$(sysctl -n hw.ncpu)
mkdir -p "$SRC" "$WORK" "$OUT"

fetch() { # url file sha256
    if [[ ! -f "$SRC/$2" ]]; then
        echo "Downloading $2"
        curl -sSL --fail -o "$SRC/$2.part" "$1"
        mv "$SRC/$2.part" "$SRC/$2"
    fi
    echo "$3  $SRC/$2" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch for $2" >&2; exit 1; }
}
fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" "ffmpeg-$FFMPEG_VERSION.tar.xz" "$FFMPEG_SHA256"
fetch "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz" \
      "lame-$LAME_VERSION.tar.gz" "$LAME_SHA256"

# What ffmpeg needs to do for us (spec §5.10): read the formats AVFoundation
# can't, and write FLAC and MP3. Everything else stays disabled.
DEMUXERS=aac,ac3,aiff,amr,ape,asf,avi,caf,dsf,eac3,flac,iff,matroska,mov,mp3,ogg,tta,w64,wav,wv
DECODERS=aac,aac_latm,ac3,alac,amrnb,amrwb,ape,dsd_lsbf,dsd_lsbf_planar,dsd_msbf,dsd_msbf_planar,eac3,flac,mp1,mp2,mp3,mp3float,opus,tta,vorbis,wavpack,wmalossless,wmapro,wmav1,wmav2,pcm_alaw,pcm_f32be,pcm_f32le,pcm_f64be,pcm_f64le,pcm_mulaw,pcm_s16be,pcm_s16le,pcm_s24be,pcm_s24le,pcm_s32be,pcm_s32le,pcm_s8,pcm_u8
PARSERS=aac,aac_latm,ac3,flac,mpegaudio,opus,vorbis
ENCODERS=flac,libmp3lame,pcm_f32le,pcm_s16le,pcm_s24le
MUXERS=caf,flac,mp3,wav
FILTERS=aformat,anull,aresample,atrim

COMMON_FLAGS=(
    --disable-everything --disable-autodetect --disable-network --disable-doc
    --disable-ffplay --disable-ffprobe --disable-debug --disable-shared --enable-static
    --enable-gpl --enable-version3 --enable-libmp3lame
    --enable-protocol=file,pipe
    --enable-demuxer=$DEMUXERS --enable-decoder=$DECODERS --enable-parser=$PARSERS
    --enable-encoder=$ENCODERS --enable-muxer=$MUXERS --enable-filter=$FILTERS
    --enable-swresample
)

: > "$OUT/BUILDINFO.txt.part"
{
    echo "GawdSpeed bundled ffmpeg"
    echo "ffmpeg $FFMPEG_VERSION  sha256 $FFMPEG_SHA256  https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
    echo "LAME $LAME_VERSION  sha256 $LAME_SHA256  https://lame.sourceforge.io"
    echo "License of the built binary: GPL-3.0-or-later (--enable-gpl --enable-version3); LAME is LGPL-2.0-or-later"
    echo "Build-time change to LAME: remove 'lame_init_old' from include/libmp3lame.sym (a removed symbol the export list still names)."
} >> "$OUT/BUILDINFO.txt.part"

for ARCH in arm64 x86_64; do
    A="$WORK/$ARCH"
    # Spotlight can briefly hold files in a fresh build tree; retry the cleanup once.
    rm -rf "$A" 2>/dev/null || { sleep 2; rm -rf "$A"; }
    mkdir -p "$A"
    PREFIX="$(pwd)/$A/prefix"
    CFLAGS="-arch $ARCH -mmacosx-version-min=$MACOS_MIN -O2"
    HOST=$([[ $ARCH == arm64 ]] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)

    echo "== LAME $LAME_VERSION ($ARCH)"
    tar -xzf "$SRC/lame-$LAME_VERSION.tar.gz" -C "$A"
    (
        cd "$A/lame-$LAME_VERSION"
        sed -i '' '/lame_init_old/d' include/libmp3lame.sym
        ./configure --host="$HOST" --prefix="$PREFIX" --enable-static --disable-shared \
            --disable-frontend --disable-decoder --disable-dependency-tracking \
            CFLAGS="$CFLAGS" LDFLAGS="-arch $ARCH" > ../lame-configure.log 2>&1
        make -j"$JOBS" > ../lame-make.log 2>&1
        make install > ../lame-install.log 2>&1
    )

    echo "== ffmpeg $FFMPEG_VERSION ($ARCH)"
    tar -xJf "$SRC/ffmpeg-$FFMPEG_VERSION.tar.xz" -C "$A"
    ARCH_FLAGS=(--arch="$ARCH" --target-os=darwin --enable-cross-compile --cc="clang -arch $ARCH")
    [[ $ARCH == x86_64 ]] && ARCH_FLAGS+=(--disable-x86asm)
    CONFIGURE=(./configure "${COMMON_FLAGS[@]}" "${ARCH_FLAGS[@]}"
               --extra-cflags="$CFLAGS -I$PREFIX/include"
               --extra-ldflags="-arch $ARCH -mmacosx-version-min=$MACOS_MIN -L$PREFIX/lib")
    (
        cd "$A/ffmpeg-$FFMPEG_VERSION"
        "${CONFIGURE[@]}" > ../ffmpeg-configure.log 2>&1 || { tail -30 ../ffmpeg-configure.log; exit 1; }
        make -j"$JOBS" ffmpeg > ../ffmpeg-make.log 2>&1 || { tail -30 ../ffmpeg-make.log; exit 1; }
    )
    echo "configure ($ARCH): ${CONFIGURE[*]}" | sed "s|$(pwd)/||g" >> "$OUT/BUILDINFO.txt.part"
done

lipo -create "$WORK/arm64/ffmpeg-$FFMPEG_VERSION/ffmpeg" "$WORK/x86_64/ffmpeg-$FFMPEG_VERSION/ffmpeg" \
     -output "$OUT/ffmpeg"
strip -x "$OUT/ffmpeg"
mv "$OUT/BUILDINFO.txt.part" "$OUT/BUILDINFO.txt"
echo "Built $OUT/ffmpeg: $(lipo -archs "$OUT/ffmpeg"), $(du -h "$OUT/ffmpeg" | cut -f1)"
