#!/usr/bin/env bash
# Flash Marathon to a Minimal Phone MP01 through its stock bootloader's
# fastboot, and only fastboot (devices/minimal/mp01/FLASHING.md).
#
#   flash-minimal-mp01.sh [--slot a|b] BOOT.img USERDATA.img
#       Install: the userdata image (Android sparse or raw), then U-Boot's
#       boot image into boot_<slot> (default b), and makes that slot active.
#   flash-minimal-mp01.sh --boot-only [--slot a|b] BOOT.img
#       Only U-Boot's boot image, for U-Boot tests; userdata is kept.
#   flash-minimal-mp01.sh --restore-stock PARTS_DIR
#       Back to stock Android: boot_a and boot_b from the phone's own
#       backup (boot_a.bin, boot_b.bin, checked against SHA256SUMS-parts.txt
#       in PARTS_DIR or its parent when there is one), slot a active,
#       userdata and metadata wiped.
#
# The phone must be unlocked and in LK's fastboot: `adb reboot bootloader`
# from Android, or a U-Boot run that ended in fastboot. The stock vbmeta
# stays; an unlocked MP01 boots U-Boot in the orange state.
#
# Writes only boot_a or boot_b and userdata (and, restoring, metadata).
# Never lk, preloader, vbmeta, nvram, nvdata, nvcfg, md1img, protect1/2,
# persist, seccfg or misc.
set -euo pipefail

SLOT=b
MODE=install
while [ $# -gt 0 ]; do
    case $1 in
    --slot) SLOT=$2; shift ;;
    --boot-only) MODE=boot ;;
    --restore-stock) MODE=restore ;;
    -h | --help) sed -n '2,/^set -e/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 64 ;;
    *) break ;;
    esac
    shift
done
case $SLOT in a | b) ;; *) echo "error: --slot is a or b" >&2; exit 64 ;; esac

is_boot_image() { [ "$(head -c 8 "$1")" = 'ANDROID!' ]; }

case $MODE in
install)
    [ $# = 2 ] || { echo "usage: $0 [--slot a|b] BOOT.img USERDATA.img" >&2; exit 64; }
    BOOT=$1 USERDATA=$2
    ;;
boot)
    [ $# = 1 ] || { echo "usage: $0 --boot-only [--slot a|b] BOOT.img" >&2; exit 64; }
    BOOT=$1
    ;;
restore)
    [ $# = 1 ] || { echo "usage: $0 --restore-stock PARTS_DIR" >&2; exit 64; }
    PARTS=$1
    for p in boot_a boot_b; do
        if [ ! -f "$PARTS/$p.bin" ] || ! is_boot_image "$PARTS/$p.bin"; then
            echo "error: $PARTS/$p.bin is not a boot image" >&2
            exit 1
        fi
    done
    SUMS=
    for f in "$PARTS/../SHA256SUMS-parts.txt" "$PARTS/SHA256SUMS-parts.txt"; do
        [ ! -f "$f" ] || SUMS=$f
    done
    if [ -n "$SUMS" ]; then
        grep -E '  boot_[ab]\.bin$' "$SUMS" | (cd "$PARTS" && sha256sum -c --quiet)
    else
        echo "warning: no SHA256SUMS-parts.txt in or above $PARTS; the backup is not checked" >&2
    fi
    ;;
esac
[ "$MODE" = restore ] || is_boot_image "$BOOT" || { echo "error: $BOOT is not an Android boot image" >&2; exit 1; }

getvar() { fastboot getvar "$1" 2>&1 | sed -n "s/^$1: *//p" | head -1; }

n=$(fastboot devices | grep -c . || true)
[ "$n" = 1 ] || { echo "error: want exactly one fastboot device, found $n" >&2; exit 1; }
product=$(getvar product)
[ "$product" = Z10 ] || { echo "error: not an MP01 (fastboot getvar product: ${product:-?}, want Z10)" >&2; exit 1; }
unlocked=$(getvar unlocked)
[ "$unlocked" = yes ] || { echo "error: the bootloader is not unlocked (fastboot getvar unlocked: ${unlocked:-?})" >&2; exit 1; }

echo
case $MODE in
install)
    echo "This erases userdata (all Android apps, data and internal storage) and"
    echo "writes $(basename "$USERDATA") to it and $(basename "$BOOT") to boot_$SLOT;"
    echo "slot $SLOT becomes active."
    ;;
boot) echo "This writes $(basename "$BOOT") to boot_$SLOT and makes slot $SLOT active." ;;
restore)
    echo "This writes the stock boot_a and boot_b from $PARTS, makes slot a active"
    echo "and wipes userdata and metadata (Android starts as after a factory reset)."
    ;;
esac
read -r -p "type YES to continue: " confirm
[ "$confirm" = YES ] || { echo "aborted"; exit 1; }

case $MODE in
install)
    fastboot flash userdata "$USERDATA"
    fastboot flash "boot_$SLOT" "$BOOT"
    fastboot --set-active="$SLOT"
    ;;
boot)
    fastboot flash "boot_$SLOT" "$BOOT"
    fastboot --set-active="$SLOT"
    ;;
restore)
    fastboot flash boot_a "$PARTS/boot_a.bin"
    fastboot flash boot_b "$PARTS/boot_b.bin"
    fastboot --set-active=a
    fastboot -w
    ;;
esac
fastboot reboot
