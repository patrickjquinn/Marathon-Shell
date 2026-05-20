#!/usr/bin/env bash
# Build a Marathon Edition SD-card image for the ZitaoTech HackberryPi
# CM5 (Raspberry Pi Compute Module 5 + 4" 720x720 HyperPixel-style DPI
# panel + RP2040 USB-HID keyboard).
#
# Unlike the duranium-based build path used for the OnePlus 6 and
# Librem 5, this pipeline produces a Raspberry Pi-firmware-bootable
# image:
#
#   bootrom → /boot/firmware/{bootcode.bin, start.elf, kernel8.img}
#           → device-tree (BCM2712-based) + overlay (hackberrypi)
#           → systemd → lightdm → marathon-shell as the Wayland session
#
# Approach: start from a stock RaspiOS Lite 64-bit image, customize
# it in-place via systemd-nspawn. RaspiOS Lite already has the right
# raspberrypi-bootloader / linux-image-rpi / firmware-brcm80211 set —
# we just layer Marathon on top and drop in the ZitaoTech overlay.
#
# Stages:
#
#   1. Host prereqs (losetup, systemd-nspawn, parted, dtc, etc.)
#   2. Fetch + decompress the pinned RaspiOS Lite arm64 image
#   3. Grow the rootfs partition so we fit Qt6 + Marathon
#   4. systemd-nspawn: apt install Qt6, build marathon-shell from
#      THIS checkout, install configs, enable lightdm autologin
#   5. Compile + drop in ZitaoTech's hackberrypi.dtbo overlay; append
#      HyperPixel + KMS lines to /boot/firmware/config.txt
#   6. Compress (xz) and emit out/marathon-hackberry-cm5.img.xz
#
# Env overrides:
#   MARATHON_BUILD_DIR      build-cache root (default ~/.cache/marathon-build)
#   RASPIOS_IMG_URL         override the base image URL
#   RASPIOS_IMG             use a local RaspiOS Lite .img / .img.xz
#                           (skips download)
#   GROW_TO                 final rootfs size in GiB (default 6)
#   SKIP_COMPRESS=1         leave the .img uncompressed (saves time
#                           during dev iteration)
#   KEEP_DEV                "1" → don't xz-compress, keep the .img for
#                           direct dd / quick reflash
#
# First-run time: ~30-45 minutes (Qt + WebEngine apt install + marathon
# CMake/Ninja build dominate). Subsequent builds reuse the cached
# base image but re-do the customization stage.
#
# Output:
#   ~/.cache/marathon-build/hackberry-cm5/out/marathon-hackberry-cm5.img.xz
#
# Flash:
#   ./scripts/flash/flash-hackberry-cm5.sh /dev/sdX

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MARATHON_SHELL_SRC="$(dirname "$SCRIPT_DIR")"
LIB="$SCRIPT_DIR/hackberry-cm5/lib"

BUILD_DIR="${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/hackberry-cm5"
mkdir -p "$BUILD_DIR/out"

# CLI parsing
SKIP_DOWNLOAD=0
SKIP_BUILD=0
for a in "$@"; do
    case "$a" in
        --skip-download) SKIP_DOWNLOAD=1 ;;
        --skip-build)    SKIP_BUILD=1 ;;
        -h|--help)
            sed -n '2,/^set -euo pipefail/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $a (try --help)" >&2; exit 64 ;;
    esac
done

echo "==> stage 1: host prerequisites"
bash "$LIB/check-host.sh"

echo "==> stage 2: base RaspiOS Lite image"
bash "$LIB/fetch-raspios.sh" "$BUILD_DIR" $SKIP_DOWNLOAD

if [ "$SKIP_BUILD" -eq 1 ]; then
    echo "==> --skip-build: image at $BUILD_DIR/work.img is the customized image; skipping customization stage"
    exit 0
fi

echo "==> stage 3-5: customize image (this is the long stage — go make coffee)"
sudo \
    MARATHON_BUILD_DIR="$BUILD_DIR" \
    MARATHON_SHELL_SRC="$MARATHON_SHELL_SRC" \
    GROW_TO="${GROW_TO:-6}" \
    bash "$LIB/customize-image.sh"

echo "==> stage 6: finalize"
bash "$LIB/finalize.sh" "$BUILD_DIR" "${SKIP_COMPRESS:-0}${KEEP_DEV:-}"

echo
echo "==> done."
echo "    Image: $BUILD_DIR/out/marathon-hackberry-cm5.img$([ "${SKIP_COMPRESS:-0}${KEEP_DEV:-}" = 1 ] && echo "" || echo ".xz")"
echo "    Flash: ./scripts/flash/flash-hackberry-cm5.sh /dev/sdX"
