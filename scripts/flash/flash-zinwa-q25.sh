#!/usr/bin/env bash
# Flash Marathon to a Zinwa Q25 (docs/install/ZINWA_Q25.md).
#
#   flash-zinwa-q25.sh --stock-lk LK.img [IMAGE_DIR]
#       A stock phone, unlocked, in the stock bootloader's fastboot mode:
#       writes userdata, then U-Boot to lk_a and lk_b, and reboots.
#   flash-zinwa-q25.sh --mtkclient [--stock-lk LK.img] [IMAGE_DIR]
#       Any phone, in BROM mode, through mtkclient: reinstalls userdata,
#       and U-Boot too when --stock-lk is given. Marathon's U-Boot has no
#       working fastboot, so this is the way back from a bad install.
#
# IMAGE_DIR holds scripts/build-zinwa-q25-image.sh's output (default
# $Q25_IMAGE_OUT, else $MARATHON_BUILD_DIR/q25): the newest
# *.userdata.img(.zst) and its .SHA256SUMS, u-boot-q25.bin and
# gimme-uboot.py.
#
# LK.img is the phone's own lk partition (lk_a), read with mtkclient
# (`mtk r lk_a lk_a.img`). It carries MediaTek's bl2_ext and the signing
# certificates, which Marathon cannot ship; gimme-uboot.py swaps its
# bootloader for U-Boot and keeps the rest. It needs liblk:
#   pip install --user git+https://github.com/R0rt1z2/liblk.git@75c8f14f16457b6c53d950d18d1ed7d2a665bed6
#
# Erases: userdata (all Android apps and data; internal storage), lk_a
# and lk_b (the Android bootloader: Android no longer starts). Nothing
# else is written.
set -euo pipefail

MODE=fastboot
STOCK_LK=
while [ $# -gt 0 ]; do
    case $1 in
    --mtkclient) MODE=mtkclient ;;
    --stock-lk) STOCK_LK=$(realpath "$2"); shift ;;
    -h | --help) sed -n '2,/^set -e/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 64 ;;
    *) break ;;
    esac
    shift
done
DIR=${1:-${Q25_IMAGE_OUT:-${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/q25}}
[ "$MODE" = mtkclient ] || [ -n "$STOCK_LK" ] || {
    echo "error: a stock phone needs --stock-lk (its lk_a, read with mtkclient)" >&2
    exit 64
}

USERDATA=$(ls -1t "$DIR"/*.userdata.img "$DIR"/*.userdata.img.zst 2> /dev/null | head -1 || true)
[ -n "$USERDATA" ] || { echo "error: no *.userdata.img in $DIR; run scripts/build-zinwa-q25-image.sh" >&2; exit 1; }
SUMS=${USERDATA%.userdata.img*}.SHA256SUMS
if [ -f "$SUMS" ]; then
    echo "==> checking $(basename "$SUMS")"
    (cd "$DIR" && sha256sum -c --quiet --ignore-missing "$(basename "$SUMS")")
else
    echo "warning: no $(basename "$SUMS"); the image is not checked" >&2
fi

TMP=$(mktemp -d -p "$DIR" .flash-q25.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
case $USERDATA in
*.zst)
    echo "==> decompressing $(basename "$USERDATA")"
    zstd -dq "$USERDATA" -o "$TMP/userdata.img"
    USERDATA=$TMP/userdata.img
    ;;
esac

LK=
if [ -n "$STOCK_LK" ]; then
    [ -f "$DIR/u-boot-q25.bin" ] && [ -f "$DIR/gimme-uboot.py" ] || {
        echo "error: $DIR lacks u-boot-q25.bin or gimme-uboot.py" >&2
        exit 1
    }
    python3 -c 'import liblk' 2> /dev/null || {
        echo "error: gimme-uboot.py needs liblk; see the top of $0" >&2
        exit 1
    }
    echo "==> putting U-Boot into $(basename "$STOCK_LK")"
    python3 "$DIR/gimme-uboot.py" "$STOCK_LK" "$DIR/u-boot-q25.bin" "$TMP/lk.img" > "$TMP/lk.log"
    python3 - "$DIR/u-boot-q25.bin" "$TMP/lk.img" << 'EOF' || { cat "$TMP/lk.log"; exit 1; }
import sys
from liblk.image import LkImage
uboot = open(sys.argv[1], 'rb').read()
lk = LkImage(sys.argv[2]).partitions['lk']
if not bytes(lk.data).startswith(uboot) or not lk.certs:
    sys.exit('error: the new lk image does not carry U-Boot with the stock certificates')
EOF
    LK=$TMP/lk.img
fi

echo
echo "This erases on the phone:"
echo "  userdata   all Android apps, data and internal storage"
[ -z "$LK" ] || echo "  lk_a lk_b  the Android bootloader; afterwards only Marathon starts"
echo "and writes $(basename "$USERDATA")${LK:+ and U-Boot}."
read -r -p "type YES to continue: " confirm
[ "$confirm" = YES ] || { echo "aborted"; exit 1; }

if [ "$MODE" = fastboot ]; then
    n=$(fastboot devices | grep -c . || true)
    [ "$n" = 1 ] || { echo "error: want exactly one fastboot device, found $n" >&2; exit 1; }
    unlocked=$(fastboot getvar unlocked 2>&1 | sed -n 's/^unlocked: *//p')
    [ "$unlocked" = yes ] || {
        echo "error: the bootloader is not unlocked (fastboot getvar unlocked: ${unlocked:-?})" >&2
        exit 1
    }
    fastboot flash userdata "$USERDATA"
    fastboot flash lk_a "$LK"
    fastboot flash lk_b "$LK"
    fastboot reboot
else
    command -v mtk > /dev/null || { echo "error: mtkclient's mtk is not on PATH" >&2; exit 1; }
    echo "==> unpacking the sparse image for mtkclient"
    simg2img "$USERDATA" "$TMP/userdata.raw"
    echo "Power the phone off, hold a volume key and plug in USB (BROM)."
    echo "Stop ModemManager first: it takes the MediaTek port."
    if [ -n "$LK" ]; then
        mtk w userdata,lk_a,lk_b "$TMP/userdata.raw,$LK,$LK"
    else
        mtk w userdata "$TMP/userdata.raw"
    fi
    echo "==> done; hold power for about 15 s to restart the phone"
fi
echo "First boot grows the storage and sets up encrypted /home; allow a few minutes."
