#!/usr/bin/env bash
# Flash a Marathon image to the original PINE64 PinePhone
# (pine64-pinephone), either to a microSD card or to the internal eMMC.
#
# The image from scripts/build-pinephone-image.sh is the whole disk: a
# pure MBR, the U-Boot SPL at byte 8 KiB, the ext4 boot partition and the
# root. Writing it with dd is the entire install, as on pmOS.
#
# Targets:
#   microSD  insert the card in a USB reader and pass its block device.
#            The A64 boot ROM always tries the microSD (upper slot)
#            before the eMMC, so this leaves the eMMC untouched.
#   eMMC     boot JumpDrive from a microSD card
#            (https://github.com/dreemurrs-embedded/Jumpdrive), plug the
#            phone into the host by USB-C, and pass the eMMC block device
#            it exposes. Then power off, remove the JumpDrive card and
#            boot. JumpDrive needs a charged battery.
#
# Before writing, the image is checked for the PinePhone layout (MBR, no
# GPT, an Allwinner eGON.BT0 SPL at 8 KiB), so an image built before
# pipeline patch 0022 (or for another device) is refused.
#
# Recovery: a correctly written microSD always boots, so a bad eMMC
# install is fixed by booting JumpDrive again and re-flashing.
set -euo pipefail

CACHE="${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}/duranium/mkosi.output/pine64-pinephone_marathon_edge"
DEFAULT_IMG=""
for f in "$CACHE"/pine64-pinephone_marathon_edge_*.raw; do
    [[ "$(basename "$f")" =~ ^pine64-pinephone_marathon_edge_[0-9]+\.raw$ ]] || continue
    { [ -z "$DEFAULT_IMG" ] || [ "$f" -nt "$DEFAULT_IMG" ]; } && DEFAULT_IMG="$f"
done

usage() {
    cat <<USAGE
Usage: flash-pinephone.sh /dev/sdX [/path/to/image.raw[.xz|.gz|.zst]]

  /dev/sdX        the microSD card, or the eMMC JumpDrive exposes (lsblk).
  image           default: the newest build,
                    ${DEFAULT_IMG:-$CACHE/pine64-pinephone_marathon_edge_<N>.raw}
USAGE
    exit 64
}

[ -z "${1:-}" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && usage

DEV="$1"
IMG="${2:-$DEFAULT_IMG}"
[ -n "$IMG" ] || { echo "error: no image under $CACHE; run ./scripts/build-pinephone-image.sh first" >&2; exit 1; }
[ -f "$IMG" ] || { echo "missing $IMG" >&2; exit 1; }

decompress() {
    case "$IMG" in
        *.xz)  xz -dc "$IMG" ;;
        *.gz)  gzip -dc "$IMG" ;;
        *.zst) zstd -dc "$IMG" ;;
        *.raw|*.img) cat "$IMG" ;;
        *) echo "unrecognized image format: $IMG" >&2; return 1 ;;
    esac
}

# The first 16 KiB hold everything the boot ROM looks at.
HEAD=$(mktemp)
trap 'rm -f "$HEAD"' EXIT
decompress | head -c 16384 > "$HEAD" || true
at() { dd if="$HEAD" bs=1 skip="$1" count="$2" status=none | tr -d '\000'; }
[ "$(at 510 2 | od -An -tx1 | tr -d ' \n')" = "55aa" ] \
    || { echo "refusing: $IMG has no MBR boot signature" >&2; exit 1; }
[ "$(at 512 8)" != "EFI PART" ] \
    || { echo "refusing: $IMG has a GPT, which overlaps the SPL at 8 KiB (built before pipeline patch 0022?)" >&2; exit 1; }
[ "$(at 8196 8)" = "eGON.BT0" ] \
    || { echo "refusing: $IMG has no Allwinner SPL (eGON.BT0) at 8 KiB" >&2; exit 1; }

[ -b "$DEV" ] || { echo "$DEV is not a block device" >&2; exit 1; }

# Never the disk the host runs from; ask before a non-removable one
# (JumpDrive's eMMC may report removable=0).
target_basename=$(basename "$DEV")
DEV_DISK=$(lsblk -no PKNAME "$DEV" 2>/dev/null | head -1)
[ -z "$DEV_DISK" ] && DEV_DISK="$target_basename"
ROOT_SRC=$(findmnt -no SOURCE / 2>/dev/null | sed 's|\[.*\]||')
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -1)
[ -z "$ROOT_DISK" ] && ROOT_DISK=$(basename "$ROOT_SRC")
if [ "$DEV_DISK" = "$ROOT_DISK" ] || [ "$target_basename" = "$ROOT_DISK" ]; then
    echo "refusing: $DEV is on the same disk as the host root ($ROOT_SRC)" >&2
    exit 1
fi
if [ "$(cat /sys/block/"$DEV_DISK"/removable 2>/dev/null || echo 0)" != "1" ]; then
    echo "warning: $DEV is not marked removable (fine for JumpDrive's eMMC)." >&2
    read -r -p "type FORCE to continue: " override
    [ "$override" = "FORCE" ] || { echo "aborted"; exit 1; }
fi

echo "==> about to overwrite $DEV with $IMG"
lsblk "$DEV" 2>/dev/null || true
read -r -p "type YES to confirm: " confirm
[ "$confirm" = "YES" ] || { echo "aborted"; exit 1; }

for m in $(lsblk -nrpo MOUNTPOINT "$DEV" 2>/dev/null | grep -v '^$'); do
    echo "==> unmounting $m"
    sudo umount "$m"
done

echo "==> writing image"
decompress | sudo dd of="$DEV" bs=4M conv=fsync status=progress
sudo sync

cat <<DONE

==> done.
microSD: put the card in the upper slot and power on; it boots before the eMMC.
eMMC:    power off, take out the JumpDrive card, power on.

First boot takes a minute (the root partition grows to fill the disk).
Over USB the host gets no DHCP lease: sudo ip addr add 172.16.42.2/24 dev <usb-if>,
then ssh to 172.16.42.1.
DONE
