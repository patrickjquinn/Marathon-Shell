#!/usr/bin/env bash
# Build a Marathon image for the Hackberry Pi.
#
# ─────────────────────────────────────────────────────────────────────
#  STATUS: NOT READY. See scripts/flash/flash-hackberry-pi.sh
#  header for the full blocker list. Short version:
#
#    • No CM4 Hackberry Pi exists. HackberryPi-4B is the closest
#      target.
#    • ST7701 720x720 panel timings aren't upstream
#      (panel-sitronix-st7701.c).
#    • BBQ10 I2C keyboard driver only exists out-of-tree
#      (billylindeman / mozcelikors / Beepberry forks).
#    • No pmaports `device-rpi*-hackberry` aport.
#    • No Marathon-Image `device-rpi*-hackberry-marathon` overlay.
#
#  Until those four items land, this script refuses to run. The
#  refusal is the honest answer — pretending to build an image
#  that won't display anything or accept input on flash would
#  waste your microSD and your trip to the keyboard.
# ─────────────────────────────────────────────────────────────────────
#
# What it would do once unblocked: target the Pi 4B
# (BCM2711) via mkosi + pftf/RPi4 EDK2 UEFI firmware, using
# `device-rpi4-hackberry` and `device-rpi4-hackberry-marathon`.
# That sequence is what scripts/flash/flash-hackberry-pi.sh
# --scaffold-4b assumes when it overlays UEFI onto the SD.
set -euo pipefail

cat >&2 <<'EOF'
Hackberry Pi support is not in a buildable state. Four upstream
items need to land first — see this script's header and
scripts/flash/flash-hackberry-pi.sh for details.

If you want the closest-thing-that-boots-but-renders-nothing path
for HackberryPi-4B bring-up, see flash-hackberry-pi.sh
--scaffold-4b — it'll write a vanilla postmarketOS Pi-4B image
to SD and you can use UART + SSH to develop the missing pieces.
EOF
exit 1
