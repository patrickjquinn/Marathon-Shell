#!/usr/bin/env bash
# Customize a stock RaspiOS Lite arm64 image with Marathon Shell:
#
#   • Grow the rootfs partition (RaspiOS Lite is ~3GB, we need ~6GB
#     for Qt6 + WebEngine + marathon-shell build).
#   • systemd-nspawn into the rootfs:
#       - apt install Qt6 + build tools
#       - build marathon-shell from the bind-mounted source
#       - install LightDM + the marathon Wayland session files from
#         platforms/raspberry-pi/config/
#       - enable lightdm.service + autologin as user "pi"
#   • Drop ZitaoTech's hackberrypi.dtbo overlay into /boot/firmware/
#     overlays/ (compiled from .dts via dtc), append the dtoverlay
#     lines to /boot/firmware/config.txt.
#   • Trim apt build-time -dev packages from the final image so it
#     stays under ~5GB.
#
# Runs as root (mounts loop device, runs systemd-nspawn). The
# orchestrator wraps this with `sudo`.
set -euo pipefail

BUILD_DIR="${MARATHON_BUILD_DIR:?MARATHON_BUILD_DIR not set}"
SRC="${MARATHON_SHELL_SRC:?MARATHON_SHELL_SRC not set}"
GROW_TO="${GROW_TO:-6}"

WORK_IMG="$BUILD_DIR/work.img"
[ -f "$WORK_IMG" ] || { echo "missing $WORK_IMG (run stage 2 first)" >&2; exit 1; }

MNT="$BUILD_DIR/mnt"
mkdir -p "$MNT/root" "$MNT/boot"

# ── stage 3: grow rootfs ───────────────────────────────────────────────
echo "  ↳ growing image to ${GROW_TO}G"
CURRENT_BYTES=$(stat -c %s "$WORK_IMG")
TARGET_BYTES=$((GROW_TO * 1024 * 1024 * 1024))
if [ "$CURRENT_BYTES" -lt "$TARGET_BYTES" ]; then
    truncate -s "${GROW_TO}G" "$WORK_IMG"
fi

LOOP=$(losetup -fP --show "$WORK_IMG")
trap 'umount -R "$MNT/root" "$MNT/boot" 2>/dev/null || true; losetup -d "$LOOP" 2>/dev/null || true' EXIT
echo "  ↳ loop device: $LOOP"

# Resize partition 2 (rootfs) to fill the new space.
parted -s "$LOOP" resizepart 2 100%
partprobe "$LOOP" || true
sleep 1
e2fsck -fy "${LOOP}p2" || true
resize2fs "${LOOP}p2"

# ── stage 4: mount + nspawn customization ──────────────────────────────
mount "${LOOP}p2" "$MNT/root"
mount "${LOOP}p1" "$MNT/boot"
mkdir -p "$MNT/root/boot/firmware"
mount --bind "$MNT/boot" "$MNT/root/boot/firmware"

# RaspiOS ships /etc/ld.so.preload with the libarmmem-${ARCH}.so on
# the first line. systemd-nspawn fails because that .so isn't there
# on the host; mask it for the duration of the chroot.
LD_PRELOAD_FILE="$MNT/root/etc/ld.so.preload"
if [ -f "$LD_PRELOAD_FILE" ]; then
    mv "$LD_PRELOAD_FILE" "$LD_PRELOAD_FILE.disabled"
fi

# Bind-mount our Marathon-Shell source into /opt/Marathon-Shell-src
# inside the chroot. The build runs there, output goes into /usr.
mkdir -p "$MNT/root/opt/Marathon-Shell-src"
mount --bind "$SRC" "$MNT/root/opt/Marathon-Shell-src"

# Drop the customization script into the chroot.
install -Dm755 "$(dirname "$0")/inside-chroot.sh" "$MNT/root/tmp/marathon-customize.sh"

echo "  ↳ entering chroot to install + build (long stage)"
systemd-nspawn -D "$MNT/root" --bind-ro=/etc/resolv.conf /tmp/marathon-customize.sh

# ── stage 5: hackberrypi.dtbo + config.txt overlays ────────────────────
echo "  ↳ compiling hackberrypi.dtbo from ZitaoTech .dts"
HACKBERRYPI_DTS="$BUILD_DIR/hackberrypi.dts"
HACKBERRYPI_DTBO="$BUILD_DIR/hackberrypi.dtbo"
if [ ! -f "$HACKBERRYPI_DTS" ]; then
    # Pinned at the ZitaoTech repo's HEAD as of 2026-05-20. If the
    # upstream moves we'll need to bump the URL; the .dts is small
    # and stable.
    DTS_URL="https://raw.githubusercontent.com/ZitaoTech/HackberryPiCM5/main/Operating%20System/hackberrypi.dts"
    curl -fL --retry 3 -o "$HACKBERRYPI_DTS" "$DTS_URL"
fi
dtc -@ -I dts -O dtb -o "$HACKBERRYPI_DTBO" "$HACKBERRYPI_DTS"
install -Dm644 "$HACKBERRYPI_DTBO" "$MNT/boot/overlays/hackberrypi.dtbo"

echo "  ↳ appending Marathon block to /boot/firmware/config.txt"
CONFIG_TXT="$MNT/boot/config.txt"
if ! grep -q "^# Marathon Shell" "$CONFIG_TXT" 2>/dev/null; then
    cat >> "$CONFIG_TXT" <<'EOF'

# ─── Marathon Shell — HackberryPi CM5 ───────────────────────────────────
# Enable the v3d KMS driver (needed for OpenGL ES under Wayland).
dtoverlay=vc4-kms-v3d
# ZitaoTech's HackberryPi CM5 overlay (HyperPixel 4.0 Square 720x720
# DPI panel via RP1 + edt-ft5x06 touch + max17048 battery gauge).
# Compiled from hackberrypi.dts and dropped into /boot/firmware/overlays/.
dtoverlay=hackberrypi
# GPU memory — 128M leaves plenty of room for KMS planes and QtWebEngine.
gpu_mem=128
# Disable boot-time rainbow splash (gets in the way of Marathon's boot logo).
disable_splash=1
# Disable bluetooth UART on GPIO 14/15 so we keep them free for the
# panel.
dtoverlay=disable-bt
EOF
fi

# cmdline.txt — quiet kernel boot, drop the predictable plymouth/grub
# verbosity that RaspiOS ships.
CMDLINE_TXT="$MNT/boot/cmdline.txt"
if [ -f "$CMDLINE_TXT" ] && ! grep -q "marathon=1" "$CMDLINE_TXT"; then
    # Append quiet flag without breaking the single-line format Pi
    # firmware requires.
    sed -i 's|$| quiet splash logo.nologo vt.global_cursor_default=0 marathon=1|' "$CMDLINE_TXT"
fi

# Drop the trackpad udev rules (the HackberryPi-Q20 has a USB-HID
# trackpad that needs to be coerced into touchpad mode; CM5 ships the
# same shell-design Q20 keyboard).
install -Dm644 "$SRC/scripts/99-hackberry.rules" "$MNT/root/etc/udev/rules.d/99-hackberry.rules"

# Restore ld.so.preload.
if [ -f "$LD_PRELOAD_FILE.disabled" ]; then
    mv "$LD_PRELOAD_FILE.disabled" "$LD_PRELOAD_FILE"
fi

# ── tear-down ──────────────────────────────────────────────────────────
echo "  ↳ unmounting"
umount "$MNT/root/opt/Marathon-Shell-src"
umount "$MNT/root/boot/firmware"
umount "$MNT/boot"
umount "$MNT/root"
losetup -d "$LOOP"
trap - EXIT
echo "  ok"
