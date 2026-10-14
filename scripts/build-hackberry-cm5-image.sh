#!/usr/bin/env bash
# Build a Marathon Edition microSD image for the ZitaoTech HackberryPi
# CM5 (Raspberry Pi Compute Module 5 + HyperPixel-style 720x720 DPI
# panel + RP2040 USB-HID keyboard).
#
# Same pipeline as OnePlus 6 / Librem 5: thin wrapper into the shared
# duranium/mkosi orchestrator at scripts/build-image.sh. Picks up the
# upstream pmaports `device-raspberry-pi5` (BCM2712, raspberrypi-
# bootloader, linux-rpi) plus packaging/'s
# `device-raspberry-pi5-hackberry-marathon` overlay aport, which ships
# the hackberrypi.dtbo + usercfg.txt + the marathon runtime stack
# (marathon-shell + marathon-plymouth-theme + greetd + …).
#
# Output: a fat16-boot + ext4 .raw GPT image ready to `dd` to microSD
# via scripts/flash/flash-hackberry-cm5.sh.
#
# First-run time: similar to the QEMU build (~15-20 min) since the
# heavy artifacts (Qt6, WebEngine, marathon-shell) are pre-built apks
# from the shared duranium pipeline.
#
#   ./scripts/build-hackberry-cm5-image.sh
#   # → image at ~/.cache/marathon-build/duranium/mkosi.output/
#   #   raspberry-pi5_marathon_edge/...raw
#   ./scripts/flash/flash-hackberry-cm5.sh /dev/sdX
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The Pi 5 build layers the HackberryPi overlay only when its apk is in
# mkosi.packages (mkosi.configure), so build it first.
MARATHON_TARGET_DEVICE=hackberrypi-cm5 bash "$SCRIPT_DIR/qemu/lib/build-device-marathon-apk.sh"
exec bash "$SCRIPT_DIR/build-image.sh" raspberry-pi5 "$@"
