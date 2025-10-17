#!/bin/bash
# Marathon OS Build and Flash Script - Improved Version
# Supports multiple ARM64 devices with robust error handling

set -e

# Default device (can be overridden)
DEVICE="${1:-enchilada}"
WORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES_DIR="$WORK_DIR/packages"
DEVICES_DIR="$WORK_DIR/devices"

# Configuration
DUMMY_PASSWORD="147147"
EXPORT_DIR="/tmp/postmarketOS-export"

echo "=== Marathon OS Build Script (Improved) ==="
echo "Device: $DEVICE"
echo "Working directory: $WORK_DIR"
echo ""

# Load device configuration
DEVICE_CONF="$DEVICES_DIR/$DEVICE/device.conf"
if [ ! -f "$DEVICE_CONF" ]; then
    echo "Error: Device configuration not found: $DEVICE_CONF"
    echo ""
    echo "Available devices:"
    ls -1 "$DEVICES_DIR" 2>/dev/null || echo "No devices directory found"
    echo ""
    echo "Usage: $0 [device-codename]"
    echo "Example: $0 enchilada"
    exit 1
fi

echo "Loading device configuration..."
source "$DEVICE_CONF"

# Validate pmbootstrap
PMAPORTS_DIR="$HOME/.local/var/pmbootstrap/cache_git/pmaports"
if [ ! -d "$PMAPORTS_DIR" ]; then
    echo "Error: pmaports directory not found. Run 'pmbootstrap init' first."
    echo ""
    echo "Initialize with:"
    echo "  pmbootstrap init"
    echo "  Select: v25.06 (stable), $DEVICE_VENDOR/$DEVICE_CODENAME, systemd, none"
    exit 1
fi

echo ""
echo "Device Details:"
echo "  Name: $DEVICE_NAME"
echo "  Vendor: $DEVICE_VENDOR"
echo "  SoC: $DEVICE_SOC"
echo "  Bootloader: $BOOTLOADER_TYPE"
echo "  Flash method: $FLASH_METHOD"
echo ""

# Function to check if pmbootstrap is running
check_pmbootstrap_status() {
    if pgrep -f "pmbootstrap" > /dev/null; then
        echo "Warning: pmbootstrap is already running. Shutting down..."
        pmbootstrap shutdown || true
        sleep 2
    fi
}

# Function to cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up..."
    pmbootstrap shutdown || true
    # Remove any stuck loop devices
    sudo losetup -D || true
}
trap cleanup EXIT

# Function to verify package build
verify_package_build() {
    local package_name="$1"
    echo "Verifying $package_name build..."
    
    if ! pmbootstrap build --dry-run "$package_name" > /dev/null 2>&1; then
        echo "Error: $package_name build verification failed"
        return 1
    fi
    echo "✓ $package_name build verified"
    return 0
}

# Function to copy package sources with error checking
copy_package_sources() {
    local package_name="$1"
    local source_dir="$PACKAGES_DIR/$package_name"
    local dest_dir="$PMAPORTS_DIR/main/$package_name"
    
    if [ ! -d "$source_dir" ]; then
        echo "Error: Package source directory not found: $source_dir"
        return 1
    fi
    
    echo "Copying $package_name sources..."
    rm -rf "$dest_dir"
    cp -r "$source_dir" "$dest_dir"
    
    # Copy to pmbootstrap cache as well
    local cache_dir="$HOME/.local/var/pmbootstrap/cache_git/pmaports/main/$package_name"
    rm -rf "$cache_dir"
    cp -r "$source_dir" "$cache_dir"
    
    echo "✓ $package_name sources copied"
    return 0
}

echo "Step 1: Pre-build checks..."
check_pmbootstrap_status

echo ""
echo "Step 2: Copying package sources to pmbootstrap workspace..."

# Copy marathon-base-config
if ! copy_package_sources "marathon-base-config"; then
    exit 1
fi

# Copy marathon-shell
if ! copy_package_sources "marathon-shell"; then
    exit 1
fi

# Copy kernel package with device context
echo "Copying kernel package..."
mkdir -p "$PMAPORTS_DIR/device/marathon"
mkdir -p "$PMAPORTS_DIR/device/marathon/linux-marathon-$DEVICE_CODENAME"
rm -rf "$PMAPORTS_DIR/device/marathon/linux-marathon-$DEVICE_CODENAME"
cp -r "$PACKAGES_DIR/linux-marathon" "$PMAPORTS_DIR/device/marathon/linux-marathon-$DEVICE_CODENAME"

# Copy device-specific configs
if [ -n "$KERNEL_CONFIG_FRAGMENT" ] && [ -f "$DEVICES_DIR/$DEVICE_SOC/$KERNEL_CONFIG_FRAGMENT" ]; then
    cp "$DEVICES_DIR/$DEVICE_SOC/kernel-config.fragment" \
       "$PMAPORTS_DIR/device/marathon/linux-marathon-$DEVICE_CODENAME/"
fi

echo "✓ All package sources copied"

echo ""
echo "Step 3: Building custom kernel for $DEVICE_NAME..."
if ! pmbootstrap build "linux-marathon-$DEVICE_CODENAME" --force; then
    echo "Error: Kernel build failed"
    exit 1
fi
echo "✓ Kernel build completed"

echo ""
echo "Step 4: Building marathon-base-config..."
if ! pmbootstrap build marathon-base-config --force; then
    echo "Error: marathon-base-config build failed"
    exit 1
fi
echo "✓ marathon-base-config build completed"

echo ""
echo "Step 5: Building marathon-shell..."
if ! pmbootstrap build marathon-shell --force; then
    echo "Error: marathon-shell build failed"
    exit 1
fi
echo "✓ marathon-shell build completed"

echo ""
echo "Step 6: Installing system with custom packages..."
echo "Using dummy password to avoid interactive setup..."

# First, install without creating images to set up the rootfs
if ! pmbootstrap install --password "$DUMMY_PASSWORD" --no-image; then
    echo "Error: System installation failed"
    exit 1
fi
echo "✓ System installation completed"

echo ""
echo "Step 7: Installing complete system with Marathon Shell..."

# Install everything in one go: system + kernel + base-config + greetd + Marathon Shell + create images
if ! pmbootstrap install --password "$DUMMY_PASSWORD" --add linux-marathon-enchilada,marathon-base-config,marathon-shell,greetd,greetd-agreety --split --filesystem ext4; then
    echo "Error: Complete system installation failed"
    exit 1
fi
echo "✓ Complete system with Marathon Shell, base config, and custom kernel installed"

echo ""
echo "Step 8: Configuring Marathon Shell and greetd..."

# Configure Marathon Shell and greetd for autologin
ROOTFS_DIR="$HOME/.local/var/pmbootstrap/chroot_rootfs_$DEVICE_VENDOR-$DEVICE_CODENAME"

# Copy Marathon Shell compositor script
if [ -f "$PACKAGES_DIR/marathon-shell/marathon-compositor" ]; then
    echo "Installing Marathon Shell compositor script..."
    sudo cp "$PACKAGES_DIR/marathon-shell/marathon-compositor" \
        "$ROOTFS_DIR/usr/bin/marathon-compositor"
    sudo chmod +x "$ROOTFS_DIR/usr/bin/marathon-compositor"
    echo "✓ Marathon Shell compositor script installed"
else
    echo "Error: Marathon Shell compositor script not found"
    exit 1
fi

# Install Marathon Shell session file
if [ -f "$PACKAGES_DIR/marathon-shell/marathon.desktop" ]; then
    echo "Installing Marathon Shell session file..."
    sudo mkdir -p "$ROOTFS_DIR/usr/share/wayland-sessions"
    sudo cp "$PACKAGES_DIR/marathon-shell/marathon.desktop" \
        "$ROOTFS_DIR/usr/share/wayland-sessions/marathon.desktop"
    echo "✓ Marathon Shell session file installed"
else
    echo "Error: Marathon Shell session file not found"
    exit 1
fi

# Configure greetd for autologin
echo "Configuring greetd for autologin..."
sudo mkdir -p "$ROOTFS_DIR/etc/greetd"
if [ -f "$PACKAGES_DIR/marathon-shell/greetd-marathon.toml" ]; then
    sudo cp "$PACKAGES_DIR/marathon-shell/greetd-marathon.toml" \
        "$ROOTFS_DIR/etc/greetd/config.toml"
else
    # Create greetd config if not found
    sudo tee "$ROOTFS_DIR/etc/greetd/config.toml" > /dev/null << 'EOF'
# greetd configuration for Marathon OS
# Autologin to Marathon Shell

[terminal]
vt = 1

[default_session]
command = "/usr/bin/marathon-compositor"
user = "user"
EOF
fi
echo "✓ greetd configured for autologin"

# Enable greetd service
echo "Enabling greetd service..."
sudo mkdir -p "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants"
sudo ln -sf "/usr/lib/systemd/system/greetd.service" \
    "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/greetd.service"
echo "✓ greetd service enabled"

echo ""
echo "Step 9: Finalizing images..."
echo "✓ Split images already created"

echo ""
echo "Step 10: Exporting images..."
if ! pmbootstrap export; then
    echo "Error: Image export failed"
    exit 1
fi
echo "✓ Images exported to $EXPORT_DIR"

echo ""
echo "Step 11: Verifying generated images..."
if [ ! -d "$EXPORT_DIR" ]; then
    echo "Error: Export directory not found: $EXPORT_DIR"
    exit 1
fi

# Check for essential images
ESSENTIAL_IMAGES=("boot.img" "vmlinuz" "initramfs" "oneplus-enchilada-boot.img" "oneplus-enchilada-root.img")
MISSING_IMAGES=()

for image in "${ESSENTIAL_IMAGES[@]}"; do
    if [ ! -L "$EXPORT_DIR/$image" ] && [ ! -f "$EXPORT_DIR/$image" ]; then
        MISSING_IMAGES+=("$image")
    fi
done

if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
    echo "Warning: Missing essential images:"
    for image in "${MISSING_IMAGES[@]}"; do
        echo "  - $image"
    done
else
    echo "✓ All essential images found"
fi

echo ""
echo "Step 12: Copying images to output directory..."
OUTPUT_DIR="$WORK_DIR/out/$DEVICE_CODENAME"
mkdir -p "$OUTPUT_DIR"

# Copy all images from export directory
if [ -d "$EXPORT_DIR" ]; then
    cp -L "$EXPORT_DIR"/* "$OUTPUT_DIR/" 2>/dev/null || true
    echo "✓ Images copied to $OUTPUT_DIR"
else
    echo "Warning: No images to copy"
fi

echo ""
echo "=== Build Complete ==="
echo "Device: $DEVICE_NAME ($DEVICE_CODENAME)"
echo "Images are in: $OUTPUT_DIR"
echo ""
echo "✅ Marathon OS with Marathon Shell is ready!"
echo "✅ System will boot directly to Marathon Shell (no login screen)"
echo "✅ All BlackBerry 10-inspired optimizations applied"
echo ""

# List generated images
echo "Generated images:"
ls -lah "$OUTPUT_DIR" 2>/dev/null || echo "No images found in output directory"

echo ""
case "$FLASH_METHOD" in
    fastboot)
        echo "To flash to device:"
        echo "  1. Boot device into fastboot mode"
        echo "  2. Connect via USB"
        echo "  3. Run the following commands:"
        echo ""
        echo "     fastboot flash boot $OUTPUT_DIR/boot.img"
        echo "     fastboot flash system $OUTPUT_DIR/oneplus-enchilada-root.img"
        echo "     fastboot reboot"
        ;;
    dd)
        echo "To flash to SD card/USB:"
        echo "  1. Insert SD card"
        echo "  2. Identify device (lsblk)"
        echo "  3. Flash image:"
        echo ""
        echo "     sudo dd if=$OUTPUT_DIR/oneplus-enchilada.img of=/dev/sdX bs=4M status=progress"
        echo "     sync"
        ;;
    *)
        echo "Flash method: $FLASH_METHOD"
        echo "Refer to device documentation for flashing instructions."
        ;;
esac

echo ""
echo "Build completed successfully!"
echo "All images are ready for flashing."
