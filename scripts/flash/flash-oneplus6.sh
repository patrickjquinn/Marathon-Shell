#!/usr/bin/env bash
# Flash a Marathon (duranium/mkosi) image to OnePlus 6 (enchilada, SDM845).
#
# Expects two artifacts produced by build-oneplus6-image.sh:
#   <prefix>-oneplus-enchilada-boot.img   (Android bootimg: kernel + dtb + initramfs)
#   <prefix>-oneplus-enchilada.img        (rootfs; will be sparse-converted)
#
# Phone must be in fastboot mode (Power off → hold Vol-Up + plug USB), bootloader
# unlocked. If not unlocked, this script will run `fastboot oem unlock` for you.
#
# Recovery if this bricks the device:
#   1. Re-flash via fastboot (almost always still works).
#   2. EDL/9008 (hold Vol-Up + Vol-Down while plugging USB) + MSM Download Tool
#      to restore OxygenOS, then unlock and re-run this script.

set -euo pipefail

IMAGE_DIR="${IMAGE_DIR:-$PWD/out}"
PREFIX="${PREFIX:-$(ls "$IMAGE_DIR"/*-oneplus-enchilada-boot.img 2>/dev/null | head -1 | sed 's/-boot\.img$//')}"

if [[ -z "${PREFIX:-}" ]]; then
    echo "error: could not auto-detect image prefix in $IMAGE_DIR" >&2
    echo "       set PREFIX=/path/to/<prefix>-oneplus-enchilada (without -boot.img)" >&2
    exit 1
fi

BOOT_IMG="${PREFIX}-boot.img"
ROOT_IMG="${PREFIX}.img"
ROOT_SPARSE="${PREFIX}.sparse.img"

[[ -f "$BOOT_IMG" ]] || { echo "missing $BOOT_IMG" >&2; exit 1; }
[[ -f "$ROOT_IMG" ]] || { echo "missing $ROOT_IMG" >&2; exit 1; }

need() { command -v "$1" >/dev/null || { echo "missing tool: $1" >&2; exit 1; }; }
need fastboot
need img2simg   # from android-tools / e2fsprogs-extra

echo "==> waiting for fastboot device (Power off, hold Vol-Up, plug USB)"
fastboot devices
fastboot getvar product 2>&1 | grep -qi enchilada || {
    echo "error: connected device is not enchilada" >&2
    exit 1
}

# 1. Unlock bootloader if needed. Wipes userdata; user confirms on-device.
if [[ "$(fastboot getvar unlocked 2>&1 | awk -F': ' '/^unlocked:/ {print $2}')" != "yes" ]]; then
    echo "==> bootloader is locked — running oem unlock (confirm on phone with Vol keys + Power)"
    fastboot oem unlock
    echo "==> rebooting back to fastboot after unlock"
    fastboot reboot bootloader
    sleep 5
fi

# 2. Pin slot A. pmOS / Marathon are A-only; if prior OxygenOS left B active the
#    flash lands in the wrong slot.
echo "==> pinning active slot to a"
fastboot --set-active=a

# 3. Erase dtbo so the appended-DT bootimg's DT wins (OxygenOS's overlay would
#    otherwise clobber sdm845-oneplus-enchilada.dtb).
echo "==> erasing dtbo"
fastboot erase dtbo

# 4. Flash boot.img (kernel + dtb + initramfs as a single Android bootimg).
echo "==> flashing boot ($BOOT_IMG)"
fastboot flash boot "$BOOT_IMG"

# 5. Sparse-convert the rootfs (fastboot max-download-size on enchilada is ~512
#    MiB; a multi-GB raw image will fail without sparse).
if [[ ! -f "$ROOT_SPARSE" || "$ROOT_IMG" -nt "$ROOT_SPARSE" ]]; then
    echo "==> sparse-converting rootfs ($(du -h "$ROOT_IMG" | awk '{print $1}'))"
    img2simg "$ROOT_IMG" "$ROOT_SPARSE"
fi

# 6. Flash rootfs to userdata. OP6 reserves no separate Linux 'system' partition;
#    userdata is the ~120 GB slot pmOS / Marathon repurpose as rootfs.
echo "==> flashing userdata ($ROOT_SPARSE)"
fastboot flash userdata "$ROOT_SPARSE"

# 7. Reboot into Marathon.
echo "==> rebooting"
fastboot reboot

cat <<'EOF'

Flash complete. First boot takes ~30 s (kernel + initramfs + systemd).

If the device hangs at the OnePlus splash for > 2 min:
  - Power off (hold Power 10 s), back to fastboot, re-flash boot.img.
  - If fastboot is dead too: EDL mode (Vol-Up + Vol-Down + plug USB), use
    OnePlus MSM Download Tool with enchilada_22_J.50_210121.zip to restore
    OxygenOS, then re-unlock and re-run this script.
EOF
