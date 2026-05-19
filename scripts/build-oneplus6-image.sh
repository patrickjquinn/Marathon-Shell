#!/usr/bin/env bash
# Build a Marathon image for the OnePlus 6 (codename: enchilada,
# SDM845). Output is an Android boot.img + sparse rootfs ready for
# `scripts/flash/flash-oneplus6.sh` over fastboot.
#
# Targets the upstream pmaports device-oneplus-enchilada plus
# Marathon-Image's device-oneplus-enchilada-marathon overlay (which
# pulls marathon-shell + the runtime stack as dependencies).
# linux-marathon (mainline PREEMPT_RT kernel for SDM845) replaces
# the stock postmarketos-qcom-sdm845 kernel via provides=/replaces=.
#
# First-run time: ~20 minutes (linux-marathon kernel build is the
# tall pole — adds ~10 min over the QEMU build).
#
#   ./scripts/build-oneplus6-image.sh
#   # → image at ~/.cache/marathon-build/duranium/mkosi.output/
#   #   oneplus-enchilada_marathon_edge/...raw + boot.img
#   ./scripts/flash/flash-oneplus6.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/build-image.sh" oneplus-enchilada "$@"
