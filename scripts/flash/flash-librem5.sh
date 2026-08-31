#!/usr/bin/env bash
# Flash a Marathon (duranium/mkosi) image to Purism Librem 5
# (i.MX 8M Quad, codename: purism-librem5).
#
# Two flash paths:
#
#   sd     dd the .raw to a microSD, insert into the phone's slot, hold
#          Vol-Down at power-on. The Librem 5 bootrom checks SD before
#          eMMC when Vol-Down is held. Non-destructive — eMMC stays put.
#
#   emmc   USB-tethered flash to internal eMMC via NXP's Serial Download
#          Protocol (SDP) using `uuu`. Boots phone-boot.img into RAM,
#          drops the device into Fastboot, sparse-flashes the raw image
#          to mmc0. This is the canonical postmarketOS path
#          (deviceinfo_flash_method=uuu).
#
# Both paths depend on Marathon's image having been built with
#   Bootloader=none
#   first partition starting at 2 MiB (4096 sectors)
# and shipping phone-boot.img + an ext4 /boot with vmlinuz / initramfs /
# imx8mq-librem5-r{2,3,4}.dtb / boot.scr. The librem5-specific mkosi
# profile in scripts/qemu/duranium-overlay handles that — DO NOT use
# the QEMU image here.

set -euo pipefail

MODE="${1:-}"
IMG="${2:-}"

usage() {
    cat <<'USAGE'
Usage: flash-librem5.sh sd  /dev/sdX     /path/to/marathon-librem5.raw[.xz]
       flash-librem5.sh emmc            /path/to/marathon-librem5.raw[.xz]

Env:
  UBOOT      path to phone-boot.img (auto-detected from
             ~/.cache/marathon-build/duranium/mkosi.output/purism-librem5_marathon_edge/phone-boot.img
             — the build orchestrator extracts it there. Falls back to
             /usr/share/u-boot/librem5/phone-boot.img if u-boot-librem5
             is installed system-wide, or ./phone-boot.img.).

sd path:
  Insert SD card. Pass its block device as the second arg.
  After flashing: insert SD into phone, power off, hold Vol-Down,
  press Power. The Librem 5 bootrom prefers SD over eMMC when
  Vol-Down is held.

emmc path:
  1. Flip all three hardware kill switches OFF (top edge of phone).
  2. Power off, remove battery.
  3. Hold Vol+, plug USB-C to host. Red LED blinks.
  4. Reinsert battery. Red LED solid. Release Vol+.
  5. `lsusb` should show 1fc9:012b NXP i.MX 8M Quad SDP.
  6. Run this script. uuu chainloads u-boot, exposes the eMMC as a
     Fastboot gadget, and sparse-writes your raw image.

Recovery (dead phone):
  • UART4 console under the back cover (Purism's debug pads, or the
    devkit's UART breakout). 115200 8N1.
  • Reboot into SDP (step 3-5 above) → re-flash phone-boot.img →
    reboot into u-boot prompt → `fastboot 0` exposes eMMC for
    re-flash from host.
USAGE
    exit 64
}

[[ -z "$MODE" || -z "$IMG" || "$MODE" = "-h" || "$MODE" = "--help" ]] && usage

# Decompress on-the-fly path
decompress_to() {  # decompress_to <src> <dst-fd>
    case "$1" in
        *.xz)   xz -dc "$1" ;;
        *.gz)   gzip -dc "$1" ;;
        *.zst)  zstd -dc "$1" ;;
        *)      cat "$1" ;;
    esac
}

case "$MODE" in
    sd)
        DEV="$IMG"; IMG="${3:-}"
        [[ -z "$IMG" ]] && usage
        [[ -b "$DEV" ]] || { echo "$DEV is not a block device" >&2; exit 1; }
        [[ -f "$IMG" ]] || { echo "missing $IMG" >&2; exit 1; }

        # Refuse to clobber the host's own disk by accident.
        case "$DEV" in
            /dev/sda|/dev/nvme0n1|/dev/vda)
                echo "refusing to write to $DEV — looks like your host system disk" >&2
                exit 1
                ;;
        esac

        echo "==> about to overwrite $DEV with $IMG"
        lsblk "$DEV" 2>/dev/null
        read -r -p "type YES to confirm: " confirm
        [[ "$confirm" = "YES" ]] || { echo "aborted"; exit 1; }

        echo "==> writing image…"
        decompress_to "$IMG" | sudo dd of="$DEV" bs=4M conv=fsync status=progress
        sudo sync
        echo "==> done. Insert SD into Librem 5, power off, hold Vol-Down, press Power."
        ;;

    emmc)
        [[ -f "$IMG" ]] || { echo "missing $IMG" >&2; exit 1; }
        command -v uuu >/dev/null || {
            echo "error: uuu not on \$PATH" >&2
            echo "       dnf install nxp-mfgtools / apt install mfgtools / pacman -S mfgtools" >&2
            exit 1
        }

        # Locate phone-boot.img. The build orchestrator
        # (scripts/build-image.sh) extracts this from the
        # u-boot-librem5 apk into mkosi.output/ next to the .raw image
        # whenever MARATHON_TARGET_DEVICE=purism-librem5.
        UBOOT="${UBOOT:-}"
        if [[ -z "$UBOOT" ]]; then
            for c in \
                "$HOME/.cache/marathon-build/duranium/mkosi.output/purism-librem5_marathon_edge/phone-boot.img" \
                /usr/share/u-boot/librem5/phone-boot.img \
                ./phone-boot.img
            do
                [[ -r "$c" ]] && { UBOOT="$c"; break; }
            done
        fi
        [[ -r "$UBOOT" ]] || {
            echo "error: phone-boot.img not found. set UBOOT=/path/to/phone-boot.img" >&2
            echo "       (packaging/'s device-purism-librem5-marathon ships one)" >&2
            exit 1
        }

        # uuu wants an uncompressed raw. Decompress to a temp file if needed.
        RAW="$IMG"
        case "$IMG" in
            *.xz|*.gz|*.zst)
                RAW="$(mktemp --suffix=.raw)"
                trap 'rm -f "$RAW"' EXIT
                echo "==> decompressing $IMG to $RAW"
                decompress_to "$IMG" > "$RAW"
                ;;
        esac

        # Compose the SDP → Fastboot uuu script (canonical pmaports
        # flash_script.lst for purism-librem5).
        #
        # uuu's filemap resolves script-referenced paths *relative to the .lst's
        # directory*, then concatenates absolute paths naively (giving
        # `/tmp//abs/path`). Stage the .lst, phone-boot.img, and raw image in a
        # single workdir and refer to them by basename to sidestep that bug.
        UUU_DIR="$(mktemp -d --suffix=.uuu)"
        trap 'rm -rf "$UUU_DIR"' EXIT
        cp -- "$UBOOT" "$UUU_DIR/phone-boot.img"
        # Hardlink the raw when possible (avoids copying multi-GB); fall back to
        # symlink across filesystems.
        ln -- "$RAW" "$UUU_DIR/marathon.raw" 2>/dev/null || \
            ln -s -- "$RAW" "$UUU_DIR/marathon.raw"
        SCRIPT="$UUU_DIR/flash_script.lst"
        # Canonical pmaports purism-librem5 sequence. The script we
        # shipped previously was missing the SDPU + SDPS stages — without
        # those u-boot loads via SDPV but defaults to UMS (USB mass
        # storage) instead of fastboot, so every FB: command silently
        # noop'd. See pmaports/device/main/device-purism-librem5/
        # flash_script.lst.
        cat > "$SCRIPT" <<'EOF'
uuu_version 1.0.1
SDP:  boot -f phone-boot.img
SDPU: delay 1000
SDPU: write -f phone-boot.img -offset 0x57c00
SDPU: jump
SDPV: delay 1000
SDPV: write -f phone-boot.img -skipspl
SDPV: jump
SDPS: boot -f phone-boot.img
FB:   ucmd mmc dev 0
FB:   flash -raw2sparse mmc0 marathon.raw
FB:   Done
EOF

        cat <<'STEPS'
==> kill switches: all three OFF (top edge of the phone).
==> power off, remove battery.
==> hold Vol+, plug USB-C, reinsert battery. Red LED solid. Release Vol+.
==> `lsusb` should show 1fc9:012b — verify before continuing.
STEPS
        read -r -p "press enter when the phone is in SDP mode: " _

        echo "==> running uuu…"
        sudo uuu "$SCRIPT"
        echo "==> done. Power-cycle the phone (battery out / in) to boot Marathon."
        ;;

    *)
        usage
        ;;
esac
