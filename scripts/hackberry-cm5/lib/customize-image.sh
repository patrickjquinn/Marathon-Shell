#!/usr/bin/env bash
# Customize a stock RaspiOS Lite arm64 image with Marathon Shell:
#
#   • Grow the rootfs partition (RaspiOS Lite is ~3GB, we need ~6GB
#     for Qt6 + WebEngine + marathon-shell build).
#   • systemd-nspawn into the rootfs:
#       - apt install Qt6 + build tools
#       - build marathon-shell from the bind-mounted source
#       - install greetd + the marathon Wayland session
#       - install plymouth + the Marathon boot splash theme
#   • Drop ZitaoTech's hackberrypi.dtbo overlay into /boot/firmware/
#     overlays/ (compiled INSIDE the chroot via the kernel-headers
#     package — host dtc can't preprocess #include <dt-bindings/…>).
#   • Append HyperPixel + KMS lines to /boot/firmware/config.txt under
#     an explicit `[all]` section header.
#   • Create the `pi` user since RaspiOS Bookworm Lite no longer ships
#     one by default.
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
LOOP=""
LD_PRELOAD_FILE=""

# Cleanup that always runs. If we masked /etc/ld.so.preload, restore it
# even if nspawn or the chroot script aborted mid-way.
cleanup() {
    set +e
    if [ -n "$LD_PRELOAD_FILE" ] && [ -f "$LD_PRELOAD_FILE.disabled" ]; then
        mv "$LD_PRELOAD_FILE.disabled" "$LD_PRELOAD_FILE"
    fi
    if mountpoint -q "$MNT/root/opt/Marathon-Shell-src" 2>/dev/null; then
        umount "$MNT/root/opt/Marathon-Shell-src" 2>/dev/null
    fi
    umount -R "$MNT/root" 2>/dev/null
    umount "$MNT/boot" 2>/dev/null
    if [ -n "$LOOP" ]; then
        losetup -d "$LOOP" 2>/dev/null
    fi
}
trap cleanup EXIT

# ── stage 3: grow rootfs ───────────────────────────────────────────────
echo "  ↳ growing image to ${GROW_TO}G"
CURRENT_BYTES=$(stat -c %s "$WORK_IMG")
TARGET_BYTES=$((GROW_TO * 1024 * 1024 * 1024))
if [ "$CURRENT_BYTES" -lt "$TARGET_BYTES" ]; then
    truncate -s "${GROW_TO}G" "$WORK_IMG"
fi

# Resize partition 2 to fill. Do this against the FILE (not the loop)
# to avoid the kernel-doesn't-re-read-the-partition-table trap that
# bites you when parted is given a loop device with held mounts.
parted -s "$WORK_IMG" resizepart 2 100%

# Now attach the loop device for filesystem operations.
LOOP=$(losetup -fP --show "$WORK_IMG")
echo "  ↳ loop device: $LOOP"

# Force the kernel to re-read the partition table on the loop, in case
# losetup didn't pick up the new size.
partx -u "$LOOP" 2>/dev/null || partprobe "$LOOP" 2>/dev/null || true
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

# Drop the customization script + plymouth theme into the chroot.
install -Dm755 "$(dirname "$0")/inside-chroot.sh" "$MNT/root/tmp/marathon-customize.sh"
mkdir -p "$MNT/root/tmp/marathon-plymouth/marathon"
cp -av "$SRC/shell/resources/plymouth/marathon/." "$MNT/root/tmp/marathon-plymouth/marathon/"

echo "  ↳ entering chroot to install + build (long stage)"
# --resolv-conf=copy-host makes apt update work on hosts with
#   systemd-resolved (where /etc/resolv.conf is a symlink to
#   /run/systemd/resolve/stub-resolv.conf — bind-ro would mount an
#   empty target).
# --bind=/dev/pts is implicit on modern nspawn; we pass --quiet to
#   suppress nspawn's own banner.
systemd-nspawn \
    --quiet \
    -D "$MNT/root" \
    --resolv-conf=copy-host \
    /tmp/marathon-customize.sh

# ── stage 5: hackberrypi.dtbo + config.txt overlays ────────────────────
# The .dts uses `#include <dt-bindings/gpio/gpio.h>` etc, which raw
# `dtc` can't preprocess. The chroot has linux-headers installed so we
# could compile it inside the nspawn — but it's simpler to just fetch
# the pre-built binary .dtbo from ZitaoTech's repo. They ship both.
echo "  ↳ fetching pre-built hackberrypi.dtbo from ZitaoTech"
HACKBERRYPI_DTBO="$BUILD_DIR/hackberrypi.dtbo"
if [ ! -f "$HACKBERRYPI_DTBO" ]; then
    # Pinned at the ZitaoTech repo's HEAD as of 2026-05-20. Their
    # `.dtbo` is the same compiled artifact RaspiOS users drop into
    # /boot/firmware/overlays/.
    DTBO_URL="https://github.com/ZitaoTech/HackberryPiCM5/raw/main/Operating%20System/hackberrypi.dtbo"
    curl -fL --retry 3 -o "$HACKBERRYPI_DTBO" "$DTBO_URL" || {
        echo "  ↳ pre-built .dtbo unavailable; trying source compile in chroot fallback"
        # The .dts uses kernel-tree headers (`#include <dt-bindings/...>`).
        # raspberrypi-kernel-headers ships those at
        # /usr/src/linux-headers-rpi-*/include — compile there.
        systemd-nspawn --quiet -D "$MNT/root" /bin/bash -c '
            set -e
            DTS_URL="https://raw.githubusercontent.com/ZitaoTech/HackberryPiCM5/main/Operating%20System/hackberrypi.dts"
            curl -fL --retry 3 -o /tmp/hackberrypi.dts "$DTS_URL"
            HEADERS=$(find /usr/src -maxdepth 1 -type d -name "linux-headers-*" | head -1)/include
            if [ -z "$HEADERS" ] || [ ! -d "$HEADERS" ]; then
                echo "no kernel-headers include dir found" >&2
                exit 1
            fi
            cpp -nostdinc -undef -x assembler-with-cpp -I "$HEADERS" \
                /tmp/hackberrypi.dts | \
                dtc -@ -I dts -O dtb -o /tmp/hackberrypi.dtbo -
            cp /tmp/hackberrypi.dtbo /tmp/marathon-plymouth/hackberrypi.dtbo
        '
        cp "$MNT/root/tmp/marathon-plymouth/hackberrypi.dtbo" "$HACKBERRYPI_DTBO"
    }
fi
install -Dm644 "$HACKBERRYPI_DTBO" "$MNT/boot/overlays/hackberrypi.dtbo"

echo "  ↳ appending Marathon block to /boot/firmware/config.txt"
CONFIG_TXT="$MNT/boot/config.txt"
if ! grep -q "^# Marathon Shell" "$CONFIG_TXT" 2>/dev/null; then
    # `[all]` section header so this applies on every Pi model. RaspiOS's
    # config.txt may end in a per-model section ([pi5], [cm4], …) and a
    # blind append would silently land in the wrong scope.
    cat >> "$CONFIG_TXT" <<'EOF'

[all]
# ─── Marathon Shell — HackberryPi CM5 ───────────────────────────────────
# Enable the v3d KMS driver (needed for OpenGL ES under Wayland).
dtoverlay=vc4-kms-v3d
# ZitaoTech's HackberryPi CM5 overlay (HyperPixel-style 720x720 DPI
# panel via RP1 + edt-ft5x06 touch + max17048 battery gauge). Built
# binary lives at /boot/firmware/overlays/hackberrypi.dtbo.
dtoverlay=hackberrypi
# GPU memory — 128M leaves plenty of room for KMS planes and QtWebEngine.
gpu_mem=128
# Disable bluetooth UART on GPIO 14/15 so we keep them free for the panel.
dtoverlay=disable-bt
EOF
fi

# ── cmdline.txt — quiet kernel boot, plymouth splash ───────────────────
# Drop the predictable plymouth/grub verbosity that RaspiOS ships. We
# enable `splash` because we DID install plymouth (inside-chroot.sh).
# `marathon=1` is a sentinel so an idempotent re-run can detect we
# already customized this cmdline.
CMDLINE_TXT="$MNT/boot/cmdline.txt"
if [ -f "$CMDLINE_TXT" ] && ! grep -q "marathon=1" "$CMDLINE_TXT"; then
    sed -i 's|$| logo.nologo vt.global_cursor_default=0 marathon=1|' "$CMDLINE_TXT"
fi

# Drop the trackpad udev rules (the HackberryPi-Q20 has a USB-HID
# trackpad that needs to be coerced into touchpad mode; CM5 ships the
# same shell-design Q20 keyboard family).
install -Dm644 "$SRC/scripts/99-hackberry.rules" "$MNT/root/etc/udev/rules.d/99-hackberry.rules"

# ── plymouth theme staged for marathon-shell-bin's PreSubmit hook ──────
# Already copied into the chroot at /tmp/marathon-plymouth/ above and
# installed into /usr/share/plymouth/themes/marathon/ by
# inside-chroot.sh's plymouth step.

# Restore ld.so.preload — also done in cleanup() trap; doing it here
# means a clean exit doesn't leave the customization-only state.
if [ -f "$LD_PRELOAD_FILE.disabled" ]; then
    mv "$LD_PRELOAD_FILE.disabled" "$LD_PRELOAD_FILE"
    LD_PRELOAD_FILE=""
fi

# ── tear-down ──────────────────────────────────────────────────────────
echo "  ↳ unmounting"
# umount -R handles the bind under /root/boot/firmware + the
# Marathon-Shell-src bind in correct nested order.
umount -R "$MNT/root"
umount "$MNT/boot"
losetup -d "$LOOP"
LOOP=""
trap - EXIT
echo "  ok"
