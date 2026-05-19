#!/usr/bin/env bash
# Flash a Marathon image to a Hackberry Pi.
#
# ─────────────────────────────────────────────────────────────────────
#  STATUS: NOT READY. Read this whole header before running anything.
# ─────────────────────────────────────────────────────────────────────
#
# There is no CM4 Hackberry Pi. ZitaoTech (the designer) ships four
# variants, none of which is CM4:
#
#   ZitaoTech/Hackberry-Pi_Zero   — Pi Zero 2 W
#   ZitaoTech/HackberryPi-4B      — Pi 4B (BCM2711, microSD)         ← most viable
#   ZitaoTech/HackberryPi5        — Pi 5  (BCM2712)
#   ZitaoTech/HackberryPiCM5      — CM5   (BCM2712)
#
# Three independent blockers stop Marathon from booting on any of
# them today. None are solved by a flash script — they need real
# upstream / vendoring work first:
#
#  1. Display panel timings. The 4" 720×720 DSI panel uses an
#     ST7701 controller, but the Hackberry-specific timings aren't
#     in mainline panel-sitronix-st7701.c. Without a custom DT
#     overlay, the panel stays dark.
#
#  2. BBQ10 keyboard driver. arturo182's I²C keyboard at 0x1F has
#     out-of-tree kernel drivers (billylindeman, mozcelikors,
#     Beepberry forks) but nothing in mainline. Marathon needs a
#     kernel module built and shipped.
#
#  3. No pmaports device dir. There is no `device-rpi*-hackberry`
#     aport upstream. The closest template is the (still-pending)
#     `clockworkpi-uconsole` MR — also CM4-class, also vendored.
#
# What this script DOES:
#
#  - If you pass `--scaffold-4b`, it writes a Marathon image onto a
#    microSD using plain `dd` and overlays the pftf/RPi4 EDK2 UEFI
#    firmware so postmarketOS-Duranium's `Bootloader=systemd-boot`
#    can chainload. This boots on a HackberryPi-4B *to the point
#    where systemd starts* — but the screen will be black and the
#    keyboard will be unresponsive because of (1) and (2). It's
#    useful as a serial-console / SSH-over-USB-gadget bring-up
#    target while the panel + keyboard work catches up.
#
#  - Without `--scaffold-4b`, it refuses to flash and prints this
#    header.
#
# What this script DOES NOT DO:
#
#  - Doesn't pretend the CM4 variant exists.
#  - Doesn't fabricate a deviceinfo or a kernel package.
#  - Doesn't claim "it works" before the panel and keyboard drivers
#    are real and upstream-tracked.
#
# When the three blockers above are fixed:
#
#  - File a pmaports `device/testing/device-rpi-cm4-hackberry`
#    (or `-4b-hackberry`) modeled on `clockworkpi-uconsole`.
#  - Add a `device-rpi4-hackberry-marathon` overlay in
#    Marathon-Image/packages/ (same shape as
#    device-oneplus-enchilada-marathon).
#  - Add a `rpi4-hackberry` device entry to scripts/qemu/lib/
#    setup-trees.sh + a build-rpi4-hackberry-image.sh wrapper.
#  - Rewrite this script to be a real flasher (replace the
#    --scaffold-4b path with a tested HackberryPi-4B target).
#
# Sources for the above (browse before shipping):
#   https://github.com/ZitaoTech/HackberryPi-4B
#   https://github.com/ZitaoTech/HackberryPiCM5/issues/19
#   https://github.com/pftf/RPi4
#   https://gitlab.com/postmarketOS/pmaports/-/merge_requests/4751   (uconsole)
#   https://github.com/billylindeman/bbq10kbd-kernel-driver

set -euo pipefail

case "${1:-}" in
    --scaffold-4b)
        ;;
    -h|--help|"")
        sed -n '2,/^set -euo pipefail/p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "Hackberry Pi is not in a flashable state. See \`$0 --help\`." >&2
        exit 1
        ;;
esac

shift
DEV="${1:-}"
IMG="${2:-}"
UEFI_ZIP="${UEFI_ZIP:-}"

if [[ -z "$DEV" || -z "$IMG" ]]; then
    cat <<'USAGE'
Usage: flash-hackberry-pi.sh --scaffold-4b /dev/sdX /path/to/marathon-rpi4.raw

This path writes the image to the SD card AND overlays pftf/RPi4
UEFI firmware on the FAT32 boot partition so systemd-boot can
chainload. Display and keyboard will not work — see header.

UEFI firmware:
  Provide UEFI_ZIP=/path/to/RPi4_UEFI_Firmware_<ver>.zip from
  https://github.com/pftf/RPi4/releases. If unset, the script
  downloads v1.43 from GitHub at flash time.
USAGE
    exit 64
fi

[[ -b "$DEV" ]] || { echo "$DEV is not a block device" >&2; exit 1; }
[[ -f "$IMG" ]] || { echo "missing $IMG" >&2; exit 1; }
case "$DEV" in
    /dev/sda|/dev/nvme0n1|/dev/vda)
        echo "refusing to write to $DEV — looks like your host system disk" >&2
        exit 1
        ;;
esac

echo "==> overwriting $DEV with $IMG (HackberryPi-4B scaffold path)"
lsblk "$DEV" 2>/dev/null
read -r -p "type YES to confirm: " confirm
[[ "$confirm" = "YES" ]] || { echo "aborted"; exit 1; }

echo "==> dd image to $DEV"
case "$IMG" in
    *.xz)   xz -dc "$IMG" ;;
    *.gz)   gzip -dc "$IMG" ;;
    *)      cat "$IMG" ;;
esac | sudo dd of="$DEV" bs=4M conv=fsync status=progress
sudo sync

# Locate the FAT32 boot partition just-written. Conventionally
# partition 1 on a Pi image.
sudo partprobe "$DEV" 2>/dev/null || true
sleep 2
BOOT_PART="${DEV}1"
[[ -e "${DEV}p1" ]] && BOOT_PART="${DEV}p1"
[[ -b "$BOOT_PART" ]] || { echo "no partition 1 on $DEV"; exit 1; }

# Pull pftf/RPi4 UEFI firmware if not provided.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [[ -z "$UEFI_ZIP" ]]; then
    UEFI_ZIP="$WORK/RPi4_UEFI_Firmware.zip"
    echo "==> downloading pftf/RPi4 UEFI firmware v1.43"
    curl -fsSL -o "$UEFI_ZIP" \
        https://github.com/pftf/RPi4/releases/download/v1.43/RPi4_UEFI_Firmware_v1.43.zip
fi
[[ -f "$UEFI_ZIP" ]] || { echo "no UEFI zip at $UEFI_ZIP" >&2; exit 1; }

MNT="$WORK/boot"
mkdir -p "$MNT"
sudo mount "$BOOT_PART" "$MNT"
trap 'sudo umount "$MNT" 2>/dev/null; rm -rf "$WORK"' EXIT

echo "==> overlaying UEFI firmware onto $BOOT_PART"
sudo unzip -o -d "$MNT" "$UEFI_ZIP"

# Make sure config.txt loads the EDK2 firmware as the OS payload.
if ! grep -q "armstub=RPI_EFI.fd" "$MNT/config.txt" 2>/dev/null; then
    {
        echo
        echo "# Marathon: chain to pftf/RPi4 EDK2 UEFI."
        echo "armstub=RPI_EFI.fd"
        echo "enable_uart=1"
        echo "dtoverlay=disable-bt"
    } | sudo tee -a "$MNT/config.txt" >/dev/null
fi

sudo umount "$MNT"
trap 'rm -rf "$WORK"' EXIT
sudo sync

cat <<'NEXT'

==> done.

Insert SD into HackberryPi-4B and power on. You should see:
  • UART console at 115200 8N1 on the GPIO debug header.
  • Marathon boots to a black screen (panel driver not yet wired).
  • SSH listens on the wired ethernet (no wifi until firmware loaded).

To unblock display + keyboard, see the script header for the three
upstream work items.
NEXT
