#!/usr/bin/env bash
# Flash a Marathon image to a Hackberry Pi.
#
# ─────────────────────────────────────────────────────────────────────
#  STATUS: NOT READY. Read this whole header before running anything.
# ─────────────────────────────────────────────────────────────────────
#
# ZitaoTech ships four Hackberry variants — none of them CM4:
#
#   ZitaoTech/Hackberry-Pi_Zero   — Pi Zero 2 W
#   ZitaoTech/HackberryPi-4B      — Pi 4B (BCM2711)        ← most viable
#   ZitaoTech/HackberryPi5        — Pi 5  (BCM2712)
#   ZitaoTech/HackberryPiCM5      — CM5   (BCM2712)
#
# Three independent blockers stop Marathon from booting on any of
# them today. The blocker shapes were updated 2026-05-20 after a
# direct read of the ZitaoTech repos + pmaports + pftf/RPi4 docs.
# The earlier "ST7701 DSI panel" framing was wrong.
#
#  1. Panel chain mismatch.
#     The 4" 720×720 TFT is wired to the Pi's 24-pin DPI/GPIO header,
#     NOT MIPI-DSI. ZitaoTech's docs (HackberryPi-4B/Screen,
#     HackberryPiCM5 Operating System notes) drive it via Pimoroni's
#     HyperPixel 4.0 Square overlay: `dtoverlay=vc4-kms-dpi-hyperpixel4sq`
#     in /boot/config.txt, plus `dtoverlay=vc4-kms-v3d`. This means
#     three things for Marathon:
#       a) panel-sitronix-st7701.c in mainline Linux is NOT relevant.
#       b) The display only comes up AFTER Linux DRM loads the
#          HyperPixel overlay — UEFI firmware (pftf/RPi4 EDK2) cannot
#          drive a DPI panel. Boot-time display is impossible.
#       c) Duranium's systemd-boot + erofs+verity layout has nowhere
#          to inject `dtoverlay=...` into /boot/config.txt. Marathon
#          would need a Raspberry-Pi-OS-style boot chain (config.txt +
#          cmdline.txt + raspberrypi-firmware boot), NOT duranium.
#
#  2. BBQ10 keyboard driver.
#     The canonical fork as of 2026-05 is ardangelo/beepberry-keyboard-driver
#     shipped as a DKMS package via the ardangelo.github.io/beepy-ppa
#     apt repo. It's out-of-tree, RP2040-firmware-coupled, and has not
#     been submitted to linux-input. Marathon would have to wrap it as
#     an Alpine APKBUILD against a fixed kernel ABI, or carry it as a
#     kernel patch.
#
#  3. No pmaports device dir.
#     There is no `device-rpi*-hackberry`, no `beepy`, no `beepberry`
#     aport in postmarketOS pmaports. Closest precedent for the kind
#     of handheld-on-Pi overlay we'd need is the `clockworkpi-uconsole`
#     aport (MR 4751 against pmaports).
#
# What this script DOES today:
#
#   refuses to flash, points you here, and exits.
#
# The earlier `--scaffold-4b` mode wrote a Marathon (duranium) image
# to SD + overlaid pftf/RPi4 EDK2 UEFI on the FAT32 boot partition.
# That mode has been REMOVED because it was misleading:
#
#   - Duranium boots via systemd-boot/UKI — fine on the Pi 4B once UEFI
#     loads, but the HyperPixel DPI overlay is never applied (duranium
#     doesn't ship raspberrypi-firmware-style config.txt overlays),
#     so the screen stays dark forever.
#   - SSH-over-USB-gadget bring-up isn't useful either: there's no
#     duranium aport that enables g_ether on the Pi.
#
# When the blockers above are addressed, the right path is a parallel
# raspios-style build (NOT duranium): config.txt + cmdline.txt +
# HyperPixel overlay + bbq10-kbd DKMS apk + a `device-rpi4-hackberry-marathon`
# overlay aport. That's a separate build pipeline from
# `scripts/build-image.sh`, not a flag on it.
#
# Sources (browse before shipping):
#   https://github.com/ZitaoTech/HackberryPi-4B
#   https://github.com/ZitaoTech/HackberryPiCM5/tree/main/Operating%20System
#   https://github.com/ardangelo/beepberry-keyboard-driver
#   https://ardangelo.github.io/beepy-ppa/docs/beepy-kbd.html
#   https://github.com/pftf/RPi4/releases
#   https://gitlab.com/postmarketOS/pmaports/-/merge_requests/4751   (uconsole template)

set -euo pipefail

case "${1:-}" in
    -h|--help|"")
        sed -n '2,/^set -euo pipefail/p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "Hackberry Pi is not in a flashable state. See '$0 --help'." >&2
        exit 1
        ;;
esac
