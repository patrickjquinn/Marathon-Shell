#!/usr/bin/env bash
# Build a Marathon image for the Hackberry Pi.
#
# ─────────────────────────────────────────────────────────────────────
#  STATUS: NOT READY. See scripts/flash/flash-hackberry-pi.sh for the
#  full blocker list. The blocker shapes were corrected 2026-05-20
#  after a direct read of the ZitaoTech repos. Short version:
#
#    • The 720×720 panel is DPI/GPIO, driven by HyperPixel 4.0 Square
#      via raspberrypi-firmware config.txt overlays — NOT ST7701 DSI,
#      and not bootable via UEFI. Duranium's systemd-boot/UKI chain
#      can't apply the overlay.
#    • BBQ10 I²C keyboard driver only exists out-of-tree (canonical:
#      ardangelo/beepberry-keyboard-driver, DKMS-shipped).
#    • No pmaports `device-rpi*-hackberry` aport exists.
#    • Marathon would need a raspios-style build pipeline (config.txt
#      + cmdline.txt + HyperPixel overlay) parallel to duranium. That
#      pipeline doesn't exist yet.
#
#  Until those four items land, this script refuses to run. The
#  refusal is the honest answer — duranium would produce an image
#  that boots blind (no display, no keyboard) on Hackberry.
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

cat >&2 <<'EOF'
Hackberry Pi support is not in a buildable state.

The panel chain (HyperPixel 4.0 Square DPI), keyboard driver
(out-of-tree ardangelo/beepberry-keyboard-driver), and pipeline
(needs a raspios-style boot chain, not duranium) all need work
before this script can produce a real image.

See scripts/flash/flash-hackberry-pi.sh for the full breakdown
and links to upstream sources.
EOF
exit 1
