#!/bin/bash
# Marathon OS - Build and Run in QEMU
# Builds Marathon OS for QEMU virtual machine with full verification.
#
# Usage: ./scripts/build-marathon-qemu.sh [aarch64|arm64|amd64|x86_64]
# Default: aarch64 (mobile-first)

set -euo pipefail

ARCH_INPUT="${1:-aarch64}"
MOBILE_WIDTH=720
MOBILE_HEIGHT=1440
MOBILE_REFRESH=60
KERNEL_VIDEO_MODE="${MOBILE_WIDTH}x${MOBILE_HEIGHT}"
QEMU_VIDEO_MODE="${MOBILE_WIDTH}x${MOBILE_HEIGHT}@${MOBILE_REFRESH}"

# Prevent multiple pmbootstrap runs from clobbering config/build outputs.
LOCK_FILE="/tmp/marathon-qemu-build.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "Error: another Marathon QEMU build appears to be running."
    echo "Please stop concurrent build scripts, then retry."
    exit 1
fi

case "$ARCH_INPUT" in
    aarch64|arm64)
        ARCH="aarch64"
        PMARCH="aarch64"
        ;;
    amd64|x86_64)
        ARCH="amd64"
        PMARCH="x86_64"
        ;;
    *)
        echo "Error: Unsupported architecture '$ARCH_INPUT'. Use: aarch64, arm64, amd64, or x86_64."
        exit 1
        ;;
esac
DEVICE="qemu-$ARCH"

# Mobile project safety: default to ARM and block accidental amd64 builds
# unless explicitly overridden.
if [ "$ARCH" = "amd64" ] && [ "${MARATHON_ALLOW_AMD64:-0}" != "1" ]; then
    echo "Error: amd64 build blocked for mobile profile."
    echo "Use: ./scripts/build-marathon-qemu.sh arm64"
    echo "Override only if intentional: MARATHON_ALLOW_AMD64=1 ./scripts/build-marathon-qemu.sh amd64"
    exit 1
fi

# Use venv pmbootstrap if available
if [ -f "$HOME/.local/var/pmbootstrap-venv/bin/pmbootstrap" ]; then
    alias pmbootstrap="$HOME/.local/var/pmbootstrap-venv/bin/pmbootstrap"
    shopt -s expand_aliases
    echo "Using pmbootstrap from venv: $(which pmbootstrap)"
fi

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARATHON_IMAGE_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="/tmp/marathon-qemu-logs-${TIMESTAMP}"
mkdir -p "$LOG_DIR"

echo "+------------------------------------------------------------+"
echo "|       MARATHON OS - QEMU BUILD AND RUN                      |"
echo "+------------------------------------------------------------+"
echo ""
echo "Device:    $DEVICE ($PMARCH)"
echo "Target:    $ARCH_INPUT -> $ARCH ($PMARCH)"
echo "Timestamp: $TIMESTAMP"
echo "Logs:      $LOG_DIR"
echo ""

# Note: pmbootstrap handles sudo prompts internally

# ==============================================================================
# STEP 1: Initialize pmbootstrap
# ==============================================================================
echo "═══ STEP 1: Initializing pmbootstrap for $DEVICE ═══"
echo ""

# Ensure work directory exists
WORK_DIR="${HOME}/.local/var/pmbootstrap"
if [ ! -d "$WORK_DIR" ]; then
    echo "Creating pmbootstrap work directory..."
    mkdir -p "$WORK_DIR"
fi

# Zap ALL chroots and caches for a clean build
pmbootstrap -y zap -a 2>/dev/null || true
pmbootstrap shutdown 2>/dev/null || true

# Configure pmbootstrap non-interactively
pmbootstrap config device "$DEVICE"
pmbootstrap config systemd always
pmbootstrap config ui none
# QEMU devices use LTS kernel (has Landlock support)
pmbootstrap config kernel lts
pmbootstrap config extra_packages none
pmbootstrap config boot_size 256
pmbootstrap config extra_space 2048

# Configure systemd extra repo mirror (required for postmarketos-base-systemd)
# MIRROR IS DOWN - Building locally instead
# pmbootstrap config mirrors.systemd "http://postmarketos.craftyguy.net/extra-repos/systemd/"

echo "pmbootstrap configured for $DEVICE"
pmbootstrap status 2>&1 || true
echo ""

# ==============================================================================
# STEP 2: Update pmaports
# ==============================================================================
echo "═══ STEP 2: Updating pmaports ═══"
PMAPORTS_DIR="$(pmbootstrap config aports)"
if [ -d "$PMAPORTS_DIR/.git" ]; then
    echo "Cleaning local pmaports modifications..."
    git -C "$PMAPORTS_DIR" reset --hard >/dev/null
    git -C "$PMAPORTS_DIR" clean -fd >/dev/null
fi
pmbootstrap pull || true
echo ""

# ==============================================================================
# STEP 3: Copy Marathon packages to pmaports
# ==============================================================================
echo "═══ STEP 3: Copying Marathon packages to pmaports ═══"
echo ""

cd "$MARATHON_IMAGE_DIR"
PMAPORTS_DIR="$(pmbootstrap config aports)"

# Ensure directories exist
mkdir -p "$PMAPORTS_DIR/main" "$PMAPORTS_DIR/device/main"

# Clean and copy marathon-shell
rm -rf "$PMAPORTS_DIR/main/marathon-shell"
cp -r packages/marathon-shell "$PMAPORTS_DIR/main/"

# Clean and copy marathon-base-config
rm -rf "$PMAPORTS_DIR/main/marathon-base-config"
cp -r packages/marathon-base-config "$PMAPORTS_DIR/main/"

# Clean and copy marathon-boot-logo
rm -rf "$PMAPORTS_DIR/main/marathon-boot-logo"
cp -r packages/marathon-boot-logo "$PMAPORTS_DIR/main/"

echo "Marathon packages copied to pmaports"

# Patch deviceinfo for QEMU resolution
echo "Patching deviceinfo for ${MOBILE_WIDTH}x${MOBILE_HEIGHT} portrait mobile resolution..."
PMAPORTS="$HOME/.local/var/pmbootstrap/cache_git/pmaports"
DEVICEINFO="$PMAPORTS/device/main/device-$DEVICE/deviceinfo"
if grep -q '^deviceinfo_screen_width=' "$DEVICEINFO"; then
    sed -i "s/^deviceinfo_screen_width=.*/deviceinfo_screen_width=\"${MOBILE_WIDTH}\"/" "$DEVICEINFO"
else
    echo "deviceinfo_screen_width=\"${MOBILE_WIDTH}\"" >> "$DEVICEINFO"
fi

if grep -q '^deviceinfo_screen_height=' "$DEVICEINFO"; then
    sed -i "s/^deviceinfo_screen_height=.*/deviceinfo_screen_height=\"${MOBILE_HEIGHT}\"/" "$DEVICEINFO"
else
    echo "deviceinfo_screen_height=\"${MOBILE_HEIGHT}\"" >> "$DEVICEINFO"
fi

if grep -q '^deviceinfo_kernel_cmdline=' "$DEVICEINFO"; then
    if grep -qE '^deviceinfo_kernel_cmdline=".*video=' "$DEVICEINFO"; then
        sed -i -E "s/(^deviceinfo_kernel_cmdline=\"[^\"]*)video=[^ \"']+/\1video=${KERNEL_VIDEO_MODE}/" "$DEVICEINFO"
    else
        sed -i -E "s/(^deviceinfo_kernel_cmdline=\"[^\"]*)\"/\1 video=${KERNEL_VIDEO_MODE}\"/" "$DEVICEINFO"
    fi
fi
echo "deviceinfo patched"
echo ""

# ==============================================================================
# STEP 4: Patch marathon-shell APKBUILD for QEMU support
# ==============================================================================
echo "═══ STEP 4: Patching marathon-shell for $PMARCH support ═══"
echo ""

MARATHON_SHELL_APKBUILD="$PMAPORTS_DIR/main/marathon-shell/APKBUILD"

# x86_64 cross-build support is only needed for qemu-amd64 runs.
if [ "$PMARCH" = "x86_64" ]; then
    if ! grep -q "x86_64" "$MARATHON_SHELL_APKBUILD"; then
        sed -i 's/^arch="aarch64"$/arch="aarch64 x86_64"/' "$MARATHON_SHELL_APKBUILD"
        echo "Added x86_64 to marathon-shell arch"
    else
        echo "marathon-shell already supports x86_64"
    fi
fi

echo "Adjusting dependencies for QEMU environment..."
# Remove mobile-specific dependencies that don't work in QEMU
sed -i '/\tiio-sensor-proxy$/d' "$MARATHON_SHELL_APKBUILD"

# Bump pkgrel only when needed to force rebuild for x86_64 porting changes.
if [ "$PMARCH" = "x86_64" ]; then
    CURRENT_PKGREL=$(grep "^pkgrel=" "$MARATHON_SHELL_APKBUILD" | cut -d= -f2)
    NEW_PKGREL=$((CURRENT_PKGREL + 1))
    sed -i "s/^pkgrel=$CURRENT_PKGREL$/pkgrel=$NEW_PKGREL/" "$MARATHON_SHELL_APKBUILD"
    echo "Bumped pkgrel to $NEW_PKGREL"
fi
echo ""

# ==============================================================================
# STEP 5: Update checksums
# ==============================================================================
echo "═══ STEP 5: Updating checksums ═══"
echo ""

# Clear cached tarballs
PMBOOTSTRAP_WORK_DIR="$(pmbootstrap config work)"
rm -f "$PMBOOTSTRAP_WORK_DIR/cache_distfiles/"*marathon-shell* 2>/dev/null || true
rm -f "$PMBOOTSTRAP_WORK_DIR/cache_distfiles/"*asyncfuture* 2>/dev/null || true

pmbootstrap checksum marathon-shell || true
pmbootstrap checksum marathon-base-config || true
pmbootstrap checksum marathon-boot-logo || true
echo ""

# ==============================================================================
# STEP 6: Build Systemd & Marathon packages
# ==============================================================================
echo "═══ STEP 6: Building Systemd & Marathon packages ═══"
echo ""

# Build the device package after patching deviceinfo so initramfs/boot config
# picks up portrait geometry in the generated image.
echo "Building device package for $DEVICE..."
pmbootstrap build --arch "$PMARCH" "device-$DEVICE" --force || {
    echo " Could not build device-$DEVICE - trying to continue..."
}
echo ""

# Build systemd packages locally because the mirror is often unreachable/unstable
echo "Building systemd core packages from extra-repos/systemd..."
# Order matters: systemd provides build dependencies for others.
# Build only packages that are expected in systemd extra-repo flow.
for pkg in systemd dbus systemd-services polkit postmarketos-base-systemd; do
    echo "Building $pkg..."
    pmbootstrap build --arch "$PMARCH" "$pkg" --force || {
        echo " Could not build $pkg - trying to continue..."
    }
done
echo ""

echo "Building marathon-base-config..."
pmbootstrap build --arch "$PMARCH" marathon-base-config

echo "Building marathon-boot-logo..."
pmbootstrap build --arch "$PMARCH" marathon-boot-logo

echo "Building marathon-shell..."
pmbootstrap build --arch "$PMARCH" marathon-shell --force

echo "Marathon packages built"
echo ""

# ==============================================================================
# STEP 7: Install Marathon OS image
# ==============================================================================
echo "═══ STEP 7: Installing Marathon OS image ═══"
echo ""

# Sanity-check that local package indexes exist for the requested target arch.
# If they do not, pmbootstrap install will fail with "no such package".
PMBOOTSTRAP_WORK_DIR="$(pmbootstrap config work)"
PMB_CHANNEL="$(pmbootstrap status 2>/dev/null | awk '/^Channel:/{print $2}' | sed 's/^systemd-//')"
PMB_CHANNEL="${PMB_CHANNEL:-v25.12}"
if [ ! -f "$PMBOOTSTRAP_WORK_DIR/packages/$PMB_CHANNEL/$PMARCH/APKINDEX.tar.gz" ] || \
   [ ! -f "$PMBOOTSTRAP_WORK_DIR/packages/systemd-$PMB_CHANNEL/$PMARCH/APKINDEX.tar.gz" ]; then
    echo "Local APKINDEX missing for $PMARCH; forcing postmarketos-base-systemd rebuild..."
    pmbootstrap build --arch "$PMARCH" postmarketos-base-systemd --force || true
fi

# Install with marathon-shell, marathon-base-config, and greetd (for auto-login)
pmbootstrap install \
    --add marathon-shell,marathon-base-config,greetd \
    --password 147147

echo "Marathon OS image installed"
echo ""

# ==============================================================================
# STEP 8: Post-install QEMU-specific configuration
# ==============================================================================
echo "═══ STEP 8: Post-install QEMU configuration ═══"
echo ""

pmbootstrap chroot --rootfs -- /bin/sh -c '
    # ── 1. Force greetd autologin on VT1 for QEMU ──
    # QEMU displays tty1 by default; using vt=1 avoids landing on a console login first.
    echo "Writing QEMU greetd config (autologin to Marathon Shell on tty1)..."
    mkdir -p /etc/greetd
    cat > /etc/greetd/config.toml <<GREETDEOF
[terminal]
vt = 1

[default_session]
command = "/usr/bin/marathon-shell-session"
user = "user"

[initial_session]
command = "/usr/bin/marathon-shell-session"
user = "user"
GREETDEOF
    cat /etc/greetd/config.toml

    # ── 2. Override GPU environment for QEMU (virtio-gpu / llvmpipe) ──
    echo "Configuring GPU environment for QEMU..."
    cat > /etc/environment.d/50-gpu-acceleration.conf <<GPUEOF
# Marathon OS GPU Environment - QEMU (virtio-gpu / llvmpipe software rendering)
# This overrides the Adreno-specific config from marathon-base-config

# Force software rendering (QEMU has no real GPU)
LIBGL_ALWAYS_SOFTWARE=1
GALLIUM_DRIVER=llvmpipe

# Mesa version overrides
MESA_GL_VERSION_OVERRIDE=3.3
MESA_GLSL_VERSION_OVERRIDE=330
MESA_GLES_VERSION_OVERRIDE=3.0

# Qt rendering: use software backend
QT_QUICK_BACKEND=software
QT_OPENGL=software

# Disable hardware-specific settings
LIBGL_ALWAYS_INDIRECT=0
GPUEOF

    # ── 3. Override marathon-shell-session for QEMU ──
    echo "Configuring marathon-shell-session for QEMU..."
    cat > /usr/bin/marathon-shell-session <<SESSIONEOF
#!/bin/sh
# Marathon Shell Wayland Session Startup Script
# QEMU-adapted version: uses linuxfb/software rendering

# Set session name
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=marathon
export XDG_CURRENT_DESKTOP=marathon

# Marathon-specific paths
export MARATHON_PREFIX=/usr
export MARATHON_APPS_DIR=~/.local/share/marathon-apps

# Qt/QML environment - QEMU compatible
# Use linuxfb as the platform plugin for QEMU virtual framebuffer
export QT_QPA_PLATFORM=linuxfb
export QT_QPA_FB_DRM=1
export QT_MEDIA_BACKEND=gstreamer
export QT_WEBENGINE_DISABLE_SANDBOX=1
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QT_QUICK_CONTROLS_STYLE=Basic
export QML_IMPORT_PATH=/usr/lib/qt6/qml:\$QML_IMPORT_PATH
export QML2_IMPORT_PATH=/usr/lib/qt6/qml:\$QML2_IMPORT_PATH

# Software rendering for QEMU
export QT_QUICK_BACKEND=software
export QT_OPENGL=software
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER=llvmpipe

# Wayland environment
export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}

# D-Bus session
if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
    if command -v dbus-run-session >/dev/null 2>&1; then
        exec dbus-run-session -- /usr/bin/marathon-shell-bin "\$@"
    fi
fi

# Logging
export QT_LOGGING_RULES="*.warning=true;marathon.*.info=true"

# Accessibility - disable AT-SPI bridge
export NO_AT_BRIDGE=1
export GTK_A11Y=none
export QT_ACCESSIBILITY=0

# GIO/GSettings
export GIO_USE_VFS=local
export GSETTINGS_BACKEND=memory

# Start the compositor
exec /usr/bin/marathon-shell-bin "\$@"
SESSIONEOF
    chmod 755 /usr/bin/marathon-shell-session

    # ── 4. Mask hardware-specific services that generate errors in QEMU ──
    echo "Masking hardware-specific services for QEMU..."
    systemctl mask ModemManager.service 2>/dev/null || true
    # iio-sensor-proxy is only relevant with real sensors
    systemctl mask iio-sensor-proxy.service 2>/dev/null || true

    # ── 5. Make boot target + display manager deterministic in image builds ──
    echo "Forcing graphical target + greetd enablement..."
    ln -sf /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target
    mkdir -p /etc/systemd/system/graphical.target.wants
    ln -sf /usr/lib/systemd/system/greetd.service /etc/systemd/system/graphical.target.wants/greetd.service
    # Prevent tty1 text login from racing with greetd on first boot.
    ln -sf /dev/null /etc/systemd/system/getty@tty1.service

    # Keep service enable calls as a best-effort fallback.
    systemctl enable greetd.service 2>/dev/null || true
    systemctl enable NetworkManager.service 2>/dev/null || true
    systemctl enable dbus.service 2>/dev/null || true
    systemctl enable systemd-logind.service 2>/dev/null || true

    # ── 6. Ensure user is in correct groups ──
    if id user >/dev/null 2>&1; then
        for group in audio video input plugdev netdev wheel render; do
            if getent group "$group" >/dev/null 2>&1; then
                adduser user "$group" 2>/dev/null || true
            fi
        done
        # Enable linger for user services
        mkdir -p /var/lib/systemd/linger
        touch /var/lib/systemd/linger/user
    fi

    # ── 7. Enable SSH for remote verification ──
    if [ -f /usr/lib/systemd/system/sshd.service ]; then
        systemctl enable sshd.service 2>/dev/null || true
    fi

    # ── 8. Create XDG_RUNTIME_DIR for user via tmpfiles ──
    mkdir -p /etc/tmpfiles.d
    echo "d /run/user/10000 0700 user user -" > /etc/tmpfiles.d/marathon-user.conf

    echo ""
    echo "QEMU post-install configuration complete"
'

echo ""

# ==============================================================================
# STEP 9: Export image
# ==============================================================================
echo "═══ STEP 9: Exporting image ═══"
echo ""

EXPORT_DIR="/tmp/marathon-qemu-${TIMESTAMP}"
pmbootstrap export "$EXPORT_DIR"

echo "Images exported to $EXPORT_DIR"
ls -lh "$EXPORT_DIR"
echo ""

# ==============================================================================
# STEP 10: Launch QEMU
# ==============================================================================
echo "═══ STEP 10: Launching QEMU ═══"
echo ""

echo "+------------------------------------------------------------+"
echo "|             BUILD COMPLETE - LAUNCHING QEMU           |"
echo "+------------------------------------------------------------+"
echo ""
echo "Image exported to: $EXPORT_DIR"
echo "Build logs: $LOG_DIR"
echo "Login: user / 147147"
echo "SSH: ssh -p 2222 user@localhost"
echo ""
echo "Launching QEMU with Marathon OS..."
echo "(Close the QEMU window or press Ctrl+C to exit)"
echo ""

# Launch QEMU with:
# - 4GB RAM (recommended for Qt6/QML shell)
# - SDL display
# - SSH forwarding on port 2222
# - Serial console captured to log file
pmbootstrap qemu \
    --memory 4096 \
    --display sdl \
    --video "$QEMU_VIDEO_MODE" \
    --image-size 8G \
    --cmdline "video=${KERNEL_VIDEO_MODE}" \
    2>&1 | tee "$LOG_DIR/qemu-boot.log"
