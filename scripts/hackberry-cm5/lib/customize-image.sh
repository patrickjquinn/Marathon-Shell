#!/usr/bin/env bash
# Customize a stock RaspiOS Lite arm64 image with Marathon Shell.
# Runs ENTIRELY ROOTLESS via libguestfs (`virt-customize` + `virt-resize`
# + `guestfish`). These tools spin up a tiny Linux VM inside QEMU to
# mount and modify the .img — the host kernel never touches loop
# devices or nspawn, so no sudo is needed.
#
# Sequence:
#   1. Grow the work.img to ${GROW_TO}G with `truncate`.
#   2. `virt-resize --expand /dev/sda2` extends partition 2 + the
#      filesystem in one shot.
#   3. `virt-customize` to apt-install Qt6, build marathon-shell from
#      the bind-mounted source, install greetd + the marathon Wayland
#      session, install plymouth + the Marathon boot splash theme,
#      create the `pi` user (Bookworm Lite no longer ships one).
#   4. Compile + copy in ZitaoTech's hackberrypi.dtbo overlay (rootless
#      via host `dtc`, no kernel headers needed — we download the
#      pre-built .dtbo from ZitaoTech's repo).
#   5. Append HyperPixel + KMS lines to /boot/firmware/config.txt
#      under an explicit `[all]` section header via `guestfish edit`.
set -euo pipefail

BUILD_DIR="${MARATHON_BUILD_DIR:?MARATHON_BUILD_DIR not set}"
SRC="${MARATHON_SHELL_SRC:?MARATHON_SHELL_SRC not set}"
GROW_TO="${GROW_TO:-6}"

WORK_IMG="$BUILD_DIR/work.img"
[ -f "$WORK_IMG" ] || { echo "missing $WORK_IMG (run stage 2 first)" >&2; exit 1; }

# ── stage 3: grow image to ${GROW_TO}G ────────────────────────────────
echo "  ↳ growing image to ${GROW_TO}G via virt-resize (rootless)"
CURRENT_BYTES=$(stat -c %s "$WORK_IMG")
TARGET_BYTES=$((GROW_TO * 1024 * 1024 * 1024))
if [ "$CURRENT_BYTES" -lt "$TARGET_BYTES" ]; then
    # virt-resize wants a SEPARATE output file at the new size. Keep
    # the original as work.img.orig in case we need to retry without
    # re-downloading RaspiOS.
    ORIG="$BUILD_DIR/work.img.orig"
    mv -f "$WORK_IMG" "$ORIG"
    truncate -s "${GROW_TO}G" "$WORK_IMG"
    # Force kernel hint off — virt-resize manages partition layout
    # itself. --expand picks the largest partition; on RaspiOS Lite
    # that's partition 2 (ext4 rootfs).
    virt-resize --expand /dev/sda2 "$ORIG" "$WORK_IMG"
    rm -f "$ORIG"
fi

# ── stage 4: ZitaoTech hackberrypi.dtbo ───────────────────────────────
# Fetch the pre-built .dtbo from upstream rather than compiling the
# .dts on the host (the .dts uses `#include <dt-bindings/...>` which
# raw `dtc` can't preprocess without kernel-tree headers).
echo "  ↳ fetching pre-built hackberrypi.dtbo from ZitaoTech"
HACKBERRYPI_DTBO="$BUILD_DIR/hackberrypi.dtbo"
if [ ! -f "$HACKBERRYPI_DTBO" ]; then
    DTBO_URL="https://github.com/ZitaoTech/HackberryPiCM5/raw/main/Operating%20System/hackberrypi.dtbo"
    curl -fL --retry 3 -o "$HACKBERRYPI_DTBO" "$DTBO_URL"
fi

# ── stage 5: assemble the plymouth theme tarball for in-VM copy-in ────
echo "  ↳ packing Marathon plymouth theme + Marathon-Shell source"
PLYMOUTH_TAR="$BUILD_DIR/marathon-plymouth.tar"
tar -C "$SRC/shell/resources/plymouth" -cf "$PLYMOUTH_TAR" marathon

# Tarball the source so we can copy-in a single artifact instead of
# bind-mounting (virt-customize's --copy-in walks a directory but is
# slow for tens-of-thousands of files; tar is faster).
SRC_TAR="$BUILD_DIR/marathon-shell-src.tar"
# Pack from the parent dir so the archive contains a top-level
# `Marathon-Shell/` directory.
tar -C "$(dirname "$SRC")" \
    --exclude='Marathon-Shell/build' \
    --exclude='Marathon-Shell/.git' \
    --exclude='Marathon-Shell/.cache' \
    --exclude='Marathon-Shell/node_modules' \
    --exclude='Marathon-Shell/.claude' \
    -cf "$SRC_TAR" "$(basename "$SRC")"

# ── stage 6: virt-customize — the long stage ──────────────────────────
# Two ENV vars matter for guestfs:
#   LIBGUESTFS_BACKEND=direct  → bypass libvirt; just run a private
#                                qemu, simpler + faster.
#   LIBGUESTFS_MEMSIZE=4096    → give the helper VM 4G RAM; default of
#                                768M is too small for apt-installing
#                                qt6-webengine + the marathon build.
export LIBGUESTFS_BACKEND=direct
export LIBGUESTFS_MEMSIZE=4096

echo "  ↳ running virt-customize (rootless; ~20-30 min)"

virt-customize -a "$WORK_IMG" \
    --memsize 4096 \
    --smp "$(nproc)" \
    --update \
    --install build-essential,cmake,ninja-build,pkg-config,git,curl \
    --install libgl1-mesa-dev,libegl1-mesa-dev,libgles2-mesa-dev,libdrm-dev \
    --install libwayland-dev,libxkbcommon-dev,libinput-dev,libudev-dev \
    --install libdbus-1-dev,libpulse-dev,libpipewire-0.3-dev \
    --install libssl-dev,libsecret-1-dev \
    --install qt6-base-dev,qt6-base-private-dev \
    --install qt6-declarative-dev,qt6-declarative-private-dev \
    --install qt6-wayland,qt6-wayland-dev \
    --install qt6-webengine-dev,qt6-tools-dev \
    --install qt6-svg-dev,qt6-multimedia-dev,qt6-shadertools-dev \
    --install qml6-module-qtquick,qml6-module-qtquick-controls \
    --install qml6-module-qtquick-layouts,qml6-module-qtquick-templates \
    --install qml6-module-qtquick-window,qml6-module-qtquick-shapes \
    --install qml6-module-qtqml-workerscript,qml6-module-qtwayland-compositor \
    --install greetd,greetd-tuigreet \
    --install plymouth,plymouth-themes \
    --install network-manager,modemmanager,upower,bluez \
    --install pipewire,pipewire-pulse,wireplumber \
    --install libnotify-bin,sudo \
    --upload "$SRC_TAR":/tmp/marathon-shell-src.tar \
    --upload "$PLYMOUTH_TAR":/tmp/marathon-plymouth.tar \
    --upload "$HACKBERRYPI_DTBO":/boot/firmware/overlays/hackberrypi.dtbo \
    --run-command 'tar -C /opt -xf /tmp/marathon-shell-src.tar && mv /opt/Marathon-Shell /opt/Marathon-Shell-src' \
    --run-command 'mkdir -p /tmp/marathon-build && cd /tmp/marathon-build && cmake /opt/Marathon-Shell-src -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr' \
    --run-command 'NCORES=$(nproc); JOBS=$(( NCORES > 4 ? 4 : (NCORES > 2 ? NCORES - 1 : 2) )); cd /tmp/marathon-build && ninja -j"$JOBS"' \
    --run-command 'cd /tmp/marathon-build && ninja install' \
    --run-command 'install -Dm755 /opt/Marathon-Shell-src/platforms/raspberry-pi/config/marathon-shell-session /usr/local/bin/marathon-shell-session' \
    --run-command 'install -Dm644 /opt/Marathon-Shell-src/platforms/raspberry-pi/config/marathon.desktop /usr/share/wayland-sessions/marathon.desktop' \
    --run-command 'install -Dm644 /opt/Marathon-Shell-src/scripts/99-hackberry.rules /etc/udev/rules.d/99-hackberry.rules' \
    --useradd pi --password 'pi:password:raspberry' \
    --run-command 'usermod -aG video,render,input,plugdev,sudo,netdev,dialout,audio,bluetooth pi' \
    --run-command 'rm -f /etc/xdg/autostart/piwiz.desktop /usr/lib/userconf-pi/userconf /etc/profile.d/userconfig.sh' \
    --run-command 'systemctl disable userconfig.service 2>/dev/null || true' \
    --run-command 'rm -f /lib/systemd/system/userconfig.service' \
    --run-command 'mkdir -p /etc/greetd && printf "[terminal]\nvt = 1\n\n[default_session]\ncommand = \"/usr/local/bin/marathon-shell-session\"\nuser = \"pi\"\n" > /etc/greetd/config.toml' \
    --run-command 'systemctl disable lightdm.service 2>/dev/null || true' \
    --run-command 'systemctl mask lightdm.service 2>/dev/null || true' \
    --run-command 'systemctl enable greetd.service' \
    --run-command 'systemctl set-default graphical.target' \
    --run-command 'systemctl disable getty@tty1.service 2>/dev/null || true' \
    --run-command 'mkdir -p /usr/share/plymouth/themes && tar -C /usr/share/plymouth/themes -xf /tmp/marathon-plymouth.tar' \
    --run-command 'plymouth-set-default-theme -R marathon || ln -sf /usr/share/plymouth/themes/marathon/marathon.plymouth /etc/alternatives/default.plymouth' \
    --run-command 'apt-get purge -y build-essential cmake ninja-build qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev qt6-wayland-dev qt6-webengine-dev qt6-tools-dev qt6-svg-dev qt6-multimedia-dev qt6-shadertools-dev libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev libdrm-dev libwayland-dev libxkbcommon-dev libinput-dev libudev-dev libdbus-1-dev libpulse-dev libpipewire-0.3-dev libssl-dev libsecret-1-dev git pkg-config curl || true' \
    --run-command 'apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/marathon-build /tmp/marathon-shell-src.tar /tmp/marathon-plymouth.tar /opt/Marathon-Shell-src /root/.cache /root/.cmake' \
    --write '/etc/motd:

  Marathon Edition — HackberryPi CM5
  Built rootlessly via virt-customize. greetd auto-logs in as "pi"
  and launches /usr/local/bin/marathon-shell-session under Wayland.

  Default password: raspberry  (CHANGE THIS — passwd)
  Logs:
    sudo journalctl -u greetd --since '"'"'5 minutes ago'"'"'
    tail -f /tmp/marathon-shell.log

'

# ── stage 7: config.txt overlays via guestfish ────────────────────────
echo "  ↳ appending [all] block to /boot/firmware/config.txt"
guestfish --rw -a "$WORK_IMG" -i <<'GFISH'
# Append the Marathon block under an explicit [all] header. Only if
# we haven't already (idempotent — re-runs of customize-image.sh
# won't double-stamp).
sh "grep -q '# Marathon Shell' /boot/firmware/config.txt || cat >> /boot/firmware/config.txt << 'EOF'

[all]
# ─── Marathon Shell — HackberryPi CM5 ───────────────────────────────────
dtoverlay=vc4-kms-v3d
dtoverlay=hackberrypi
gpu_mem=128
dtoverlay=disable-bt
EOF"

# Marathon sentinel + quieter kernel — `splash` is enabled because
# plymouth is now installed.
sh "grep -q 'marathon=1' /boot/firmware/cmdline.txt || sed -i 's|$| quiet splash logo.nologo vt.global_cursor_default=0 marathon=1|' /boot/firmware/cmdline.txt"
GFISH

# Clean up the staged tarballs from the host build dir.
rm -f "$SRC_TAR" "$PLYMOUTH_TAR"

echo "  ok"
