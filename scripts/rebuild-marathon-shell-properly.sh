#!/bin/bash
# Properly Rebuild Marathon Shell Script
# This fixes Marathon Shell package building

set -e

WORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$WORK_DIR/marathon-shell-rebuild-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Marathon Shell Proper Rebuild Started ==="
log "Working directory: $WORK_DIR"

# Clean up
log "Step 1: Cleaning up existing pmbootstrap processes..."
pmbootstrap shutdown || true
sleep 2

# Copy fixed APKBUILD
log "Step 2: Copying fixed Marathon Shell package..."
PMAPORTS_DIR="$HOME/.local/var/pmbootstrap/cache_git/pmaports"
rm -rf "$PMAPORTS_DIR/main/marathon-shell"
cp -r "$WORK_DIR/packages/marathon-shell" "$PMAPORTS_DIR/main/"
log "✓ Marathon Shell package copied"

# The key: pmbootstrap needs to build from the package directory
# We can't use checksums with local directory sources in APKBUILD
log "Step 3: Building Marathon Shell without checksum validation..."

# Build with --force and --no-check
if pmbootstrap build marathon-shell --force 2>&1 | tee -a "$LOG_FILE"; then
    log "✓ Marathon Shell built successfully"
else
    log "ERROR: Marathon Shell build failed"
    log "Checking detailed error..."
    tail -100 "$HOME/.local/var/pmbootstrap/log.txt" | tee -a "$LOG_FILE"
    exit 1
fi

# Install the system
log "Step 4: Installing system with new Marathon Shell..."
if pmbootstrap install --password '147147' --add linux-marathon-enchilada,marathon-base-config,marathon-shell,greetd,greetd-agreety --split --filesystem ext4 2>&1 | tee -a "$LOG_FILE"; then
    log "✓ System installed successfully"
else
    log "ERROR: System installation failed"
    exit 1
fi

# Export images
log "Step 5: Exporting images..."
if pmbootstrap export 2>&1 | tee -a "$LOG_FILE"; then
    log "✓ Images exported successfully"
else
    log "ERROR: Image export failed"
    exit 1
fi

# Copy to output
log "Step 6: Copying images to output directory..."
OUTPUT_DIR="$WORK_DIR/out/enchilada"
mkdir -p "$OUTPUT_DIR"
EXPORT_DIR="/tmp/postmarketOS-export"
if [ -d "$EXPORT_DIR" ]; then
    cp -L "$EXPORT_DIR"/* "$OUTPUT_DIR/" 2>/dev/null || true
    log "✓ Images copied to $OUTPUT_DIR"
else
    log "WARNING: Export directory not found"
fi

# Verify
log "=== Verification ==="
ROOTFS_DIR="$HOME/.local/var/pmbootstrap/chroot_rootfs_oneplus-enchilada"
if [ -f "$ROOTFS_DIR/usr/bin/marathon-shell" ]; then
    log "✓ Marathon Shell binary found"
else
    log "✗ Marathon Shell binary missing"
fi

if [ -d "$ROOTFS_DIR/usr/local/share/marathon-apps" ]; then
    log "✓ Marathon apps directory found"
    ls -la "$ROOTFS_DIR/usr/local/share/marathon-apps/" | tee -a "$LOG_FILE"
else
    log "✗ Marathon apps directory missing"
fi

log "=== Marathon Shell Rebuild Complete ==="
log "Log file: $LOG_FILE"
