#!/usr/bin/env bash
# Build a Marathon image for the original PINE64 PinePhone (codename:
# pine64-pinephone, Allwinner A64). Not the PinePhone Pro, which boots
# differently.
#
# Targets the upstream pmaports device-pine64-pinephone plus packaging/'s
# device-pine64-pinephone-marathon overlay, and builds the forks it
# depends on (linux-postmarketos-allwinner-marathon,
# u-boot-pinephone-marathon, pinephone-callaudiod-marathon).
#
# Output is a raw disk image with a pure MBR (the A64 boot ROM reads the
# U-Boot SPL at byte 8 KiB, where a GPT's partition entries would be),
# u-boot-sunxi-with-spl-528.bin at 8 KiB, an ext4 boot partition with
# vmlinuz, initramfs, allwinner/*.dtb and boot.scr, then the root
# partition (pipeline patches 0022 and 0023). The disk surgery runs
# `sudo -A`, so set SUDO_ASKPASS.
#
#   ./scripts/build-pinephone-image.sh
#   # → image at ~/.cache/marathon-build/duranium/mkosi.output/
#   #   pine64-pinephone_marathon_edge/...raw
#   ./scripts/flash/flash-pinephone.sh /dev/sdX
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/build-image.sh" pine64-pinephone "$@"
