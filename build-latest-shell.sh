#!/bin/bash
set -e

cd /home/patrickquinn/Developer/Marathon-Image

echo "Starting Marathon Shell build with memory optimizations..."
echo "This will take 5-10 minutes..."

pmbootstrap build marathon-shell --force 2>&1 | tee marathon-final-build.log

if [ $? -eq 0 ]; then
    echo "✅ BUILD SUCCESSFUL!"
    echo "Installing and exporting images..."
    pmbootstrap install --no-fde --password 147147
    pmbootstrap export
    cp -L /home/patrickquinn/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/oneplus-enchilada.img /mnt/utm-shared/personal/
    cp -L /home/patrickquinn/.local/var/pmbootstrap/chroot_rootfs_oneplus-enchilada/boot/boot.img /mnt/utm-shared/personal/
    echo "✅ IMAGES READY IN /mnt/utm-shared/personal/"
    ls -lh /mnt/utm-shared/personal/*.img
else
    echo "❌ BUILD FAILED - Check marathon-final-build.log"
    tail -100 marathon-final-build.log
fi

