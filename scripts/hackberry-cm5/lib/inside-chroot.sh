#!/bin/bash
# Runs INSIDE the systemd-nspawn chroot of a RaspiOS Lite arm64 image.
# Installs Qt6 + Marathon's runtime deps, builds marathon-shell from
# the bind-mounted source at /opt/Marathon-Shell-src, configures
# LightDM autologin to launch Marathon as the Wayland session.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ── 1. apt: build-time + run-time deps ────────────────────────────────
echo "    [chroot] apt update"
apt-get -qq update

echo "    [chroot] installing build + runtime deps"
apt-get -qq install -y --no-install-recommends \
    build-essential cmake ninja-build pkg-config git \
    libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev libdrm-dev \
    libwayland-dev libxkbcommon-dev libinput-dev libudev-dev \
    libdbus-1-dev libpulse-dev libpipewire-0.3-dev \
    libssl-dev libsecret-1-dev \
    qt6-base-dev qt6-base-private-dev \
    qt6-declarative-dev qt6-declarative-private-dev \
    qt6-wayland qt6-wayland-dev qt6-wayland-private-dev \
    qt6-webengine-dev qt6-tools-dev qt6-tools-dev-tools \
    qt6-svg-dev qt6-multimedia-dev qt6-positioning-dev \
    qt6-shadertools-dev \
    qml6-module-qtquick qml6-module-qtquick-controls \
    qml6-module-qtquick-layouts qml6-module-qtquick-templates \
    qml6-module-qtquick-window qml6-module-qtquick-shapes \
    qml6-module-qtqml-workerscript qml6-module-qtwayland-compositor \
    lightdm lightdm-gtk-greeter \
    network-manager modemmanager upower bluez \
    pipewire pipewire-pulse wireplumber

# ── 2. build marathon-shell ───────────────────────────────────────────
echo "    [chroot] configuring marathon-shell"
SRC=/opt/Marathon-Shell-src
BUILD=/tmp/marathon-build
mkdir -p "$BUILD"
cd "$BUILD"
cmake "$SRC" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr

echo "    [chroot] building (parallel; this is the long step)"
ninja

echo "    [chroot] installing"
ninja install

# ── 3. session files ──────────────────────────────────────────────────
echo "    [chroot] installing session + LightDM configs"

install -Dm755 "$SRC/platforms/raspberry-pi/config/marathon-shell-session" \
    /usr/local/bin/marathon-shell-session

install -Dm644 "$SRC/platforms/raspberry-pi/config/marathon.desktop" \
    /usr/share/wayland-sessions/marathon.desktop

install -Dm644 "$SRC/platforms/raspberry-pi/config/lightdm.conf" \
    /etc/lightdm/lightdm.conf

# Permissions for backlight + render + video on the standard "pi" user.
usermod -aG video,render,input,plugdev pi || true

# ── 4. enable services ────────────────────────────────────────────────
echo "    [chroot] enabling lightdm + setting graphical default"
systemctl enable lightdm.service
systemctl set-default graphical.target

# Disable getty on tty1 — Marathon owns the framebuffer.
systemctl disable getty@tty1.service 2>/dev/null || true

# ── 5. trim build-time -dev packages ──────────────────────────────────
# Keep the runtime libs; remove headers + dev tools that aren't useful
# on the device and add ~1.5GB to the image.
echo "    [chroot] purging -dev packages to slim the image"
apt-get -qq purge -y \
    build-essential cmake ninja-build \
    'qt6-*-dev' 'qt6-*-private-dev' \
    'lib*-dev' 'lib*-private-dev' \
    qt6-shadertools-dev qt6-positioning-dev qt6-multimedia-dev \
    qt6-svg-dev qt6-tools-dev qt6-tools-dev-tools \
    git pkg-config || true
apt-get -qq autoremove -y
apt-get -qq clean
rm -rf /var/lib/apt/lists/* /tmp/marathon-build /root/.cache /root/.cmake

# ── 6. boot greeting (proves Marathon was installed) ───────────────────
cat > /etc/motd <<'EOF'

  Marathon Edition — HackberryPi CM5
  Built from this checkout. LightDM auto-logs in as "pi" and launches
  /usr/local/bin/marathon-shell-session under Wayland.

  Logs:    journalctl --user -u marathon-shell-session
           tail -f /tmp/marathon-shell.log

EOF

echo "    [chroot] customization complete"
