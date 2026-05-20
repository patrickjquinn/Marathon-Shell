#!/usr/bin/env bash
# Flash a Marathon Edition image to a microSD for the ZitaoTech
# HackberryPi CM5 (CM5 Lite — boots from microSD on the Hackberry
# carrier, no eMMC dependency).
#
# Image source: ./scripts/build-hackberry-cm5-image.sh produces
#   ~/.cache/marathon-build/hackberry-cm5/out/marathon-hackberry-cm5.img.xz
# Decompresses on the fly so you can also pass a raw .img.
#
# Safety:
#   - refuses to write to /dev/sda, /dev/nvme0n1, /dev/vda
#     (your host's own disks)
#   - requires explicit "YES" confirmation before overwriting
#   - shows lsblk output so you can verify the target
#
# Flow after flashing:
#   1. Insert microSD into the Hackberry CM5 carrier.
#   2. Power on. RPi rainbow splash → kernel boot → systemd → lightdm.
#   3. lightdm auto-logs in as user "pi" and launches Marathon.
#   4. The HyperPixel 4.0 Square + hackberrypi overlay drive the
#      720x720 panel via DRM/KMS.
#
# Default user/password on the image: pi / raspberry (RaspiOS default).
# Change with `passwd` after first SSH/console login.
set -euo pipefail

CACHE="${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/hackberry-cm5"
DEFAULT_IMG_XZ="$CACHE/out/marathon-hackberry-cm5.img.xz"
DEFAULT_IMG_RAW="$CACHE/out/marathon-hackberry-cm5.img"

usage() {
    cat <<USAGE
Usage: flash-hackberry-cm5.sh /dev/sdX [/path/to/image.img(.xz)]

  /dev/sdX           target microSD block device (use lsblk to find).
  /path/to/image     optional override; default auto-detects:
                       1. $DEFAULT_IMG_XZ
                       2. $DEFAULT_IMG_RAW

Examples:
  # Build then flash (typical):
  ./scripts/build-hackberry-cm5-image.sh
  ./scripts/flash/flash-hackberry-cm5.sh /dev/sdb

  # Re-flash from a previous build:
  ./scripts/flash/flash-hackberry-cm5.sh /dev/sdb

  # Custom image:
  ./scripts/flash/flash-hackberry-cm5.sh /dev/sdb /tmp/marathon-cm5.img.xz
USAGE
    exit 64
}

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ -z "${1:-}" ] && usage

DEV="$1"
IMG="${2:-}"

# Auto-detect the image if not supplied.
if [ -z "$IMG" ]; then
    if [ -f "$DEFAULT_IMG_XZ" ]; then
        IMG="$DEFAULT_IMG_XZ"
    elif [ -f "$DEFAULT_IMG_RAW" ]; then
        IMG="$DEFAULT_IMG_RAW"
    else
        echo "error: no image found at $DEFAULT_IMG_XZ or $DEFAULT_IMG_RAW" >&2
        echo "       run ./scripts/build-hackberry-cm5-image.sh first" >&2
        exit 1
    fi
fi

[ -b "$DEV" ] || { echo "$DEV is not a block device" >&2; exit 1; }
[ -f "$IMG" ] || { echo "missing $IMG" >&2; exit 1; }

# Safety: refuse to clobber the host's own disks.
case "$DEV" in
    /dev/sda|/dev/nvme0n1|/dev/vda|/dev/mmcblk0)
        echo "refusing to write to $DEV — looks like your host system disk" >&2
        echo "double-check with 'lsblk' and pass the SD card's device explicitly" >&2
        exit 1
        ;;
esac

echo "==> about to overwrite $DEV with $IMG"
lsblk "$DEV" 2>/dev/null || true
read -r -p "type YES to confirm: " confirm
[ "$confirm" = "YES" ] || { echo "aborted"; exit 1; }

# Make sure nothing is mounted from the target.
for m in $(lsblk -nrpo MOUNTPOINT "$DEV" 2>/dev/null | grep -v '^$'); do
    echo "==> unmounting $m"
    sudo umount "$m" 2>/dev/null || true
done

echo "==> writing image (bs=4M, fsync)"
case "$IMG" in
    *.xz)   xz -dc "$IMG" ;;
    *.gz)   gzip -dc "$IMG" ;;
    *.zst)  zstd -dc "$IMG" ;;
    *.img)  cat "$IMG" ;;
    *)      echo "unrecognized image format: $IMG" >&2; exit 1 ;;
esac | sudo dd of="$DEV" bs=4M conv=fsync status=progress

sudo sync

echo
echo "==> done."
echo
echo "Eject the SD card, insert it into the HackberryPi CM5 carrier."
echo "Power on. First boot: ~30-60 s. LightDM auto-logs in as 'pi'."
echo
echo "Console / SSH:"
echo "  user:     pi"
echo "  password: raspberry  (RaspiOS default — change after first login)"
echo
echo "If the screen stays black: SSH in and check"
echo "  systemctl status lightdm"
echo "  journalctl -u lightdm --since '2 minutes ago'"
echo "  ls /boot/firmware/overlays/hackberrypi.dtbo   # overlay present?"
echo "  grep -E '^dtoverlay=' /boot/firmware/config.txt"
