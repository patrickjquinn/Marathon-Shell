#!/usr/bin/env bash
# Build a Marathon image for the OnePlus 6 (codename: enchilada,
# SDM845). Targets the upstream pmaports device-oneplus-enchilada
# plus Marathon-Image's device-oneplus-enchilada-marathon overlay
# (depends= marathon-shell + the runtime stack + linux-marathon,
# mainline PREEMPT_RT for SDM845 via provides=/replaces=).
#
# Duranium model on phones, per
# <https://postmarketos.org/blog/2026/03/17/introducing-duranium/>:
#
#   • The system rootfs is a single GPT disk image (ESP + /usr + verity
#     + /var + …) that gets flashed to the device's `userdata`
#     partition. U-Boot reads the embedded GPT via the `blkmap`
#     command (acts like losetup), then boots systemd-boot from the
#     inner ESP, which loads the UKI from the inner /boot.
#   • The Android `boot` partition holds a one-time-flash bootimg
#     containing EFI-aware u-boot + initramfs. boot-deploy builds it
#     during the rootfs bake (device aport depends on mkbootimg +
#     systemd-boot + deviceinfo_generate_bootimg=true) and drops
#     /boot/boot.img-<kver>, which mkosi.repart's CopyFiles=/boot:/
#     lands at the ESP root.
#
# Output (under ~/.cache/marathon-build/duranium/mkosi.output/
#         oneplus-enchilada_marathon_edge/):
#
#   • oneplus-enchilada_marathon_edge_<N>.raw      — GPT disk image
#   • boot.img                                     — extracted from ESP
#
# Pair with scripts/flash/flash-oneplus6.sh to push both to the phone.
#
# First-run time: ~20 minutes (linux-marathon kernel build is the
# tall pole — adds ~10 min over the QEMU build).
#
#   ./scripts/build-oneplus6-image.sh
#   ./scripts/flash/flash-oneplus6.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/build-image.sh" oneplus-enchilada "$@"
