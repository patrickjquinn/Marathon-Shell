#!/usr/bin/env bash
# Hackberry Pi build dispatcher.
#
# ZitaoTech ships four Hackberry variants. Marathon currently supports
# ONE of them:
#
#   ZitaoTech/HackberryPiCM5      CM5 + 720x720 HyperPixel-style panel
#                                 + USB-HID RP2040 keyboard
#                                 → ./scripts/build-hackberry-cm5-image.sh
#
# Other variants (Pi Zero 2 W, Pi 4B, Pi 5) are not supported. The CM5
# is the highest-spec Hackberry on the carrier and the variant the
# project is actively building against, so we focused there first.
# Adding the others is a smaller scope each (new device aport +
# config.txt + DTC overlay) than building the first one was.
#
# This script just dispatches to the CM5 path so the per-device
# wrapper layout matches the other devices.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat >&2 <<'NOTICE'
NOTE: scripts/build-hackberry-pi-image.sh is a compatibility wrapper.
The actual build is in scripts/build-hackberry-cm5-image.sh, which
targets the ZitaoTech HackberryPi CM5 (CM5 Lite + 720x720 panel).

If you want a different Hackberry variant (Pi Zero 2 W / 4B / Pi 5),
file an issue with the variant + your panel/keyboard hardware so we
can author its overlay.

Dispatching to scripts/build-hackberry-cm5-image.sh ...
NOTICE
exec bash "$SCRIPT_DIR/build-hackberry-cm5-image.sh" "$@"
