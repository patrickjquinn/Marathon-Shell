#!/bin/bash
# Marathon OS - Build and Run in QEMU
# Zaps chroot, builds Marathon for QEMU virtual machine, and launches it.
#
# Usage: ./scripts/build-marathon-qemu.sh [amd64|aarch64]
# Default: amd64 (x86_64)

set -e

ARCH="${1:-amd64}"
DEVICE="qemu-$ARCH"

case "$ARCH" in
    amd64)
        PMARCH="x86_64"
        ;;
    aarch64)
        PMARCH="aarch64"
        ;;
    *)
        echo "Error: Unsupported architecture '$ARCH'. Use 'amd64' or 'aarch64'."
        exit 1
        ;;
esac

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARATHON_IMAGE_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       MARATHON OS - QEMU BUILD AND RUN                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Device: $DEVICE ($PMARCH)"
echo "Timestamp: $TIMESTAMP"
echo ""

# Keep sudo alive for long builds
if command -v sudo >/dev/null 2>&1; then
    echo "═══ SUDO: Validating credentials (may prompt once) ═══"
    sudo -v
    ( while true; do sudo -n true; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
    echo ""
fi

# ==============================================================================
# STEP 1: Zap ALL chroots and caches
# ==============================================================================
echo "═══ STEP 1: Zapping ALL chroots and caches ═══"
echo ""
# -a = delete everything (all caches, packages, chroots)
# -y is a global flag that goes BEFORE the subcommand
pmbootstrap -y zap -a || true
pmbootstrap shutdown 2>/dev/null || true
echo "✅ All chroots zapped"
echo ""

# ==============================================================================
# STEP 2: Reinitialize pmbootstrap for QEMU device
# ==============================================================================
echo "═══ STEP 2: Reinitializing pmbootstrap for $DEVICE ═══"
echo ""

# Configure pmbootstrap non-interactively
pmbootstrap config device "$DEVICE"
pmbootstrap config systemd always
pmbootstrap config ui none
# QEMU devices require explicit kernel selection: lts, virt, or edge
# lts = Alpine LTS kernel (recommended, most features)
pmbootstrap config kernel lts
pmbootstrap config extra_packages none
pmbootstrap config boot_size 256
pmbootstrap config extra_space 0

# Configure systemd extra repo mirror (required for postmarketos-base-systemd)
pmbootstrap config mirrors.systemd "http://postmarketos.craftyguy.net/extra-repos/systemd/"

# Ensure we're on the systemd channel
CURRENT_CHANNEL=$(pmbootstrap config channel 2>/dev/null || echo "unknown")
if [[ "$CURRENT_CHANNEL" != *"systemd"* ]]; then
    echo "Switching to systemd channel..."
    # Use edge-systemd or similar if available
    pmbootstrap config channel "systemd-v25.06" 2>/dev/null || \
    pmbootstrap config channel "edge" 2>/dev/null || true
fi

echo "✅ pmbootstrap configured for $DEVICE"
pmbootstrap status
echo ""

# ==============================================================================
# STEP 3: Update pmaports
# ==============================================================================
echo "═══ STEP 3: Updating pmaports ═══"
PMAPORTS_DIR="$(pmbootstrap config aports)"
if [ -d "$PMAPORTS_DIR/.git" ]; then
    echo "Cleaning local pmaports modifications..."
    git -C "$PMAPORTS_DIR" reset --hard >/dev/null
    git -C "$PMAPORTS_DIR" clean -fd >/dev/null
fi
pmbootstrap pull || true
echo ""

# ==============================================================================
# STEP 4: Copy Marathon packages to pmaports
# ==============================================================================
echo "═══ STEP 4: Copying Marathon packages to pmaports ═══"
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

echo "✅ Marathon packages copied to pmaports"
echo ""

# ==============================================================================
# STEP 5: Patch marathon-shell APKBUILD for x86_64 support
# ==============================================================================
echo "═══ STEP 5: Patching marathon-shell for $PMARCH support ═══"
echo ""

MARATHON_SHELL_APKBUILD="$PMAPORTS_DIR/main/marathon-shell/APKBUILD"

# Update arch to include both aarch64 and x86_64
if ! grep -q "x86_64" "$MARATHON_SHELL_APKBUILD"; then
    sed -i 's/^arch="aarch64"$/arch="aarch64 x86_64"/' "$MARATHON_SHELL_APKBUILD"
    echo "✅ Added x86_64 to marathon-shell arch"
else
    echo "✅ marathon-shell already supports x86_64"
fi

# For x86_64, we might need to relax some mobile-specific dependencies
# that may not be available (like modemmanager, iio-sensor-proxy)
if [ "$PMARCH" = "x86_64" ]; then
    # Make some mobile-specific deps optional for QEMU testing
    # (these won't be available in QEMU x86_64 but aren't critical for testing)
    echo "Adjusting dependencies for QEMU environment..."
    
    # Remove mobile-specific dependencies that won't work in QEMU
    sed -i '/\tiio-sensor-proxy$/d' "$MARATHON_SHELL_APKBUILD"
fi

# Bump pkgrel to force rebuild
CURRENT_PKGREL=$(grep "^pkgrel=" "$MARATHON_SHELL_APKBUILD" | cut -d= -f2)
NEW_PKGREL=$((CURRENT_PKGREL + 1))
sed -i "s/^pkgrel=$CURRENT_PKGREL$/pkgrel=$NEW_PKGREL/" "$MARATHON_SHELL_APKBUILD"
echo "✅ Bumped pkgrel to $NEW_PKGREL"

echo ""

# ==============================================================================
# STEP 6: Update checksums
# ==============================================================================
echo "═══ STEP 6: Updating checksums ═══"
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
# STEP 7: Build Marathon packages
# ==============================================================================
echo "═══ STEP 7: Building Marathon packages ═══"
echo ""

# Build systemd packages from extra-repos/systemd (required for systemd images)
# These must be built locally because the remote systemd mirror is unreachable
# The order matters: build dependencies first
echo "Building systemd core packages from extra-repos/systemd..."
echo "  (This is required because the remote systemd mirror is not available)"
echo ""

# Core systemd packages - these are dependencies of postmarketos-base-systemd
# ORDER MATTERS: systemd must be built first as it provides systemd-stage0-dev
# which dbus and other packages depend on
for pkg in systemd dbus systemd-services polkit pipewire wireplumber upower postmarketos-base-systemd; do
    echo "Building $pkg..."
    pmbootstrap build "$pkg" --force || {
        echo "⚠️  Could not build $pkg - trying to continue..."
    }
done
echo ""

echo "Building marathon-base-config..."
pmbootstrap build marathon-base-config

echo "Building marathon-boot-logo..."
pmbootstrap build marathon-boot-logo

echo "Building marathon-shell..."
pmbootstrap build marathon-shell --force

echo "✅ Marathon packages built"
echo ""

# ==============================================================================
# STEP 8: Install Marathon OS image
# ==============================================================================
echo "═══ STEP 8: Installing Marathon OS image ═══"
echo ""

# Install with marathon-shell and marathon-base-config
# Using --add to include our packages alongside the device defaults
pmbootstrap install \
    --add marathon-shell,marathon-base-config \
    --password 147147

echo "✅ Marathon OS image installed"
echo ""

# ==============================================================================
# STEP 9: Post-install setup
# ==============================================================================
echo "═══ STEP 9: Post-install configuration ═══"
echo ""

# Enable greetd for Marathon Shell
pmbootstrap chroot --rootfs -- /bin/sh -c '
    # Enable greetd display manager
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable greetd.service 2>/dev/null || true
    fi
    
    # Configure greetd to use marathon-shell-session if available
    if [ -f /usr/bin/marathon-shell-session ]; then
        mkdir -p /etc/greetd
        cat > /etc/greetd/config.toml <<EOF
[terminal]
vt = 7

[default_session]
command = "/usr/bin/marathon-shell-session"
user = "user"
EOF
    fi
'

echo "✅ Post-install configuration complete"
echo ""

# ==============================================================================
# STEP 10: Export image
# ==============================================================================
echo "═══ STEP 10: Exporting image ═══"
echo ""

EXPORT_DIR="/tmp/marathon-qemu-${TIMESTAMP}"
pmbootstrap export "$EXPORT_DIR"

echo "✅ Images exported to $EXPORT_DIR"
ls -lh "$EXPORT_DIR"
echo ""

# ==============================================================================
# STEP 11: Launch QEMU
# ==============================================================================
echo "═══ STEP 11: Launching QEMU ═══"
echo ""

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ✅ BUILD COMPLETE - LAUNCHING QEMU ✅            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📦 Image exported to: $EXPORT_DIR"
echo "🔐 Login: user / 147147"
echo "🔌 SSH: ssh -p 2222 user@localhost"
echo ""
echo "Launching QEMU with Marathon OS..."
echo "(Close the QEMU window or press Ctrl+C to exit)"
echo ""

# Launch QEMU with:
# - 4GB RAM (recommended for Qt6/QML shell)
# - SDL display with GL acceleration
# - Audio support
# - SSH forwarding on port 2222
pmbootstrap qemu \
    --memory 4096 \
    --display sdl \
    --audio pa \
    --image-size 8G \
    --video 720x1280@60 \
    --tablet
