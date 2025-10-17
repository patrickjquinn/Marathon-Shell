#!/bin/bash
# Marathon OS Build Script with Comprehensive Logging
# This script builds Marathon OS and logs everything to a detailed log file

set -e

# Configuration
WORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$WORK_DIR/marathon-build-$(date +%Y%m%d-%H%M%S).log"
DEVICE="enchilada"

echo "=== Marathon OS Build with Full Logging ==="
echo "Working directory: $WORK_DIR"
echo "Log file: $LOG_FILE"
echo "Device: $DEVICE"
echo ""

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to run command with logging
run_with_log() {
    local cmd="$1"
    local description="$2"
    
    log "Starting: $description"
    log "Command: $cmd"
    
    if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS: $description"
        return 0
    else
        local exit_code=$?
        log "ERROR: $description failed with exit code $exit_code"
        return $exit_code
    fi
}

# Start logging
log "=== Marathon OS Build Started ==="
log "Build timestamp: $(date)"
log "Working directory: $WORK_DIR"
log "Device: $DEVICE"
log "User: $(whoami)"
log "Hostname: $(hostname)"
log ""

# Check prerequisites
log "=== Checking Prerequisites ==="

# Check if pmbootstrap is installed
if ! command -v pmbootstrap >/dev/null 2>&1; then
    log "ERROR: pmbootstrap not found. Please install it first."
    log "Install with: sudo dnf install -y pmbootstrap"
    exit 1
fi
log "✓ pmbootstrap found: $(pmbootstrap --version 2>&1 | head -1)"

# Check if git is installed
if ! command -v git >/dev/null 2>&1; then
    log "ERROR: git not found. Please install it first."
    exit 1
fi
log "✓ git found: $(git --version)"

# Check if fastboot is installed
if ! command -v fastboot >/dev/null 2>&1; then
    log "WARNING: fastboot not found. Install with: sudo dnf install -y android-tools"
else
    log "✓ fastboot found: $(fastboot --version 2>&1 | head -1)"
fi

# Check available disk space
log "=== System Resources ==="
log "Available disk space:"
df -h | tee -a "$LOG_FILE"
log ""
log "Memory usage:"
free -h | tee -a "$LOG_FILE"
log ""

# Check if pmbootstrap is initialized
log "=== Checking pmbootstrap Configuration ==="
if [ ! -d "$HOME/.local/var/pmbootstrap" ]; then
    log "ERROR: pmbootstrap not initialized. Run 'pmbootstrap init' first."
    exit 1
fi
log "✓ pmbootstrap directory exists"

# Check pmbootstrap status
log "pmbootstrap status:"
pmbootstrap status 2>&1 | tee -a "$LOG_FILE"
log ""

# Clean up any existing processes
log "=== Cleaning Up Existing Processes ==="
if pgrep -f "pmbootstrap" > /dev/null; then
    log "Shutting down existing pmbootstrap processes..."
    pmbootstrap shutdown 2>&1 | tee -a "$LOG_FILE"
    sleep 3
fi
log "✓ Cleanup completed"
log ""

# Start the build process
log "=== Starting Marathon OS Build Process ==="

# Step 1: Copy package sources
log "Step 1: Copying package sources to pmbootstrap workspace..."
PMAPORTS_DIR="$HOME/.local/var/pmbootstrap/cache_git/pmaports"

if [ ! -d "$PMAPORTS_DIR" ]; then
    log "ERROR: pmaports directory not found: $PMAPORTS_DIR"
    exit 1
fi

# Copy marathon-base-config
log "Copying marathon-base-config..."
if [ -d "$WORK_DIR/packages/marathon-base-config" ]; then
    rm -rf "$PMAPORTS_DIR/main/marathon-base-config"
    cp -r "$WORK_DIR/packages/marathon-base-config" "$PMAPORTS_DIR/main/"
    log "✓ marathon-base-config copied"
else
    log "ERROR: marathon-base-config directory not found"
    exit 1
fi

# Copy marathon-shell
log "Copying marathon-shell..."
if [ -d "$WORK_DIR/packages/marathon-shell" ]; then
    rm -rf "$PMAPORTS_DIR/main/marathon-shell"
    cp -r "$WORK_DIR/packages/marathon-shell" "$PMAPORTS_DIR/main/"
    log "✓ marathon-shell copied"
else
    log "ERROR: marathon-shell directory not found"
    exit 1
fi

# Copy kernel package
log "Copying kernel package..."
mkdir -p "$PMAPORTS_DIR/device/marathon"
rm -rf "$PMAPORTS_DIR/device/marathon/linux-marathon-enchilada"
cp -r "$WORK_DIR/packages/linux-marathon" "$PMAPORTS_DIR/device/marathon/linux-marathon-enchilada"
log "✓ kernel package copied"

log ""

# Step 2: Build custom kernel
log "Step 2: Building custom kernel..."
if ! run_with_log "pmbootstrap build linux-marathon-enchilada --force" "Kernel build"; then
    log "ERROR: Kernel build failed"
    exit 1
fi

log ""

# Step 3: Build base configuration
log "Step 3: Building marathon-base-config..."
if ! run_with_log "pmbootstrap build marathon-base-config --force" "Base config build"; then
    log "ERROR: Base config build failed"
    exit 1
fi

log ""

# Step 4: Build Marathon Shell
log "Step 4: Building marathon-shell..."
if ! run_with_log "pmbootstrap build marathon-shell --force" "Marathon Shell build"; then
    log "ERROR: Marathon Shell build failed"
    exit 1
fi

log ""

# Step 5: Install complete system
log "Step 5: Installing complete system..."
if ! run_with_log "pmbootstrap install --password '147147' --add linux-marathon-enchilada,marathon-base-config,marathon-shell,greetd,greetd-agreety --split --filesystem ext4" "System installation"; then
    log "ERROR: System installation failed"
    exit 1
fi

log ""

# Step 6: Export images
log "Step 6: Exporting images..."
if ! run_with_log "pmbootstrap export" "Image export"; then
    log "ERROR: Image export failed"
    exit 1
fi

log ""

# Step 7: Copy images to output directory
log "Step 7: Copying images to output directory..."
OUTPUT_DIR="$WORK_DIR/out/$DEVICE"
mkdir -p "$OUTPUT_DIR"

EXPORT_DIR="/tmp/postmarketOS-export"
if [ -d "$EXPORT_DIR" ]; then
    cp -L "$EXPORT_DIR"/* "$OUTPUT_DIR/" 2>/dev/null || true
    log "✓ Images copied to $OUTPUT_DIR"
    
    # List generated images
    log "Generated images:"
    ls -lah "$OUTPUT_DIR" | tee -a "$LOG_FILE"
else
    log "WARNING: Export directory not found: $EXPORT_DIR"
fi

log ""

# Final verification
log "=== Build Verification ==="
log "Checking for essential images..."

ESSENTIAL_IMAGES=("boot.img" "vmlinuz" "initramfs" "oneplus-enchilada-boot.img" "oneplus-enchilada-root.img")
MISSING_IMAGES=()

for image in "${ESSENTIAL_IMAGES[@]}"; do
    if [ -f "$OUTPUT_DIR/$image" ] || [ -L "$OUTPUT_DIR/$image" ]; then
        log "✓ Found: $image"
    else
        log "✗ Missing: $image"
        MISSING_IMAGES+=("$image")
    fi
done

if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
    log "WARNING: Missing essential images: ${MISSING_IMAGES[*]}"
else
    log "✓ All essential images found"
fi

log ""

# Build summary
log "=== Build Summary ==="
log "Build completed at: $(date)"
log "Log file: $LOG_FILE"
log "Output directory: $OUTPUT_DIR"
log ""

if [ ${#MISSING_IMAGES[@]} -eq 0 ]; then
    log "✅ BUILD SUCCESSFUL - All images generated successfully"
    log ""
    log "To flash to device:"
    log "  fastboot flash boot $OUTPUT_DIR/boot.img"
    log "  fastboot flash system $OUTPUT_DIR/oneplus-enchilada-root.img"
    log "  fastboot reboot"
else
    log "❌ BUILD INCOMPLETE - Some images missing"
    log "Missing images: ${MISSING_IMAGES[*]}"
fi

log ""
log "=== Marathon OS Build Completed ==="
log "Total build time: $(date)"
log "Log file location: $LOG_FILE"
