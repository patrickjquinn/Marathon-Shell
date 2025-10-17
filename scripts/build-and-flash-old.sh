#!/bin/bash
# Marathon OS Build and Flash Script
# Supports multiple ARM64 devices

set -e

# Default device (can be overridden)
DEVICE="${1:-enchilada}"
WORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES_DIR="$WORK_DIR/packages"
DEVICES_DIR="$WORK_DIR/devices"

echo "=== Marathon OS Build Script ==="
echo "Device: $DEVICE"
echo "Working directory: $WORK_DIR"
echo ""

# Load device configuration
DEVICE_CONF="$DEVICES_DIR/$DEVICE/device.conf"
if [ ! -f "$DEVICE_CONF" ]; then
    echo "Error: Device configuration not found: $DEVICE_CONF"
    echo ""
    echo "Available devices:"
    ls -1 "$DEVICES_DIR"
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
    echo "  Select: edge, $DEVICE_VENDOR/$DEVICE_CODENAME, systemd, none"
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

echo "Step 1: Copying package sources to pmbootstrap workspace..."
cp -r "$PACKAGES_DIR/marathon-base-config" "$PMAPORTS_DIR/main/"
cp -r "$PACKAGES_DIR/marathon-shell" "$PMAPORTS_DIR/main/"

# Copy kernel package with device context
mkdir -p "$PMAPORTS_DIR/device/marathon"
mkdir -p "$PMAPORTS_DIR/device/marathon/linux-marathon-$DEVICE_CODENAME"
cp -r "$PACKAGES_DIR/linux-marathon"/* "$PMAPORTS_DIR/device/marathon/linux-marathon-$DEVICE_CODENAME/"

# Copy device-specific configs
if [ -n "$KERNEL_CONFIG_FRAGMENT" ] && [ -f "$DEVICES_DIR/$DEVICE_SOC/$KERNEL_CONFIG_FRAGMENT" ]; then
    cp "$DEVICES_DIR/$DEVICE_SOC/kernel-config.fragment" \
       "$PMAPORTS_DIR/device/marathon/linux-marathon-$DEVICE_CODENAME/"
fi

echo ""
echo "Step 2: Building custom kernel for $DEVICE_NAME..."
( cd "$PMAPORTS_DIR/device/marathon/linux-marathon-$DEVICE_CODENAME" && \
  device="$DEVICE_CODENAME" pmbootstrap build linux-marathon-$DEVICE_CODENAME )

echo ""
echo "Step 3: Building marathon-base-config..."
pmbootstrap build marathon-base-config

echo ""
echo "Step 4: Building marathon-shell..."
pmbootstrap build marathon-shell

echo ""
echo "Step 5: Installing system with custom packages..."
pmbootstrap install \
    --device "$DEVICE_VENDOR-$DEVICE_CODENAME" \
    --add marathon-base-config \
    --add marathon-shell \
    --kernel marathon-$DEVICE_CODENAME

echo ""
echo "Step 6: Exporting images..."
mkdir -p "$WORK_DIR/out/$DEVICE_CODENAME"

case "$BOOTLOADER_TYPE" in
    android)
        echo "Creating Android boot image..."
        pmbootstrap export --android-boot-img
        pmbootstrap flasher export_rootfs
        ;;
    u-boot)
        echo "Creating U-Boot compatible image..."
        pmbootstrap export
        ;;
    *)
        echo "Unknown bootloader type: $BOOTLOADER_TYPE"
        exit 1
        ;;
esac

echo ""
echo "Step 7: Copying images to output directory..."
CHROOT_DIR="$HOME/.local/var/pmbootstrap/chroot_native"
if [ -d "$CHROOT_DIR/tmp" ]; then
    cp "$CHROOT_DIR"/tmp/*$DEVICE_CODENAME*.img "$WORK_DIR/out/$DEVICE_CODENAME/" 2>/dev/null || true
fi

echo ""
echo "=== Build Complete ==="
echo "Device: $DEVICE_NAME ($DEVICE_CODENAME)"
echo "Images are in: $WORK_DIR/out/$DEVICE_CODENAME/"
echo ""

case "$FLASH_METHOD" in
    fastboot)
        echo "To flash to device:"
        echo "  1. Boot device into fastboot mode"
        echo "  2. Connect via USB"
        echo "  3. Run the following commands:"
        echo ""
        echo "     fastboot flash $BOOT_PARTITION $WORK_DIR/out/$DEVICE_CODENAME/boot-*.img"
        echo "     fastboot flash $SYSTEM_PARTITION $WORK_DIR/out/$DEVICE_CODENAME/postmarketos-*.img"
        echo "     fastboot reboot"
        ;;
    dd)
        echo "To flash to SD card/USB:"
        echo "  1. Insert SD card"
        echo "  2. Identify device (lsblk)"
        echo "  3. Flash image:"
        echo ""
        echo "     sudo dd if=$WORK_DIR/out/$DEVICE_CODENAME/marathon-$DEVICE_CODENAME.img of=/dev/sdX bs=4M status=progress"
        echo "     sync"
        ;;
    *)
        echo "Flash method: $FLASH_METHOD"
        echo "Refer to device documentation for flashing instructions."
        ;;
esac

echo ""
