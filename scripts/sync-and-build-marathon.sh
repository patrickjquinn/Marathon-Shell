#!/bin/bash
# Marathon OS - Sync Latest Marathon Shell from GitHub and Build
# Pulls latest Marathon Shell code and rebuilds images

set -e

DEVICE="${1:-oneplus-enchilada}"
# Marathon Shell source repo (kept in sync with packages/marathon-shell/APKBUILD)
MARATHON_SHELL_REPO_URL="${MARATHON_SHELL_REPO_URL:-https://github.com/patrickjquinn/Marathon-Shell.git}"
# Optional fallback repo (older org naming)
MARATHON_SHELL_REPO_FALLBACK_URL="${MARATHON_SHELL_REPO_FALLBACK_URL:-https://github.com/MarathonOS/Marathon-Shell.git}"
# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Assume script is in scripts/ subdirectory
MARATHON_IMAGE_DIR="$(dirname "$SCRIPT_DIR")"
# Use a dedicated build directory for the source code to avoid touching user's dev workspace
MARATHON_SHELL_DIR="$MARATHON_IMAGE_DIR/build/marathon-shell-source"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "+------------------------------------------------------------+"
echo "|     MARATHON OS - SYNC & BUILD FROM LATEST GITHUB CODE      |"
echo "+------------------------------------------------------------+"
echo ""
echo "Device: $DEVICE"
echo "Timestamp: $TIMESTAMP"
echo ""

# Keep sudo alive for long builds (pmbootstrap uses sudo frequently).
# This avoids failing mid-build when the sudo timestamp expires.
if command -v sudo >/dev/null 2>&1; then
    echo "═══ SUDO: Validating credentials (may prompt once) ═══"
    sudo -v
    # Keep-alive: refresh sudo timestamp every 60s until script exits
    ( while true; do sudo -n true; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
    echo ""
fi

# Keep pmaports in sync (helps avoid dependency/version drift like the polkit warning).
# NOTE: We re-copy our local ports into pmaports after this, so our changes persist.
echo "═══ STEP 0: Updating pmaports (pmbootstrap pull) ═══"
PMAPORTS_DIR="$(pmbootstrap config aports)"
if [ -d "$PMAPORTS_DIR/.git" ]; then
    echo "Cleaning local pmaports modifications (required for pmbootstrap pull)..."
    # Drop any local changes/untracked ports we copied in previous runs.
    git -C "$PMAPORTS_DIR" reset --hard >/dev/null
    git -C "$PMAPORTS_DIR" clean -fd >/dev/null
fi
pmbootstrap pull || true
echo ""

# Step 1: Sync Marathon Shell from GitHub
echo "═══ STEP 1: Syncing Marathon Shell from GitHub ═══"
echo ""

if [ ! -d "$MARATHON_SHELL_DIR" ]; then
    echo "Marathon Shell directory not found: $MARATHON_SHELL_DIR"
    echo "   Cloning from GitHub..."
    mkdir -p "$(dirname "$MARATHON_SHELL_DIR")"
    git clone "$MARATHON_SHELL_REPO_URL" "$MARATHON_SHELL_DIR" || \
        git clone "$MARATHON_SHELL_REPO_FALLBACK_URL" "$MARATHON_SHELL_DIR"
    cd "$MARATHON_SHELL_DIR"
else
    cd "$MARATHON_SHELL_DIR"
    echo "Pulling latest changes from GitHub..."
    
    # Stash any local changes
    if ! git diff-index --quiet HEAD --; then
        echo " Local changes detected, stashing..."
        git stash
    fi
    
    # Pull latest
    git fetch origin
    git pull origin main || git pull origin master
    
    echo "Marathon Shell synced to latest commit:"
    git log -1 --oneline
fi

echo ""

# Step 2: APKBUILD now pulls directly from GitHub - no tarball needed
echo "═══ STEP 2: APKBUILD configured to pull from GitHub ═══"
echo "Marathon Shell will be fetched directly from GitHub during build"
echo ""

# Step 3: Build Marathon Shell package
echo "═══ STEP 3: Building Marathon Shell Package ═══"
echo ""

cd "$MARATHON_IMAGE_DIR"

# Copy to pmaports (place packages in standard locations)
PMAPORTS_DIR="$(pmbootstrap config aports)"
mkdir -p "$PMAPORTS_DIR/main" "$PMAPORTS_DIR/device/main"

# Cleanup legacy location from older versions of this script (avoid "found in multiple aports subfolders")
rm -rf "$PMAPORTS_DIR/device/marathon/marathon-shell"

# main/
rm -rf "$PMAPORTS_DIR/main/marathon-shell" \
       "$PMAPORTS_DIR/main/marathon-base-config" \
       "$PMAPORTS_DIR/main/marathon-boot-logo"
cp -r packages/marathon-shell "$PMAPORTS_DIR/main/"
cp -r packages/marathon-base-config "$PMAPORTS_DIR/main/"
cp -r packages/marathon-boot-logo "$PMAPORTS_DIR/main/"

# device/main/
rm -rf "$PMAPORTS_DIR/device/main/linux-marathon" \
       "$PMAPORTS_DIR/device/main/device-oneplus-enchilada-marathon"
cp -r packages/linux-marathon "$PMAPORTS_DIR/device/main/"
cp -r packages/device-oneplus-enchilada-marathon "$PMAPORTS_DIR/device/main/"

echo "Refreshing checksums for marathon-shell (source tarballs track moving branches)..."
# Clear distfiles so we don't accidentally reuse cached tarballs (always build latest).
PMBOOTSTRAP_WORK_DIR="$(pmbootstrap config work)"
rm -f "$PMBOOTSTRAP_WORK_DIR/cache_distfiles/"*marathon-shell* 2>/dev/null || true
rm -f "$PMBOOTSTRAP_WORK_DIR/cache_distfiles/"*asyncfuture* 2>/dev/null || true
pmbootstrap checksum marathon-shell || true
echo ""

echo "Building marathon-base-config..."
pmbootstrap build marathon-base-config

echo "Building marathon-boot-logo..."
pmbootstrap build marathon-boot-logo

echo "Building linux-marathon..."
pmbootstrap build linux-marathon

echo "Building marathon-shell..."
pmbootstrap build marathon-shell --force

echo "Marathon Shell built"
echo ""

# Step 4: Install and Generate Image
echo "═══ STEP 4: Installing and Generating Image ═══"
echo ""

echo "Running pmbootstrap install to generate system image..."

# Ensure only one kernel flavor ends up in the rootfs (mkinitfs fails otherwise).
# 1) Make sure linux-marathon APK metadata + kernel.release path is up-to-date.
PMBOOTSTRAP_WORK_DIR="$(pmbootstrap config work)"
LINUX_MARATHON_APK="$(ls -1 "$PMBOOTSTRAP_WORK_DIR"/packages/*/aarch64/linux-marathon-*.apk 2>/dev/null | sort | tail -1 || true)"
if [ -n "$LINUX_MARATHON_APK" ]; then
    NEED_REBUILD_KERNEL=0

    # Old layout: linux-marathon used to install kernel.release under /usr/share/kernel/marathon/
    if tar -tf "$LINUX_MARATHON_APK" 2>/dev/null | grep -q 'usr/share/kernel/marathon/kernel.release'; then
        NEED_REBUILD_KERNEL=1
    fi

    # Stale metadata: an older build injected a '!linux-postmarketos-qcom-sdm845' dependency which breaks rootfs install.
    if tar --warning=no-unknown-keyword -xOf "$LINUX_MARATHON_APK" .PKGINFO 2>/dev/null | grep -q '^depend = !linux-postmarketos-qcom-sdm845$'; then
        NEED_REBUILD_KERNEL=1
    fi

    if [ "$NEED_REBUILD_KERNEL" = "1" ]; then
        echo "Detected old/stale linux-marathon package metadata. Rebuilding linux-marathon..."
        pmbootstrap build linux-marathon --force
        echo ""
    fi
fi

# 2) Patch the OnePlus 6 device package dependency to use linux-marathon (instead of linux-postmarketos-qcom-sdm845).
PMAPORTS_DIR="$(pmbootstrap config aports)"
OP6_APKBUILD="$PMAPORTS_DIR/device/community/device-oneplus-enchilada/APKBUILD"
if [ -f "$OP6_APKBUILD" ]; then
    if grep -q 'linux-postmarketos-qcom-sdm845' "$OP6_APKBUILD"; then
        echo "Patching device-oneplus-enchilada to depend on linux-marathon..."
        sed -i 's/linux-postmarketos-qcom-sdm845/linux-marathon/g' "$OP6_APKBUILD"
        echo "Patched device-oneplus-enchilada (kernel -> linux-marathon)"
        echo ""

        echo "Rebuilding device-oneplus-enchilada package so the patched dependency takes effect..."
        pmbootstrap build device-oneplus-enchilada --force
        echo ""
    fi
fi

# We use --password 147147 (default) to avoid interactive prompt
# Install the Marathon meta-package for OnePlus 6 (pulls kernel + shell + config)
pmbootstrap install --zap --add device-oneplus-enchilada-marathon --password 147147

echo "System image generated"
echo ""

# Step 5: Verify installation (in the new rootfs)
echo "═══ STEP 5: Verifying Installation ═══"
echo ""

echo "Checking Marathon Shell binary..."
pmbootstrap chroot --rootfs -- ls -lh /usr/bin/marathon-shell-bin | awk '{print "   " $0}'

echo ""
echo "Checking Marathon Shell session script points at /usr (not /usr/local)..."
pmbootstrap chroot --rootfs -- sh -c 'head -n 40 /usr/bin/marathon-shell-session | sed -n "1,40p"'

echo ""
echo "Checking QML modules..."
pmbootstrap chroot --rootfs -- ls /usr/lib/qt6/qml/MarathonUI/ 2>/dev/null | head -8

echo ""
echo "Installation verified"
echo ""

# Step 6: Export images
echo "═══ STEP 6: Exporting Images ═══"
echo ""

EXPORT_DIR="/tmp/marathon-export-${TIMESTAMP}"
pmbootstrap export "$EXPORT_DIR"

echo "Images exported to $EXPORT_DIR"
echo ""

# Step 7: Copy to out directory
echo "═══ STEP 7: Copying Images ═══"
echo ""

mkdir -p "out/$DEVICE"

BOOT_SRC="$EXPORT_DIR/boot.img"
ROOT_SRC="$EXPORT_DIR/${DEVICE}.img"

if [ -f "$BOOT_SRC" ]; then
    cp "$BOOT_SRC" "out/$DEVICE/boot-MARATHON-SYNCED-${TIMESTAMP}.img"
    BOOT_SIZE=$(ls -lh "out/$DEVICE/boot-MARATHON-SYNCED-${TIMESTAMP}.img" | awk '{print $5}')
    echo "Boot image: $BOOT_SIZE"
else
    echo " Boot image not found at $BOOT_SRC"
fi

if [ -f "$ROOT_SRC" ]; then
    cp "$ROOT_SRC" "out/$DEVICE/${DEVICE}-MARATHON-SYNCED-${TIMESTAMP}.img"
    ROOT_SIZE=$(ls -lh "out/$DEVICE/${DEVICE}-MARATHON-SYNCED-${TIMESTAMP}.img" | awk '{print $5}')
    echo "Root image: $ROOT_SIZE"
else
    echo " Root image not found at $ROOT_SRC"
    # Try to list export dir to help debugging
    echo "Contents of export dir:"
    ls -l "$EXPORT_DIR"
fi

# Update LATEST symlinks
cd "out/$DEVICE"
ln -sf "boot-MARATHON-SYNCED-${TIMESTAMP}.img" "boot-MARATHON-LATEST.img"
ln -sf "${DEVICE}-MARATHON-SYNCED-${TIMESTAMP}.img" "${DEVICE}-MARATHON-LATEST.img"
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
    
    echo "Images copied to $HOME/Developer/personal/"
fi

echo ""
echo "+------------------------------------------------------------+"
echo "|             SYNC & BUILD COMPLETE                     |"
echo "+------------------------------------------------------------+"
echo ""
echo "Images with Latest Marathon Shell:"
echo "   Boot:  out/$DEVICE/boot-MARATHON-SYNCED-${TIMESTAMP}.img ($BOOT_SIZE)"
echo "   Root:  out/$DEVICE/${DEVICE}-MARATHON-SYNCED-${TIMESTAMP}.img ($ROOT_SIZE)"
echo ""
echo "Latest Symlinks:"
echo "   out/$DEVICE/boot-MARATHON-LATEST.img"
echo "   out/$DEVICE/${DEVICE}-MARATHON-LATEST.img"
echo ""
echo "Marathon Shell Info:"
cd "$MARATHON_SHELL_DIR"
echo "   Commit: $(git log -1 --oneline)"
echo "   Branch: $(git branch --show-current)"
cd "$MARATHON_IMAGE_DIR"
echo ""
echo "Flash Commands:"
echo "   fastboot flash boot out/$DEVICE/boot-MARATHON-LATEST.img"
echo "   fastboot flash userdata out/$DEVICE/${DEVICE}-MARATHON-LATEST.img"
echo "   fastboot reboot"
echo ""
echo "Ready to flash!"
echo ""
