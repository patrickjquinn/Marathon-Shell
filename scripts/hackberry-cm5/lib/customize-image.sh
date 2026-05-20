#!/usr/bin/env bash
# Customize a stock RaspiOS Lite arm64 image with Marathon Shell.
#
# ROOTLESS via podman + libguestfs. The host needs only podman (which
# duranium already requires). The build runs entirely inside a
# rootless podman container that has guestfs-tools installed — the
# host kernel never touches loop devices, the host never needs sudo,
# the host never needs guestfs-tools installed.
#
# Sequence:
#   1. Grow the .img to ${GROW_TO}G via truncate + virt-resize
#      (inside container, rootless).
#   2. virt-customize (inside container) chains all apt-installs,
#      marathon-shell build, config drops, user creation, plymouth
#      theme install, and post-install package purges into a single
#      command pipe.
#   3. guestfish (inside container) appends the [all] config.txt
#      block + cmdline.txt sentinel idempotently.
set -euo pipefail

BUILD_DIR="${MARATHON_BUILD_DIR:?MARATHON_BUILD_DIR not set}"
SRC="${MARATHON_SHELL_SRC:?MARATHON_SHELL_SRC not set}"
GROW_TO="${GROW_TO:-6}"

WORK_IMG="$BUILD_DIR/work.img"
[ -f "$WORK_IMG" ] || { echo "missing $WORK_IMG (run stage 2 first)" >&2; exit 1; }

CONTAINERFILE="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")/Containerfile"
IMAGE_TAG="localhost/marathon-cm5-builder:latest"

# ── stage 3a: ensure builder container is present ─────────────────────
if ! podman image exists "$IMAGE_TAG"; then
    echo "  ↳ building marathon-cm5-builder container (one-time, ~3-5 min)"
    podman build -f "$CONTAINERFILE" -t "$IMAGE_TAG" "$(dirname "$CONTAINERFILE")"
else
    echo "  ↳ marathon-cm5-builder container cached ✓"
fi

# Helper that wraps every container invocation with the right mounts +
# kvm passthrough. SELinux: `:z` (lowercase) for shared label, avoids
# the relabel-permission errors that `:Z` triggers on Fedora hosts.
in_builder() {
    podman run --rm \
        --device /dev/kvm \
        -e LIBGUESTFS_BACKEND=direct \
        -e LIBGUESTFS_MEMSIZE=4096 \
        -v "$BUILD_DIR":/work:z \
        -v "$SRC":/marathon-src:z,ro \
        "$IMAGE_TAG" "$@"
}

# ── stage 3b: grow image to ${GROW_TO}G via virt-resize ───────────────
echo "  ↳ growing image to ${GROW_TO}G via virt-resize"
CURRENT_BYTES=$(stat -c %s "$WORK_IMG")
TARGET_BYTES=$((GROW_TO * 1024 * 1024 * 1024))
if [ "$CURRENT_BYTES" -lt "$TARGET_BYTES" ]; then
    # virt-resize wants separate input + output files. Stash the
    # original so a mid-flight failure doesn't force a re-download.
    mv -f "$WORK_IMG" "$BUILD_DIR/work.img.orig"
    truncate -s "${GROW_TO}G" "$WORK_IMG"
    in_builder -c "virt-resize --expand /dev/sda2 /work/work.img.orig /work/work.img"
    rm -f "$BUILD_DIR/work.img.orig"
fi

# ── stage 4: pre-stage payloads (dtbo + plymouth + source tarball) ─────
echo "  ↳ fetching pre-built hackberrypi.dtbo from ZitaoTech"
HACKBERRYPI_DTBO="$BUILD_DIR/hackberrypi.dtbo"
if [ ! -f "$HACKBERRYPI_DTBO" ]; then
    DTBO_URL="https://github.com/ZitaoTech/HackberryPiCM5/raw/main/Operating%20System/hackberrypi.dtbo"
    curl -fL --retry 3 -o "$HACKBERRYPI_DTBO" "$DTBO_URL"
fi

echo "  ↳ packing Marathon plymouth theme + Marathon-Shell source"
PLYMOUTH_TAR="$BUILD_DIR/marathon-plymouth.tar"
tar -C "$SRC/shell/resources/plymouth" -cf "$PLYMOUTH_TAR" marathon

SRC_TAR="$BUILD_DIR/marathon-shell-src.tar"
tar -C "$(dirname "$SRC")" \
    --exclude='Marathon-Shell/build' \
    --exclude='Marathon-Shell/.git' \
    --exclude='Marathon-Shell/.cache' \
    --exclude='Marathon-Shell/node_modules' \
    --exclude='Marathon-Shell/.claude' \
    -cf "$SRC_TAR" "$(basename "$SRC")"

# ── stage 5: virt-customize (the long stage, ~20-30 min) ──────────────
echo "  ↳ running virt-customize inside container (~20-30 min)"

# All payloads sit under $BUILD_DIR (mounted at /work) so the
# container's --upload paths resolve. The source tarball + plymouth
# tarball + dtbo are in /work; virt-customize uploads them into the
# image's filesystem, then --run-command pipes drive the rest.

in_builder -c "
set -euo pipefail
virt-customize -a /work/work.img \\
    --memsize 4096 \\
    --smp \$(nproc) \\
    --update \\
    --install build-essential,cmake,ninja-build,pkg-config,git,curl \\
    --install libgl1-mesa-dev,libegl1-mesa-dev,libgles2-mesa-dev,libdrm-dev \\
    --install libwayland-dev,libxkbcommon-dev,libinput-dev,libudev-dev \\
    --install libdbus-1-dev,libpulse-dev,libpipewire-0.3-dev \\
    --install libssl-dev,libsecret-1-dev \\
    --install qt6-base-dev,qt6-base-private-dev \\
    --install qt6-declarative-dev,qt6-declarative-private-dev \\
    --install qt6-wayland,qt6-wayland-dev \\
    --install qt6-webengine-dev,qt6-tools-dev \\
    --install qt6-svg-dev,qt6-multimedia-dev,qt6-shadertools-dev \\
    --install qml6-module-qtquick,qml6-module-qtquick-controls \\
    --install qml6-module-qtquick-layouts,qml6-module-qtquick-templates \\
    --install qml6-module-qtquick-window,qml6-module-qtquick-shapes \\
    --install qml6-module-qtqml-workerscript,qml6-module-qtwayland-compositor \\
    --install greetd,greetd-tuigreet \\
    --install plymouth,plymouth-themes \\
    --install network-manager,modemmanager,upower,bluez \\
    --install pipewire,pipewire-pulse,wireplumber \\
    --install libnotify-bin,sudo \\
    --upload /work/marathon-shell-src.tar:/tmp/marathon-shell-src.tar \\
    --upload /work/marathon-plymouth.tar:/tmp/marathon-plymouth.tar \\
    --upload /work/hackberrypi.dtbo:/boot/firmware/overlays/hackberrypi.dtbo \\
    --run-command 'tar -C /opt -xf /tmp/marathon-shell-src.tar && mv /opt/Marathon-Shell /opt/Marathon-Shell-src' \\
    --run-command 'mkdir -p /tmp/marathon-build && cd /tmp/marathon-build && cmake /opt/Marathon-Shell-src -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr' \\
    --run-command 'NCORES=\$(nproc); JOBS=\$(( NCORES > 4 ? 4 : (NCORES > 2 ? NCORES - 1 : 2) )); cd /tmp/marathon-build && ninja -j\"\$JOBS\"' \\
    --run-command 'cd /tmp/marathon-build && ninja install' \\
    --run-command 'install -Dm755 /opt/Marathon-Shell-src/platforms/raspberry-pi/config/marathon-shell-session /usr/local/bin/marathon-shell-session' \\
    --run-command 'install -Dm644 /opt/Marathon-Shell-src/platforms/raspberry-pi/config/marathon.desktop /usr/share/wayland-sessions/marathon.desktop' \\
    --run-command 'install -Dm644 /opt/Marathon-Shell-src/scripts/99-hackberry.rules /etc/udev/rules.d/99-hackberry.rules' \\
    --useradd pi --password 'pi:password:raspberry' \\
    --run-command 'usermod -aG video,render,input,plugdev,sudo,netdev,dialout,audio,bluetooth pi' \\
    --run-command 'rm -f /etc/xdg/autostart/piwiz.desktop /usr/lib/userconf-pi/userconf /etc/profile.d/userconfig.sh' \\
    --run-command 'systemctl disable userconfig.service 2>/dev/null || true' \\
    --run-command 'rm -f /lib/systemd/system/userconfig.service' \\
    --run-command 'mkdir -p /etc/greetd && printf \"[terminal]\\nvt = 1\\n\\n[default_session]\\ncommand = \\\"/usr/local/bin/marathon-shell-session\\\"\\nuser = \\\"pi\\\"\\n\" > /etc/greetd/config.toml' \\
    --run-command 'systemctl disable lightdm.service 2>/dev/null || true' \\
    --run-command 'systemctl mask lightdm.service 2>/dev/null || true' \\
    --run-command 'systemctl enable greetd.service' \\
    --run-command 'systemctl set-default graphical.target' \\
    --run-command 'systemctl disable getty@tty1.service 2>/dev/null || true' \\
    --run-command 'mkdir -p /usr/share/plymouth/themes && tar -C /usr/share/plymouth/themes -xf /tmp/marathon-plymouth.tar' \\
    --run-command 'plymouth-set-default-theme -R marathon || ln -sf /usr/share/plymouth/themes/marathon/marathon.plymouth /etc/alternatives/default.plymouth' \\
    --run-command 'apt-get purge -y build-essential cmake ninja-build qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev qt6-wayland-dev qt6-webengine-dev qt6-tools-dev qt6-svg-dev qt6-multimedia-dev qt6-shadertools-dev libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev libdrm-dev libwayland-dev libxkbcommon-dev libinput-dev libudev-dev libdbus-1-dev libpulse-dev libpipewire-0.3-dev libssl-dev libsecret-1-dev git pkg-config curl || true' \\
    --run-command 'apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/marathon-build /tmp/marathon-shell-src.tar /tmp/marathon-plymouth.tar /opt/Marathon-Shell-src /root/.cache /root/.cmake'
"

# ── stage 6: config.txt + cmdline.txt edits via guestfish ─────────────
echo "  ↳ appending [all] block to /boot/firmware/config.txt"
in_builder -c "guestfish --rw -a /work/work.img -i <<'GFISH'
sh \"grep -q '# Marathon Shell' /boot/firmware/config.txt || cat >> /boot/firmware/config.txt << 'EOF'

[all]
# ─── Marathon Shell — HackberryPi CM5 ───────────────────────────────────
dtoverlay=vc4-kms-v3d
dtoverlay=hackberrypi
gpu_mem=128
dtoverlay=disable-bt
EOF\"
sh \"grep -q 'marathon=1' /boot/firmware/cmdline.txt || sed -i 's|\\\$| quiet splash logo.nologo vt.global_cursor_default=0 marathon=1|' /boot/firmware/cmdline.txt\"
GFISH
"

# Clean up the staged tarballs.
rm -f "$SRC_TAR" "$PLYMOUTH_TAR"

echo "  ok"
