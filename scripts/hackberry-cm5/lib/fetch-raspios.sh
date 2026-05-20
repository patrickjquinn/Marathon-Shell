#!/usr/bin/env bash
# Fetch (and decompress) the base RaspiOS Lite arm64 image. The image
# is the bookworm-based "Raspberry Pi OS Lite (64-bit)" without a
# desktop environment — we layer Marathon's session over it.
#
# We pin a specific dated release rather than tracking "latest" because
# we want reproducibility. Bump RASPIOS_DATE + URL together when we
# want a newer base.
set -euo pipefail

BUILD_DIR="$1"
SKIP_DOWNLOAD="${2:-0}"

# Pinned release. Bookworm-based; ships Qt 6.4 (within Marathon's
# 6.4-6.12 range), raspberrypi-bootloader, and the rpi-update'd kernel
# with RP1 + DPI support.
RASPIOS_DATE="${RASPIOS_DATE:-2025-05-13}"
RASPIOS_BASENAME="${RASPIOS_DATE}-raspios-bookworm-arm64-lite"
RASPIOS_IMG_URL="${RASPIOS_IMG_URL:-https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-${RASPIOS_DATE}/${RASPIOS_BASENAME}.img.xz}"

mkdir -p "$BUILD_DIR/base"
RASPIOS_XZ="$BUILD_DIR/base/${RASPIOS_BASENAME}.img.xz"
RASPIOS_IMG="$BUILD_DIR/base/${RASPIOS_BASENAME}.img"
WORK_IMG="$BUILD_DIR/work.img"

# Local override — point RASPIOS_IMG= at an already-downloaded file.
if [ -n "${RASPIOS_IMG_LOCAL:-}" ]; then
    if [ ! -f "$RASPIOS_IMG_LOCAL" ]; then
        echo "RASPIOS_IMG_LOCAL=$RASPIOS_IMG_LOCAL does not exist" >&2
        exit 1
    fi
    case "$RASPIOS_IMG_LOCAL" in
        *.img.xz)
            echo "  decompressing $RASPIOS_IMG_LOCAL → $WORK_IMG"
            xz -dc "$RASPIOS_IMG_LOCAL" > "$WORK_IMG"
            ;;
        *.img)
            cp -v "$RASPIOS_IMG_LOCAL" "$WORK_IMG"
            ;;
        *)
            echo "RASPIOS_IMG_LOCAL: unrecognized format ($RASPIOS_IMG_LOCAL)" >&2
            exit 1
            ;;
    esac
    echo "  using local RaspiOS image: $RASPIOS_IMG_LOCAL"
    exit 0
fi

# Download if missing.
if [ ! -f "$RASPIOS_IMG" ]; then
    if [ "$SKIP_DOWNLOAD" = "1" ]; then
        echo "  --skip-download: $RASPIOS_IMG missing; cannot continue" >&2
        exit 1
    fi
    if [ ! -f "$RASPIOS_XZ" ]; then
        echo "  fetching $RASPIOS_IMG_URL"
        curl -fL --retry 3 -o "$RASPIOS_XZ.tmp" "$RASPIOS_IMG_URL"
        mv "$RASPIOS_XZ.tmp" "$RASPIOS_XZ"
    fi
    echo "  decompressing $RASPIOS_XZ"
    xz -dc "$RASPIOS_XZ" > "$RASPIOS_IMG"
fi

# Working copy. We never mutate the base — re-run a fresh build by
# rm-ing work.img.
echo "  cp $RASPIOS_IMG → $WORK_IMG"
cp --reflink=auto -f "$RASPIOS_IMG" "$WORK_IMG"

echo "  ok"
