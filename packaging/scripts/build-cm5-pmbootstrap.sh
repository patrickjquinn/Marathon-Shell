#!/bin/bash
# Build a bootable Marathon SD image for HackberryPi CM5 (Pi 5) using
# pmbootstrap + upstream pmaports + systemd-edge.
#
# This is the CANONICAL path that boots on real CM5 hardware. duranium/mkosi
# does NOT boot on Pi 5 — its UKI/erofs/verity/GPT architecture is wrong
# for Pi-firmware boot. Use this script.
#
# Three hard-won bug fixes baked in:
#   1. linux-rpi pinned to 6.12.85-r0 (Alpine v3.23/main/aarch64).
#      Alpine edge's 6.18.35-r0 has a NULL-pointer-deref in
#      __mod_node_page_state() during udev init in initrd on Pi 5 /
#      CM5 hardware (raspberrypi/linux#7196). Boot stays blank.
#   2. config.txt rewritten via device-overlay post-install to use
#      auto_initramfs=1 + Pi-OS-Lite display knobs. Stock pmaports
#      ships `initramfs initramfs-rpi` directive but mkinitfs writes
#      /boot/initramfs (no suffix). Pi BootROM aborts on missing file.
#   3. After install, boot-partition patch copies kernel_2712.img +
#      initramfs_2712 (Pi 5 EEPROM defaults) alongside the original
#      filenames, since the in-chroot post-install runs BEFORE
#      mkinitfs writes the final initramfs.
#
# Prereqs:
#   - pmbootstrap installed and `pmbootstrap init` already run with
#     device=raspberry-pi5, ui=marathon, systemd=always
#   - pmaports clone at ~/pmaports-upstream (gitlab.postmarketos.org)
#   - this repo at ~/Developer/Marathon-Shell
#   - SUDO_ASKPASS=/tmp/askpass.sh (or polkit/sudo configured)
#   - SD card at /dev/sda (verify with lsblk before running)

set -euo pipefail

PMAPORTS="${PMAPORTS:-$HOME/pmaports-upstream}"
MARATHON_PKGS="${MARATHON_PKGS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages}"
DURANIUM_PKGS="${DURANIUM_PKGS:-$HOME/duranium-build/duranium/mkosi.packages}"
SD_DEV="${SD_DEV:-/dev/sda}"
PIN_LINUX_RPI_APK="linux-rpi-6.12.85-r0.apk"

# ─── 1. Verify prereqs ────────────────────────────────────────────────────
[ -d "$PMAPORTS" ] || { echo "ERROR: $PMAPORTS missing — git clone gitlab.postmarketos.org/postmarketOS/pmaports.git" >&2; exit 1; }
[ -d "$MARATHON_PKGS" ] || { echo "ERROR: $MARATHON_PKGS missing" >&2; exit 1; }
which pmbootstrap >/dev/null || { echo "ERROR: pmbootstrap not in PATH" >&2; exit 1; }

# ─── 2. Vendor Marathon packages into pmaports ────────────────────────────
echo "+ vendoring Marathon packages into $PMAPORTS"
mkdir -p "$PMAPORTS/main" "$PMAPORTS/device/community"
cp -r "$MARATHON_PKGS/device-raspberry-pi5-marathon" "$PMAPORTS/device/community/"
for p in marathon-base-config marathon-shell marathon-plymouth-theme marathon-boot-logo postmarketos-ui-marathon marathon-mail-oauth qmf; do
    cp -r "$MARATHON_PKGS/$p" "$PMAPORTS/main/"
done

# ─── 3. Drop pinned linux-rpi 6.12.85 into the local edge repo ────────────
echo "+ pinning linux-rpi to 6.12.85-r0"
PKGS_EDGE="$(pmbootstrap config work)/packages/edge/aarch64"
[ -f "$DURANIUM_PKGS/$PIN_LINUX_RPI_APK" ] && \
    sudo cp "$DURANIUM_PKGS/$PIN_LINUX_RPI_APK" "$PKGS_EDGE/" || true
sudo cp "$DURANIUM_PKGS/linux-rpi-dev-6.12.85-r0.apk" "$PKGS_EDGE/" 2>/dev/null || true

# Patch the marathon-overlay APKBUILD to PIN linux-rpi.
sed -i 's|^depends="$|depends="\n\tlinux-rpi=6.12.85-r0|' \
    "$PMAPORTS/device/community/device-raspberry-pi5-marathon/APKBUILD"

# ─── 4. Patch device-raspberry-pi5-marathon post-install to fix config.txt ─
cat > "$PMAPORTS/device/community/device-raspberry-pi5-marathon/device-raspberry-pi5-marathon.post-install" <<'POSTINST'
#!/bin/sh

# Pi 5 BootROM reads /boot/config.txt's `initramfs <filename>` directive.
# raspberrypi-bootloader ships `initramfs initramfs-rpi` but mkinitfs
# writes to /boot/initramfs (no suffix). Mismatch → BootROM fails to
# load initramfs → blank screen.
if [ -d /boot ]; then
    [ -f /boot/initramfs ] && [ ! -e /boot/initramfs-rpi ] && \
        ln -sf initramfs /boot/initramfs-rpi
    cat > /boot/config.txt <<'EOF'
auto_initramfs=1
arm_64bit=1
arm_boost=1
disable_fw_kms_setup=1
display_auto_detect=1
max_framebuffers=2
include usercfg.txt
EOF
fi

ln -sf marathon-config.toml /etc/greetd/config.toml
systemctl enable greetd NetworkManager upower pipewire pipewire-pulse wireplumber
systemctl enable ModemManager iwd bluetooth 2>/dev/null || true
systemctl disable lightdm.service 2>/dev/null || true
systemctl mask    lightdm.service 2>/dev/null || true
systemctl set-default graphical.target 2>/dev/null || true
systemctl disable getty@tty1.service 2>/dev/null || true
exit 0
POSTINST
chmod +x "$PMAPORTS/device/community/device-raspberry-pi5-marathon/device-raspberry-pi5-marathon.post-install"

# ─── 5. Regenerate checksums + index ──────────────────────────────────────
echo "+ regenerating checksums"
for p in marathon-base-config marathon-shell marathon-plymouth-theme marathon-boot-logo postmarketos-ui-marathon marathon-mail-oauth qmf device-raspberry-pi5-marathon; do
    pmbootstrap checksum "$p" 2>&1 | tail -1
done
pmbootstrap index 2>&1 | tail -1

# ─── 6. Install ───────────────────────────────────────────────────────────
echo "+ pmbootstrap install (this may take a while)"
pmbootstrap install --zap --add device-raspberry-pi5-marathon --password "${ROOT_PASSWORD:-027602}"

# ─── 7. Boot-partition patch: Pi 5 default filenames ──────────────────────
# The in-chroot post-install runs before mkinitfs's final pass, so
# `kernel_2712.img` + `initramfs_2712` (Pi 5 EEPROM defaults) need to be
# copied AFTER. Loop-mount and patch the built image.
IMG="$(pmbootstrap config work)/chroot_native/home/pmos/rootfs/raspberry-pi5.img"
[ -f "$IMG" ] || { echo "ERROR: built image not at $IMG" >&2; exit 1; }
LOOP=$(sudo losetup -P -f --show "$IMG")
sudo mkdir -p /tmp/cm5boot
sudo mount "${LOOP}p1" /tmp/cm5boot
sudo cp /tmp/cm5boot/vmlinuz-rpi /tmp/cm5boot/kernel_2712.img
sudo cp /tmp/cm5boot/initramfs /tmp/cm5boot/initramfs_2712
sudo sync
sudo umount /tmp/cm5boot
sudo losetup -d "$LOOP"

# ─── 8. Flash ─────────────────────────────────────────────────────────────
if [ "${SKIP_FLASH:-0}" = "1" ]; then
    echo "SKIP_FLASH=1 — image at $IMG, not flashing"
    exit 0
fi
echo "+ flashing $IMG -> $SD_DEV (will dd ~4 GB)"
sudo umount "${SD_DEV}"* 2>/dev/null || true
sudo dd if="$IMG" of="$SD_DEV" bs=4M conv=fsync status=progress
sudo sync
echo "DONE — pop SD into CM5"
