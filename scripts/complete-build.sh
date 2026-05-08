#!/bin/bash
# Complete Marathon OS Build - Updates checksums and builds image
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "+------------------------------------------------------------+"
echo "|          MARATHON OS - COMPLETE BUILD WORKFLOW              |"
echo "+------------------------------------------------------------+"
echo ""

# Step 1: Update checksums
echo "═══ STEP 1: Updating checksums ═══"
echo "Copying latest package definition to pmaports..."

# Copy to pmaports (same logic as sync-and-build-marathon.sh)
PMAPORTS_DIR="$(pmbootstrap config aports)"

# Keep checksums workflow as-is, but ensure the package exists in only one place.
mkdir -p "$PMAPORTS_DIR/main"
rm -rf "$PMAPORTS_DIR/device/marathon/marathon-shell"
rm -rf "$PMAPORTS_DIR/main/marathon-shell"
cp -r packages/marathon-shell "$PMAPORTS_DIR/main/"

echo "This will ask for your sudo password..."
echo ""
pmbootstrap checksum marathon-shell

echo ""
echo "Checksums updated"
echo "Syncing updated APKBUILD back to local packages..."
cp "$PMAPORTS_DIR/device/marathon/marathon-shell/APKBUILD" "packages/marathon-shell/APKBUILD"
echo ""

# Step 2: Run the build
echo "═══ STEP 2: Building Marathon OS ═══"
echo ""
# Default device
DEVICE="${1:-oneplus-enchilada}"

./scripts/sync-and-build-marathon.sh "$DEVICE"

echo ""
echo "+------------------------------------------------------------+"
echo "|                 BUILD COMPLETE                        |"
echo "+------------------------------------------------------------+"
