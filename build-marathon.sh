#!/bin/bash
# Marathon OS Build Script for OnePlus 6 (enchilada)
# Complete Marathon OS: PREEMPT_RT kernel + optimizations + Marathon Shell

set -e

DEVICE="oneplus-enchilada"
PASSWORD="${1:-147147}"

echo "=== Marathon OS Builder ==="
echo "Device: $DEVICE"
echo ""

# Copy packages to pmaports
echo "1. Copying Marathon packages to pmaports..."
mkdir -p ~/.local/var/pmbootstrap/cache_git/pmaports/device/marathon/
cp -r packages/linux-marathon ~/.local/var/pmbootstrap/cache_git/pmaports/device/marathon/
cp -r packages/marathon-shell ~/.local/var/pmbootstrap/cache_git/pmaports/device/marathon/
cp -r packages/marathon-base-config ~/.local/var/pmbootstrap/cache_git/pmaports/device/marathon/

echo "2. Building Marathon kernel..."
pmbootstrap build linux-marathon --force

echo "3. Building Marathon Shell..."
pmbootstrap build marathon-shell --force

echo "4. Building Marathon base config..."
pmbootstrap build marathon-base-config --force

echo "5. Installing complete Marathon OS..."
pmbootstrap install \
    --add marathon-shell=1.0.0-r0 \
    --add marathon-base-config=1.0.0-r0 \
    --password "$PASSWORD"

echo "6. Exporting images..."
pmbootstrap export

echo "7. Copying images to shared folder..."
if [ -d "/mnt/utm-shared/personal" ]; then
    cp -f ~/.local/var/pmbootstrap/chroot_rootfs_${DEVICE}/boot/boot.img \
        /mnt/utm-shared/personal/boot-marathon.img
    cp -f ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/${DEVICE}.img \
        /mnt/utm-shared/personal/${DEVICE}-marathon.img
    echo "Images copied to /mnt/utm-shared/personal/"
else
    echo "Shared folder not found, images at:"
    echo "  - ~/.local/var/pmbootstrap/chroot_rootfs_${DEVICE}/boot/boot.img"
    echo "  - ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/${DEVICE}.img"
fi

echo ""
echo "=== BUILD COMPLETE ==="
echo ""
echo "Flash with:"
echo "  fastboot erase userdata"
echo "  fastboot flash boot boot-marathon.img"
echo "  fastboot flash userdata ${DEVICE}-marathon.img"
echo "  fastboot reboot"






