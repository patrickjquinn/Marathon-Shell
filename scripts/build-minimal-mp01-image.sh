#!/usr/bin/env bash
# Build the Minimal Phone MP01 image (devices/minimal/mp01/README.md).
#
# Output: the GPT disk image (ESP and root) for the phone's userdata, in
# $MARATHON_BUILD_DIR/duranium/mkosi.output/minimal-mp01_marathon_edge/.
# Nothing composes the U-Boot boot image for boot_a yet, and there is no
# flash script: the MP01's boot chain is unproven.
#
# Needs the kernel aport device-minimal-mp01 names (linux-minimal-mp01).
# Arguments go to scripts/build-image.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/build-image.sh" minimal-mp01 "$@"
