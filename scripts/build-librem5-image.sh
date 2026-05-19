#!/usr/bin/env bash
# Build a Marathon image for the Purism Librem 5 (codename:
# purism-librem5, NXP i.MX 8M Quad). Output is a raw disk image with
# phone-boot.img embedded at offset 33 KiB + ext4 /boot containing
# vmlinuz / initramfs / imx8mq-librem5-r{2,3,4}.dtb + the compiled
# boot.scr. Ready for scripts/flash/flash-librem5.sh (sd or eMMC).
#
# Targets the upstream pmaports device-purism-librem5 plus
# Marathon-Image's device-purism-librem5-marathon overlay (which
# pulls marathon-shell + the runtime stack as dependencies).
#
# A note on mkosi.Bootloader: the Librem 5's mainline u-boot does
# not consume systemd-boot's EFI loader path. The duranium-overlay
# under scripts/qemu/duranium-overlay/ pins Bootloader=none for
# this target and ships boot.scr alongside vmlinuz so u-boot can
# `ext2load` them directly.
#
# First-run time: ~15 minutes.
#
#   ./scripts/build-librem5-image.sh
#   # → image at ~/.cache/marathon-build/duranium/mkosi.output/
#   #   purism-librem5_marathon_edge/...raw
#   ./scripts/flash/flash-librem5.sh sd /dev/sdX <image.raw>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/build-image.sh" purism-librem5 "$@"
