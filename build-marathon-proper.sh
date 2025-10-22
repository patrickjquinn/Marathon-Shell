#!/bin/bash
# Marathon OS Complete Build Script
# Builds a system that boots directly to Marathon Shell, NOT SXMO

set -e

DEVICE="oneplus-enchilada"
PASSWORD="${1:-147147}"

echo "=== Marathon OS Complete Builder ===" 
echo "Device: $DEVICE"
echo "This will build a system that boots to MARATHON SHELL, not SXMO"
echo ""

# Check current config
echo "=== STEP 1: Check pmbootstrap config ==="
CURRENT_UI=$(grep "^ui = " ~/.config/pmbootstrap_v3.cfg | cut -d'=' -f2 | tr -d ' ')
echo "Current UI: $CURRENT_UI"

if [ "$CURRENT_UI" != "none" ]; then
    echo ""
    echo "❌ ERROR: pmbootstrap is configured for UI: $CURRENT_UI"
    echo ""
    echo "You need to reconfigure pmbootstrap:"
    echo "  1. Run: pmbootstrap init"
    echo "  2. Choose device: oneplus-enchilada"
    echo "  3. Choose UI: none"
    echo "  4. Choose branch: v25.06"
    echo "  5. Re-run this script"
    echo ""
    exit 1
fi

echo "✓ pmbootstrap configured correctly (ui = none)"
echo ""

# Copy packages
echo "=== STEP 2: Copy Marathon packages to pmaports ==="
mkdir -p ~/.local/var/pmbootstrap/cache_git/pmaports/device/marathon/
sudo rm -rf ~/.local/var/pmbootstrap/cache_git/pmaports/device/marathon/linux-marathon
sudo rm -rf ~/.local/var/pmbootstrap/cache_git/pmaports/device/marathon/marathon-shell
sudo rm -rf ~/.local/var/pmbootstrap/cache_git/pmaports/device/marathon/marathon-base-config
rsync -av --exclude='.git' packages/linux-marathon/ ~/.local/var/pmbootstrap/cache_git/pmaports/device/marathon/linux-marathon/
rsync -av --exclude='.git' packages/marathon-shell/ ~/.local/var/pmbootstrap/cache_git/pmaports/device/marathon/marathon-shell/
rsync -av --exclude='.git' packages/marathon-base-config/ ~/.local/var/pmbootstrap/cache_git/pmaports/device/marathon/marathon-base-config/
echo "✓ Packages copied"
echo ""

# Build kernel
echo "=== STEP 3: Build Marathon kernel ==="
pmbootstrap build linux-marathon --force
echo "✓ Kernel built"
echo ""

# Build shell
echo "=== STEP 4: Build Marathon Shell ==="
pmbootstrap build marathon-shell --force
echo "✓ Marathon Shell built"
echo ""

# Build base config
echo "=== STEP 5: Build Marathon base config ==="
pmbootstrap build marathon-base-config --force
echo "✓ Base config built"
echo ""

# Install system with Marathon packages
echo "=== STEP 6: Install Marathon OS ==="
echo "Installing base system + Marathon Shell (NOT SXMO)..."
pmbootstrap install \
    --add linux-marathon \
    --add marathon-shell \
    --add marathon-base-config \
    --add greetd \
    --add greetd-gtkgreet \
    --password "$PASSWORD"
echo "✓ System installed"
echo ""

# Configure greetd for auto-login to Marathon Shell
echo "=== STEP 7: Configure greetd for Marathon Shell ==="
pmbootstrap chroot --suffix rootfs_${DEVICE} -- sh -c '
mkdir -p /etc/greetd
cat > /etc/greetd/config.toml << EOF
[terminal]
vt = 1

[default_session]
command = "agreety --cmd /usr/bin/marathon-shell-session"
user = "user"
EOF
'
echo "✓ greetd configured"
echo ""

# Verify installation
echo "=== STEP 8: Verify Marathon Shell installation ==="
echo "Checking for Marathon Shell files..."
pmbootstrap chroot --suffix rootfs_${DEVICE} -- sh -c '
if [ -f /usr/bin/marathon-shell-session ]; then
    echo "✓ marathon-shell-session found"
else
    echo "✗ marathon-shell-session NOT found"
    exit 1
fi

if [ -f /usr/bin/marathon-shell-bin ]; then
    echo "✓ marathon-shell-bin found"
else
    echo "✗ marathon-shell-bin NOT found"  
    exit 1
fi

if [ -f /usr/share/wayland-sessions/marathon.desktop ]; then
    echo "✓ marathon.desktop found"
else
    echo "✗ marathon.desktop NOT found"
    exit 1
fi
'
echo ""

# Check for SXMO (should NOT be installed)
echo "Checking for SXMO (should NOT be present)..."
if pmbootstrap chroot --suffix rootfs_${DEVICE} -- apk list --installed | grep -q sxmo; then
    echo "⚠️  WARNING: SXMO is still installed!"
    echo "This may interfere with Marathon Shell"
else
    echo "✓ SXMO not present (good)"
fi
echo ""

# Export images
echo "=== STEP 9: Export images ==="
pmbootstrap export
echo "✓ Images exported"
echo ""

# Copy to shared folder
echo "=== STEP 10: Copy images to shared folder ==="
if [ -d "/mnt/utm-shared/personal" ]; then
    cp -f ~/.local/var/pmbootstrap/chroot_rootfs_${DEVICE}/boot/boot.img \
        /mnt/utm-shared/personal/boot-marathon-shell.img
    cp -f ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/${DEVICE}.img \
        /mnt/utm-shared/personal/${DEVICE}-marathon-shell.img
    echo "✓ Images copied to /mnt/utm-shared/personal/"
    echo ""
    ls -lh /mnt/utm-shared/personal/*marathon-shell.img
else
    echo "⚠️  Shared folder not found"
    echo "Images available at:"
    echo "  - ~/.local/var/pmbootstrap/chroot_rootfs_${DEVICE}/boot/boot.img"
    echo "  - ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/${DEVICE}.img"
fi
echo ""

echo "=== BUILD COMPLETE ==="
echo ""
echo "✅ Marathon OS with Marathon Shell is ready!"
echo ""
echo "This image will boot to MARATHON SHELL, not SXMO."
echo ""
echo "Flash with:"
echo "  fastboot erase userdata"
echo "  fastboot flash boot boot-marathon-shell.img"
echo "  fastboot flash userdata ${DEVICE}-marathon-shell.img"
echo "  fastboot reboot"

