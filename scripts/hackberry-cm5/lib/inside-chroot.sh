#!/bin/bash
# Runs INSIDE the systemd-nspawn chroot of a RaspiOS Lite arm64 image.
#
# Responsibilities:
#   1. apt install Qt6 + Marathon's runtime deps (only packages that
#      ACTUALLY exist in Bookworm — vetted against the apt cache).
#   2. Build marathon-shell from /opt/Marathon-Shell-src (cap parallel
#      jobs to avoid OOM on hosts with <16 GB).
#   3. Create the `pi` user (Bookworm Lite doesn't ship one anymore)
#      with the standard groups + a default password.
#   4. Configure greetd to auto-login `pi` and launch marathon-shell as
#      the Wayland session. Greetd is lighter than RaspiOS's lightdm,
#      doesn't grab /dev/dri/card0 the way lightdm-gtk-greeter does,
#      and matches the duranium-on-phone session model.
#   5. Install plymouth + the Marathon boot splash theme.
#   6. Trim build-time -dev packages.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ── 1. apt: build-time + run-time deps ────────────────────────────────
echo "    [chroot] apt update"
apt-get -qq update

# Package list vetted against Bookworm: dropped qt6-tools-dev-tools and
# qt6-positioning-dev (neither in Bookworm main). qml6-module-qtwayland-
# compositor stays as it IS in Bookworm.
echo "    [chroot] installing build + runtime deps"
apt-get -qq install -y --no-install-recommends \
    build-essential cmake ninja-build pkg-config git curl \
    libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev libdrm-dev \
    libwayland-dev libxkbcommon-dev libinput-dev libudev-dev \
    libdbus-1-dev libpulse-dev libpipewire-0.3-dev \
    libssl-dev libsecret-1-dev \
    qt6-base-dev qt6-base-private-dev \
    qt6-declarative-dev qt6-declarative-private-dev \
    qt6-wayland qt6-wayland-dev \
    qt6-webengine-dev qt6-tools-dev \
    qt6-svg-dev qt6-multimedia-dev qt6-shadertools-dev \
    qml6-module-qtquick qml6-module-qtquick-controls \
    qml6-module-qtquick-layouts qml6-module-qtquick-templates \
    qml6-module-qtquick-window qml6-module-qtquick-shapes \
    qml6-module-qtqml-workerscript qml6-module-qtwayland-compositor \
    greetd greetd-tuigreet \
    plymouth plymouth-themes \
    network-manager modemmanager upower bluez \
    pipewire pipewire-pulse wireplumber \
    libnotify-bin sudo

# ── 2. build marathon-shell ───────────────────────────────────────────
echo "    [chroot] configuring marathon-shell"
SRC=/opt/Marathon-Shell-src
BUILD=/tmp/marathon-build
mkdir -p "$BUILD"
cd "$BUILD"
cmake "$SRC" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr

# Cap parallelism to avoid OOM on hosts with limited RAM. WebEngine
# link can use ~4-6 GB per object; on a 16 GB host with 4 jobs we have
# headroom. nproc-2 is a reasonable upper bound; floor at 2 jobs.
NCORES=$(nproc)
JOBS=$(( NCORES > 4 ? 4 : (NCORES > 2 ? NCORES - 1 : 2) ))
echo "    [chroot] building (-j$JOBS — capped for OOM safety on lower-RAM hosts)"
ninja -j"$JOBS"

echo "    [chroot] installing"
ninja install

# ── 3. create the `pi` user (Bookworm Lite no longer ships one) ───────
echo "    [chroot] creating user 'pi'"
if ! id pi >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G video,render,input,plugdev,sudo,netdev,dialout,audio,bluetooth pi
    echo 'pi:raspberry' | chpasswd
else
    # User exists (e.g. on re-customization) — just normalize the groups.
    usermod -aG video,render,input,plugdev,sudo,netdev,dialout,audio,bluetooth pi
fi

# Disable RaspiOS's first-run wizard that would normally create the
# user interactively + force a password change.
rm -f /etc/xdg/autostart/piwiz.desktop /usr/lib/userconf-pi/userconf 2>/dev/null || true
rm -f /etc/profile.d/userconfig.sh 2>/dev/null || true
# Stop the firstrun systemd unit that re-runs userconf on every boot.
systemctl disable userconfig.service 2>/dev/null || true
rm -f /lib/systemd/system/userconfig.service 2>/dev/null || true

# ── 4. greetd autologin + marathon session ────────────────────────────
echo "    [chroot] installing greetd autologin + marathon session"

# greetd's config drops the password prompt and launches the Marathon
# Wayland session as user `pi` on tty1.
mkdir -p /etc/greetd
cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "/usr/local/bin/marathon-shell-session"
user = "pi"
EOF

# Session script — directly from platforms/raspberry-pi/config/. We
# overwrite to make sure we have the current version.
install -Dm755 "$SRC/platforms/raspberry-pi/config/marathon-shell-session" \
    /usr/local/bin/marathon-shell-session

# Also drop a wayland-sessions entry for legacy compat (in case a
# different greeter is wired later).
install -Dm644 "$SRC/platforms/raspberry-pi/config/marathon.desktop" \
    /usr/share/wayland-sessions/marathon.desktop

# Mask RaspiOS's stock display manager (lightdm) — it would race
# greetd for /dev/tty1 and the framebuffer.
systemctl disable lightdm.service 2>/dev/null || true
systemctl mask lightdm.service 2>/dev/null || true

# Enable greetd + graphical target.
systemctl enable greetd.service
systemctl set-default graphical.target
# Disable getty on tty1 — greetd owns it.
systemctl disable getty@tty1.service 2>/dev/null || true

# ── 5. plymouth marathon boot splash ──────────────────────────────────
echo "    [chroot] installing Marathon plymouth theme"
mkdir -p /usr/share/plymouth/themes/marathon
cp -av /tmp/marathon-plymouth/marathon/. /usr/share/plymouth/themes/marathon/

# Set as the default theme + rebuild the initramfs so it loads at boot
# (plymouth lives in the initramfs, not the rootfs).
plymouth-set-default-theme -R marathon || {
    # plymouth-set-default-theme may fail silently inside nspawn if it
    # can't find a real kernel package. Fall back to manually setting
    # the symlink, then mark the initramfs for rebuild on first boot.
    rm -f /etc/alternatives/default.plymouth
    ln -sf /usr/share/plymouth/themes/marathon/marathon.plymouth \
        /etc/alternatives/default.plymouth
    touch /var/lib/marathon-plymouth-pending-initrd-rebuild
}

# ── 6. trim build-time -dev packages ──────────────────────────────────
# Keep the runtime libs; remove headers + dev tools that aren't useful
# on the device. Careful with wildcard purges — apt has been known to
# cascade-remove runtime libs in earlier eras. We list packages
# explicitly rather than glob to avoid surprises.
echo "    [chroot] purging build-only packages to slim the image"
apt-get -qq purge -y \
    build-essential cmake ninja-build \
    qt6-base-dev qt6-base-private-dev \
    qt6-declarative-dev qt6-declarative-private-dev \
    qt6-wayland-dev qt6-webengine-dev qt6-tools-dev \
    qt6-svg-dev qt6-multimedia-dev qt6-shadertools-dev \
    libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev libdrm-dev \
    libwayland-dev libxkbcommon-dev libinput-dev libudev-dev \
    libdbus-1-dev libpulse-dev libpipewire-0.3-dev \
    libssl-dev libsecret-1-dev \
    git pkg-config curl || true
apt-get -qq autoremove -y
apt-get -qq clean
rm -rf /var/lib/apt/lists/* /tmp/marathon-build /tmp/marathon-plymouth /root/.cache /root/.cmake

# ── 7. /etc/motd — login banner so SSH bring-up is obvious ────────────
cat > /etc/motd <<'EOF'

  Marathon Edition — HackberryPi CM5
  Built from this checkout. greetd auto-logs in as "pi" and launches
  /usr/local/bin/marathon-shell-session under Wayland.

  Default password: raspberry  (CHANGE THIS — passwd)
  Logs:
    sudo journalctl -u greetd --since '5 minutes ago'
    tail -f /tmp/marathon-shell.log
  Plymouth:
    sudo plymouth-set-default-theme   # show current theme
    sudo update-initramfs -u          # rebuild after changing theme

EOF

echo "    [chroot] customization complete"
