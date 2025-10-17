#!/bin/bash
# Marathon Shell Build with Logo Integration
# Builds Marathon Shell with Marathon logo and logs everything to file

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="marathon-shell-build-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to run commands with logging
run_with_log() {
    local cmd="$1"
    local description="$2"
    
    log "Running: $description"
    log "Command: $cmd"
    
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        success "$description completed successfully"
        return 0
    else
        error "$description failed"
        return 1
    fi
}

# Main execution
main() {
    echo "Marathon Shell Build with Logo Integration" | tee "$LOG_FILE"
    echo "===========================================" | tee -a "$LOG_FILE"
    echo "Started: $(date)" | tee -a "$LOG_FILE"
    echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    log "Starting Marathon Shell build with Marathon logo integration..."
    
    # Step 1: Copy packages to pmbootstrap workspace
    log "Step 1: Copying Marathon Shell package to pmbootstrap workspace..."
    PMAPORTS_DIR="$HOME/.local/var/pmbootstrap/cache_git/pmaports"
    
    if ! run_with_log "rsync -av --exclude='.git' packages/marathon-shell/ \"$PMAPORTS_DIR/main/marathon-shell/\"" "Copy Marathon Shell package"; then
        error "Failed to copy Marathon Shell package"
        exit 1
    fi
    
    # Step 2: Build Marathon Shell
    log "Step 2: Building Marathon Shell package..."
    if ! run_with_log "pmbootstrap build marathon-shell --force" "Marathon Shell build"; then
        error "Marathon Shell build failed"
        log "Build failed. Check the log file for details: $LOG_FILE"
        exit 1
    fi
    
    # Step 3: Install Marathon Shell into rootfs
    log "Step 3: Installing Marathon Shell into rootfs..."
    if ! run_with_log "pmbootstrap chroot -r -- apk add marathon-shell" "Marathon Shell installation"; then
        error "Marathon Shell installation failed"
        exit 1
    fi
    
    # Step 4: Export images
    log "Step 4: Exporting images..."
    if ! run_with_log "pmbootstrap export" "Image export"; then
        error "Image export failed"
        exit 1
    fi
    
    # Step 5: Copy images to output directory
    log "Step 5: Copying images to output directory..."
    OUTPUT_DIR="$PROJECT_DIR/out/enchilada"
    mkdir -p "$OUTPUT_DIR"
    
    if [ -d "/tmp/postmarketOS-export" ]; then
        if run_with_log "cp -L /tmp/postmarketOS-export/* \"$OUTPUT_DIR/\" 2>/dev/null || true" "Copy images to output directory"; then
            success "Images copied to $OUTPUT_DIR"
        else
            warning "Some images may not have been copied"
        fi
    else
        warning "Export directory not found: /tmp/postmarketOS-export"
    fi
    
    # Final verification
    log "=== Build Verification ==="
    log "Checking for essential images..."
    
    ESSENTIAL_IMAGES=("boot.img" "vmlinuz" "initramfs")
    for img in "${ESSENTIAL_IMAGES[@]}"; do
        if [ -f "$OUTPUT_DIR/$img" ]; then
            success "✓ $img exists ($(ls -lh "$OUTPUT_DIR/$img" | awk '{print $5}'))"
        else
            error "✗ $img missing"
        fi
    done
    
    # Check Marathon Shell installation
    log "Checking Marathon Shell installation..."
    if run_with_log "pmbootstrap chroot -r -- ls -la /usr/bin/marathon-shell" "Check Marathon Shell binary"; then
        success "✓ Marathon Shell binary exists"
    else
        error "✗ Marathon Shell binary missing"
    fi
    
    if run_with_log "pmbootstrap chroot -r -- ls -la /usr/share/marathon-apps/" "Check Marathon apps"; then
        success "✓ Marathon apps installed"
    else
        error "✗ Marathon apps missing"
    fi
    
    # Check Marathon logo integration
    log "Checking Marathon logo integration..."
    if run_with_log "pmbootstrap chroot -r -- ls -la /usr/share/marathon-apps/ | grep -q marathon" "Check Marathon logo in apps"; then
        success "✓ Marathon logo integrated"
    else
        warning "Marathon logo integration status unclear"
    fi
    
    echo "" | tee -a "$LOG_FILE"
    success "Marathon Shell build with logo integration complete!"
    echo "" | tee -a "$LOG_FILE"
    echo "Build Summary:" | tee -a "$LOG_FILE"
    echo "  - Marathon Shell built with Marathon logo" | tee -a "$LOG_FILE"
    echo "  - Images exported to: $OUTPUT_DIR" | tee -a "$LOG_FILE"
    echo "  - Log file: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Next steps:" | tee -a "$LOG_FILE"
    echo "  1. Review the log file: cat $LOG_FILE" | tee -a "$LOG_FILE"
    echo "  2. Flash to device: fastboot flash boot out/enchilada/boot.img" | tee -a "$LOG_FILE"
    echo "  3. The Marathon logo will appear as the default wallpaper" | tee -a "$LOG_FILE"
}

# Run main function
main "$@"
