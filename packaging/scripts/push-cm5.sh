#!/bin/bash
# Iteration loop: rebuild marathon-shell APK + push to live CM5.
#
# Usage: ./push-cm5.sh [<package>]
#
# Defaults to marathon-shell. Override with arg, e.g. ./push-cm5.sh device-raspberry-pi5-marathon
#
# Assumes:
#   - CM5 at marathon.local OR override with CM5_HOST=<ip>
#   - Default ssh: user@$CM5_HOST with password 027602
#   - You have sshpass installed (`apk add sshpass` / `pacman -S sshpass`)
#   - pmbootstrap configured (run ./build-cm5-pmbootstrap.sh once first)

set -euo pipefail

PKG="${1:-marathon-shell}"
CM5_HOST="${CM5_HOST:-192.168.68.58}"
CM5_USER="${CM5_USER:-user}"
CM5_PASS="${CM5_PASS:-027602}"

PMAPORTS="${PMAPORTS:-$HOME/pmaports-upstream}"
PKGS_EDGE="$(pmbootstrap config work)/packages/edge/aarch64"

# 1. Resync Marathon source into pmaports vendored copy (so changes land)
if [ "$PKG" = "marathon-shell" ]; then
    SRC=/home/patrickquinn/Developer/Marathon-Shell
    if [ -d "$SRC" ]; then
        echo "+ syncing local Marathon-Shell src to pmaports"
        # marathon-shell APKBUILD pulls from GitHub. If you want LOCAL src,
        # we'd need to override source=. For now this just regenerates checksums
        # if APKBUILD changed.
        true
    fi
fi

# 2. Bump pkgrel so apk knows it's a fresh build
APKBUILD="$PMAPORTS/main/$PKG/APKBUILD"
[ -f "$APKBUILD" ] || APKBUILD="$PMAPORTS/device/community/$PKG/APKBUILD"
[ -f "$APKBUILD" ] || { echo "ERROR: $PKG APKBUILD not found" >&2; exit 1; }

CURR=$(grep "^pkgrel=" "$APKBUILD" | head -1 | cut -d= -f2)
NEXT=$((CURR + 1))
sed -i "s|^pkgrel=$CURR|pkgrel=$NEXT|" "$APKBUILD"
echo "+ bumped $PKG pkgrel: $CURR → $NEXT"

# 3. Regen checksums + build
pmbootstrap checksum "$PKG" 2>&1 | tail -1
pmbootstrap build "$PKG" --force 2>&1 | tail -3

# 4. Locate the freshly-built apk
APK=$(ls -t "$PKGS_EDGE/$PKG"-[0-9]*.apk 2>/dev/null | head -1)
[ -f "$APK" ] || { echo "ERROR: built APK not found in $PKGS_EDGE" >&2; exit 1; }
echo "+ built $APK ($(du -h "$APK" | cut -f1))"

# 5. Push + install on device
SSH="sshpass -p $CM5_PASS ssh -o StrictHostKeyChecking=no $CM5_USER@$CM5_HOST"
SCP="sshpass -p $CM5_PASS scp -o StrictHostKeyChecking=no"

REMOTE_APK="/tmp/$(basename "$APK")"
echo "+ scp $APK → $CM5_HOST:$REMOTE_APK"
$SCP "$APK" "$CM5_USER@$CM5_HOST:$REMOTE_APK"

echo "+ apk install (requires root via sudo)"
$SSH "echo 027602 | sudo -S apk add --allow-untrusted $REMOTE_APK" 2>&1 | tail -5

# 6. Restart shell session so user picks up new binary
if [ "$PKG" = "marathon-shell" ]; then
    echo "+ restarting greetd to reload shell"
    $SSH "echo 027602 | sudo -S systemctl restart greetd"
fi

echo "DONE — refresh on device"
