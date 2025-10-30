#!/bin/bash
set -e

echo "════════════════════════════════════════════════════════════════════════════"
echo "Building Marathon Shell in Alpine chroot with cross-compile from host"
echo "════════════════════════════════════════════════════════════════════════════"

cd /home/patrickquinn/Developer/Marathon-Shell

# Use distcc or cross-compile approach
# Build the C++ sources on host with musl cross-compiler, then package in Alpine

echo "This approach won't work - Alpine uses musl, Fedora uses glibc"
echo "We need to either:"
echo "1. Increase swap space in the chroot"
echo "2. Use a cross-compiler for aarch64-alpine-linux-musl"
echo "3. Build on a machine with more RAM"
echo ""
echo "Attempting option 1: Increase swap..."

# Try to add swap to the chroot
sudo dd if=/dev/zero of=/home/patrickquinn/.local/var/pmbootstrap/chroot_native/swapfile bs=1M count=4096
sudo chmod 600 /home/patrickquinn/.local/var/pmbootstrap/chroot_native/swapfile
sudo mkswap /home/patrickquinn/.local/var/pmbootstrap/chroot_native/swapfile
sudo swapon /home/patrickquinn/.local/var/pmbootstrap/chroot_native/swapfile

echo "Swap added. Now rebuilding..."
cd /home/patrickquinn/Developer/Marathon-Image
pmbootstrap build marathon-shell --force

