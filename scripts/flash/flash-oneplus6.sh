#!/usr/bin/env bash
# Flash a Marathon (duranium/mkosi) image to OnePlus 6 (enchilada, SDM845).
#
# Duranium model on phones, per
# <https://postmarketos.org/blog/2026/03/17/introducing-duranium/>:
#
#   • The full Marathon system is a GPT disk image (ESP + /usr +
#     verity + /var + …) that gets written to the device's `userdata`
#     partition. U-Boot reads the embedded GPT via `blkmap` (acts like
#     losetup), boots systemd-boot from the inner ESP, which loads the
#     UKI from the inner /boot.
#   • The Android `boot` partition holds a one-time-flash bootimg
#     containing the EFI-aware u-boot + initramfs the bootrom hands
#     off to. boot-deploy generates it during the rootfs bake; we
#     extract it from the .esp split-artifact during
#     `build-oneplus6-image.sh`, so it sits next to the .raw.
#
# Expected artifacts produced by `./scripts/build-oneplus6-image.sh`,
# auto-detected in this order (override with env vars):
#
#   ROOTFS=<path>     defaults to
#                     ~/.cache/marathon-build/duranium/mkosi.output/
#                     oneplus-enchilada_marathon_edge/
#                     oneplus-enchilada_marathon_edge_<N>.raw
#   BOOT_IMG=<path>   defaults to <ROOTFS-dir>/boot.img (extracted
#                     from <ROOTFS-dir>/*.esp.raw at build time).
#
# Phone must be in fastboot mode: power off, hold Vol-Up, plug USB.
# Bootloader unlocked — if not, this script runs `fastboot oem unlock`
# (wipes userdata; user confirms on-device).
#
# Recovery if this bricks the device:
#   1. Re-flash via fastboot — almost always still works.
#   2. EDL/9008 mode (Vol-Up + Vol-Down + plug USB) + OnePlus MSM
#      Download Tool with enchilada_22_J.50_210121.zip to restore
#      OxygenOS, then re-unlock and re-run this script.
#
# Caveats — this is the duranium-on-phone flash protocol that the
# postmarketOS team documented in the introduction blog post and that
# their CI builds for. The exact procedure has been verified for OP6
# in the upstream CI matrix but has NOT been validated on Marathon's
# branch on actual hardware in this dev environment. Sanity-check the
# fastboot variables echoed below before you commit to flashing.

set -euo pipefail

CACHE="${MARATHON_BUILD_DIR:-$HOME/.cache/marathon-build}"
OUT_DIR="$CACHE/duranium/mkosi.output/oneplus-enchilada_marathon_edge"

ROOTFS="${ROOTFS:-}"
BOOT_IMG="${BOOT_IMG:-}"

usage() {
    cat <<USAGE
Usage: flash-oneplus6.sh [--rootfs PATH] [--boot-img PATH] [--no-unlock] [--rootfs-only]

  --rootfs PATH      duranium GPT image (.raw or .raw.zst).
                     default: $OUT_DIR/oneplus-enchilada_marathon_edge_<N>.raw
  --boot-img PATH    Android bootimg to flash to 'boot' partition.
                     default: <rootfs-dir>/boot.img
  --no-unlock        skip the bootloader unlock check (use if already unlocked
                     and you want to avoid the oem-unlock command path entirely).
  --rootfs-only      skip the boot-partition flash; only re-flash userdata.
                     Use after the one-time bootimg flash for subsequent updates.

  ROOTFS / BOOT_IMG env vars override the same things.

Phone prep:
  1. Power off.
  2. Hold Vol-Up + plug USB. "FASTBOOT MODE" appears on-screen.
  3. 'fastboot devices' from your host should list the phone.
USAGE
    exit 64
}

UNLOCK=1
ROOTFS_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --rootfs)       ROOTFS="$2"; shift 2 ;;
        --boot-img)     BOOT_IMG="$2"; shift 2 ;;
        --no-unlock)    UNLOCK=0; shift ;;
        --rootfs-only)  ROOTFS_ONLY=1; shift ;;
        -h|--help)      usage ;;
        *) echo "unknown arg: $1" >&2; usage ;;
    esac
done

# Auto-detect from build output if not supplied.
if [ -z "$ROOTFS" ]; then
    ROOTFS=$(ls -1t "$OUT_DIR"/oneplus-enchilada_marathon_edge_*.raw 2>/dev/null \
        | grep -E "/oneplus-enchilada_marathon_edge_[0-9]+\.raw$" | head -1 || true)
fi
[ -n "$ROOTFS" ] && [ -f "$ROOTFS" ] || {
    echo "error: rootfs image not found." >&2
    echo "       run ./scripts/build-oneplus6-image.sh first, or pass --rootfs PATH." >&2
    exit 1
}

if [ -z "$BOOT_IMG" ] && [ "$ROOTFS_ONLY" -eq 0 ]; then
    BOOT_IMG="$(dirname "$ROOTFS")/boot.img"
fi
if [ "$ROOTFS_ONLY" -eq 0 ]; then
    [ -f "$BOOT_IMG" ] || {
        echo "error: boot.img not found at $BOOT_IMG" >&2
        echo "       ./scripts/build-oneplus6-image.sh extracts it from the .esp.raw —" >&2
        echo "       re-run that script, or pass --boot-img PATH explicitly." >&2
        exit 1
    }
fi

need() { command -v "$1" >/dev/null || { echo "missing tool: $1" >&2; exit 1; }; }
need fastboot
need img2simg   # from android-tools / e2fsprogs-extra

# Decompress if needed.
ROOTFS_RAW="$ROOTFS"
case "$ROOTFS" in
    *.zst)
        need zstd
        ROOTFS_RAW="$(mktemp --suffix=.raw)"
        trap 'rm -f "$ROOTFS_RAW" "${ROOTFS_RAW%.raw}.sparse.raw"' EXIT
        echo "==> decompressing $ROOTFS to $ROOTFS_RAW"
        zstd -dc "$ROOTFS" > "$ROOTFS_RAW"
        ;;
    *.xz)
        ROOTFS_RAW="$(mktemp --suffix=.raw)"
        trap 'rm -f "$ROOTFS_RAW" "${ROOTFS_RAW%.raw}.sparse.raw"' EXIT
        echo "==> decompressing $ROOTFS to $ROOTFS_RAW"
        xz -dc "$ROOTFS" > "$ROOTFS_RAW"
        ;;
esac

echo "==> waiting for fastboot device"
echo "    (power off, hold Vol-Up, plug USB)"
fastboot devices

PRODUCT=$(fastboot getvar product 2>&1 | awk -F': ' '/^product:/ {print $2}')
echo "==> fastboot reports product=$PRODUCT"
case "$PRODUCT" in
    enchilada|OnePlus6) : ;;
    *)
        echo "error: connected device reports product=$PRODUCT, expected enchilada" >&2
        exit 1
        ;;
esac

# 1. Optional unlock. The OP6 wipes userdata on unlock; user must
#    confirm on-device with Vol keys + Power.
if [ "$UNLOCK" -eq 1 ]; then
    UNLOCKED=$(fastboot getvar unlocked 2>&1 | awk -F': ' '/^unlocked:/ {print $2}')
    if [ "$UNLOCKED" != "yes" ]; then
        echo "==> bootloader is locked — running 'oem unlock' (confirm on phone)"
        fastboot oem unlock
        echo "==> rebooting back to fastboot after unlock"
        fastboot reboot bootloader
        sleep 5
    fi
fi

# 2. Pin slot A. pmOS / Marathon are A-only; if prior OxygenOS left
#    B active, the flash lands in the wrong slot.
echo "==> pinning active slot to a"
fastboot --set-active=a

# 3. Erase dtbo so the duranium bootimg's appended DT wins
#    (OxygenOS's overlay would otherwise clobber sdm845-oneplus-
#    enchilada.dtb).
echo "==> erasing dtbo"
fastboot erase dtbo

# 4. One-time: flash the EFI-aware u-boot bootimg to `boot`. After
#    this, future Marathon updates only need to re-flash userdata —
#    re-run this script with --rootfs-only to skip step 4.
if [ "$ROOTFS_ONLY" -eq 0 ]; then
    echo "==> flashing boot ($(basename "$BOOT_IMG"), $(du -h "$BOOT_IMG" | awk '{print $1}'))"
    fastboot flash boot "$BOOT_IMG"
fi

# 5. Sparse-convert the rootfs. The OP6's fastboot
#    max-download-size is ~512 MiB; a multi-GB raw image will fail
#    transfer without sparse format. deviceinfo_flash_sparse="true"
#    confirms the device speaks sparse natively.
SPARSE="${ROOTFS_RAW%.raw}.sparse.raw"
if [ ! -f "$SPARSE" ] || [ "$ROOTFS_RAW" -nt "$SPARSE" ]; then
    SIZE=$(du -h "$ROOTFS_RAW" | awk '{print $1}')
    echo "==> sparse-converting rootfs ($SIZE → sparse)"
    img2simg "$ROOTFS_RAW" "$SPARSE"
fi

# 6. Flash sparse rootfs to userdata. The OP6 reserves no separate
#    Linux 'system' partition; userdata is the ~120 GB slot pmOS /
#    Marathon repurpose as rootfs. The duranium GPT sits inside this
#    block — u-boot's blkmap reads the inner partition table.
echo "==> flashing userdata ($(du -h "$SPARSE" | awk '{print $1}'))"
fastboot flash userdata "$SPARSE"

# 7. Reboot into Marathon.
echo "==> rebooting"
fastboot reboot

cat <<EOF

Flash complete. First boot takes ~30 s (u-boot + systemd-boot + UKI +
systemd userspace bring-up).

For subsequent Marathon updates, re-run with --rootfs-only to skip
the bootimg flash (you only need to do that once).

Diagnostics:
  - If the OnePlus splash hangs > 2 min: power off (Power 10 s), back
    to fastboot, re-flash boot.img.
  - If fastboot is dead too: EDL mode (Vol-Up + Vol-Down + plug USB)
    + OnePlus MSM Download Tool with enchilada_22_J.50_210121.zip to
    restore OxygenOS, then re-unlock and re-run this script.
  - Serial console: 3.5 mm jack with the Qualcomm SDM845 debug
    cable; 115200 8N1.
EOF
