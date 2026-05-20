#!/usr/bin/env bash
# Compatibility wrapper. The Hackberry flash script is now per-variant.
#
# Currently supported:
#   • HackberryPi CM5 → scripts/flash/flash-hackberry-cm5.sh
#
# Other variants (Pi Zero 2 W, Pi 4B, Pi 5) aren't supported yet.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat >&2 <<'NOTICE'
NOTE: scripts/flash/flash-hackberry-pi.sh is a compatibility wrapper.
The actual flash logic is in scripts/flash/flash-hackberry-cm5.sh,
which targets the ZitaoTech HackberryPi CM5.

For other Hackberry variants, no flash script exists yet — file an
issue with your variant + hardware so we can author one.

Dispatching to scripts/flash/flash-hackberry-cm5.sh ...
NOTICE
exec bash "$SCRIPT_DIR/flash-hackberry-cm5.sh" "$@"
