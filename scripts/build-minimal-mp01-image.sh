#!/usr/bin/env bash
# Build the Minimal Phone MP01 image (devices/minimal/mp01/README.md).
#
# Output: the GPT disk image (ESP and root) for the phone's userdata, in
# $MARATHON_BUILD_DIR/duranium/mkosi.output/minimal-mp01_marathon_edge/.
# The U-Boot boot image for boot_b is built outside this tree, and nothing
# turns this output into the userdata image scripts/flash/flash-minimal-mp01.sh
# writes yet (devices/minimal/mp01/FLASHING.md).
#
# Needs the kernel aport device-minimal-mp01 names (linux-minimal-mp01).
# Arguments go to scripts/build-image.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/build-image.sh" minimal-mp01 "$@"
