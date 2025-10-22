#!/bin/bash
# Marathon OS - Sync Latest Marathon Shell from GitHub and Build
# Pulls latest Marathon Shell code and rebuilds images

set -e

DEVICE="oneplus-enchilada"
MARATHON_SHELL_DIR="/home/patrickquinn/Developer/Marathon-Shell"
MARATHON_IMAGE_DIR="/home/patrickquinn/Developer/Marathon-Image"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     MARATHON OS - SYNC & BUILD FROM LATEST GITHUB CODE      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Timestamp: $TIMESTAMP"
echo ""

# Step 1: Sync Marathon Shell from GitHub
echo "═══ STEP 1: Syncing Marathon Shell from GitHub ═══"
echo ""

if [ ! -d "$MARATHON_SHELL_DIR" ]; then
    echo "❌ Marathon Shell directory not found: $MARATHON_SHELL_DIR"
    echo "   Cloning from GitHub..."
    cd "$(dirname "$MARATHON_SHELL_DIR")"
    git clone https://github.com/patrickjquinn/Marathon-Shell.git
    cd "$MARATHON_SHELL_DIR"
else
    cd "$MARATHON_SHELL_DIR"
    echo "📥 Pulling latest changes from GitHub..."
    
    # Stash any local changes
    if ! git diff-index --quiet HEAD --; then
        echo "⚠️  Local changes detected, stashing..."
        git stash
    fi
    
    # Pull latest
    git fetch origin
    git pull origin main || git pull origin master
    
    echo "✅ Marathon Shell synced to latest commit:"
    git log -1 --oneline
fi

echo ""

# Step 2: Create fresh tarball for Marathon Shell
echo "═══ STEP 2: Creating Marathon Shell Source Tarball ═══"
echo ""

cd "$MARATHON_SHELL_DIR"

# Clean build artifacts
echo "Cleaning build artifacts..."
rm -rf build build-apps .cache

# Create tarball
echo "Creating tarball..."
cd ..
tar czf "$MARATHON_IMAGE_DIR/packages/marathon-shell/marathon-shell-1.0.0.tar.gz" \
    --exclude='.git' \
    --exclude='build*' \
    --exclude='.cache' \
    --exclude='*.o' \
    --exclude='*.so' \
    --exclude='moc_*' \
    --exclude='qrc_*' \
    --transform 's,^Marathon-Shell,marathon-shell-1.0.0,' \
    Marathon-Shell/

TARBALL_SIZE=$(ls -lh "$MARATHON_IMAGE_DIR/packages/marathon-shell/marathon-shell-1.0.0.tar.gz" | awk '{print $5}')
echo "✅ Tarball created: $TARBALL_SIZE"

# Update checksums
echo ""
echo "Updating package checksums..."
cd "$MARATHON_IMAGE_DIR/packages/marathon-shell"
pmbootstrap checksum marathon-shell

echo "✅ Checksums updated"
echo ""

# Step 3: Build Marathon Shell package
echo "═══ STEP 3: Building Marathon Shell Package ═══"
echo ""

cd "$MARATHON_IMAGE_DIR"

# Copy to pmaports
PMAPORTS_DIR=~/.local/var/pmbootstrap/cache_git/pmaports
mkdir -p "$PMAPORTS_DIR/device/marathon/"
rm -rf "$PMAPORTS_DIR/device/marathon/marathon-shell"
cp -r packages/marathon-shell "$PMAPORTS_DIR/device/marathon/"

echo "Building marathon-shell..."
pmbootstrap build marathon-shell --force

echo "✅ Marathon Shell built"
echo ""

# Step 4: Install in rootfs
echo "═══ STEP 4: Installing Marathon Shell ═══"
echo ""

echo "Installing marathon-shell in rootfs..."
pmbootstrap chroot --suffix rootfs -- apk add --force-reinstall marathon-shell

echo "✅ Marathon Shell installed"
echo ""

# Step 5: Verify installation
echo "═══ STEP 5: Verifying Installation ═══"
echo ""

echo "Checking Marathon Shell binary..."
pmbootstrap chroot --suffix rootfs -- ls -lh /usr/bin/marathon-shell-bin | awk '{print "   " $0}'

echo ""
echo "Checking QML modules..."
pmbootstrap chroot --suffix rootfs -- ls /usr/lib/qt6/qml/MarathonUI/ 2>/dev/null | head -8

echo ""
echo "✅ Installation verified"
echo ""

# Step 6: Export images
echo "═══ STEP 6: Exporting Images ═══"
echo ""

pmbootstrap export

echo "✅ Images exported"
echo ""

# Step 7: Copy to out directory
echo "═══ STEP 7: Copying Images ═══"
echo ""

mkdir -p out/enchilada

BOOT_SRC=~/.local/var/pmbootstrap/chroot_rootfs_${DEVICE}/boot/boot.img
ROOT_SRC=~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/${DEVICE}.img

cp "$BOOT_SRC" "out/enchilada/boot-MARATHON-SYNCED-${TIMESTAMP}.img"
cp "$ROOT_SRC" "out/enchilada/oneplus-enchilada-MARATHON-SYNCED-${TIMESTAMP}.img"

BOOT_SIZE=$(ls -lh "out/enchilada/boot-MARATHON-SYNCED-${TIMESTAMP}.img" | awk '{print $5}')
ROOT_SIZE=$(ls -lh "out/enchilada/oneplus-enchilada-MARATHON-SYNCED-${TIMESTAMP}.img" | awk '{print $5}')

echo "✅ Boot image: $BOOT_SIZE"
echo "✅ Root image: $ROOT_SIZE"

# Update LATEST symlinks
cd out/enchilada
ln -sf "boot-MARATHON-SYNCED-${TIMESTAMP}.img" "boot-MARATHON-LATEST.img"
ln -sf "oneplus-enchilada-MARATHON-SYNCED-${TIMESTAMP}.img" "oneplus-enchilada-MARATHON-LATEST.img"
cd ../..

echo ""

# Step 8: Copy to shared folder
if [ -d "$HOME/Developer/personal" ]; then
    echo "═══ STEP 8: Copying to Shared Folder ═══"
    echo ""
    
    cp "out/enchilada/boot-MARATHON-SYNCED-${TIMESTAMP}.img" "$HOME/Developer/personal/"
    cp "out/enchilada/oneplus-enchilada-MARATHON-SYNCED-${TIMESTAMP}.img" "$HOME/Developer/personal/"
    
    cd "$HOME/Developer/personal"
    ln -sf "boot-MARATHON-SYNCED-${TIMESTAMP}.img" "boot-MARATHON-LATEST.img"
    ln -sf "oneplus-enchilada-MARATHON-SYNCED-${TIMESTAMP}.img" "oneplus-enchilada-MARATHON-LATEST.img"
    cd -
    
    echo "✅ Images copied to $HOME/Developer/personal/"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ✅ SYNC & BUILD COMPLETE ✅                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📦 Images with Latest Marathon Shell:"
echo "   Boot:  out/enchilada/boot-MARATHON-SYNCED-${TIMESTAMP}.img ($BOOT_SIZE)"
echo "   Root:  out/enchilada/oneplus-enchilada-MARATHON-SYNCED-${TIMESTAMP}.img ($ROOT_SIZE)"
echo ""
echo "🔗 Latest Symlinks:"
echo "   out/enchilada/boot-MARATHON-LATEST.img"
echo "   out/enchilada/oneplus-enchilada-MARATHON-LATEST.img"
echo ""
echo "📝 Marathon Shell Info:"
cd "$MARATHON_SHELL_DIR"
echo "   Commit: $(git log -1 --oneline)"
echo "   Branch: $(git branch --show-current)"
cd "$MARATHON_IMAGE_DIR"
echo ""
echo "🚀 Flash Commands:"
echo "   fastboot flash boot out/enchilada/boot-MARATHON-LATEST.img"
echo "   fastboot flash userdata out/enchilada/oneplus-enchilada-MARATHON-LATEST.img"
echo "   fastboot reboot"
echo ""
echo "🎉 Ready to flash!"
echo ""

