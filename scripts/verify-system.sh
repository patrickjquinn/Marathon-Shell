#!/bin/bash
# Marathon OS System Verification Script
# Tests the system before flashing to ensure it will work

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="system-verification-$(date +%Y%m%d-%H%M%S).log"

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

# Function to test commands
test_command() {
    local cmd="$1"
    local description="$2"
    
    log "Testing: $description"
    if pmbootstrap chroot -r -- sh -c "$cmd" >> "$LOG_FILE" 2>&1; then
        success "✓ $description"
        return 0
    else
        error "✗ $description failed"
        return 1
    fi
}

# Main verification
main() {
    echo "Marathon OS System Verification" | tee "$LOG_FILE"
    echo "=================================" | tee -a "$LOG_FILE"
    echo "Started: $(date)" | tee -a "$LOG_FILE"
    echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    local errors=0
    local warnings=0
    
    log "Starting system verification..."
    
    # Test 1: Essential binaries
    log "=== Testing Essential Binaries ==="
    if test_command "which weston" "Weston compositor binary"; then
        success "Weston compositor available"
    else
        error "Weston compositor missing"
        ((errors++))
    fi
    
    if test_command "which weston-terminal" "Weston terminal"; then
        success "Weston terminal available"
    else
        warning "Weston terminal missing"
        ((warnings++))
    fi
    
    # Test 2: Marathon logo
    log "=== Testing Marathon Logo ==="
    if test_command "ls -la /usr/share/wallpapers/marathon-logo.png" "Marathon logo file"; then
        success "Marathon logo available"
    else
        error "Marathon logo missing"
        ((errors++))
    fi
    
    # Test 3: System services
    log "=== Testing System Services ==="
    if test_command "systemctl is-enabled weston" "Weston service enabled"; then
        success "Weston service enabled"
    else
        error "Weston service not enabled"
        ((errors++))
    fi
    
    if test_command "systemctl is-enabled NetworkManager" "NetworkManager enabled"; then
        success "NetworkManager enabled"
    else
        warning "NetworkManager not enabled"
        ((warnings++))
    fi
    
    # Test 4: Graphics stack
    log "=== Testing Graphics Stack ==="
    if test_command "ls -la /usr/lib/libwayland*" "Wayland libraries"; then
        success "Wayland libraries available"
    else
        error "Wayland libraries missing"
        ((errors++))
    fi
    
    if test_command "ls -la /usr/lib/libEGL*" "EGL libraries"; then
        success "EGL libraries available"
    else
        error "EGL libraries missing"
        ((errors++))
    fi
    
    # Test 5: User account
    log "=== Testing User Account ==="
    if test_command "id user" "User account exists"; then
        success "User account exists"
    else
        error "User account missing"
        ((errors++))
    fi
    
    # Test 6: Boot configuration
    log "=== Testing Boot Configuration ==="
    if test_command "ls -la /boot/vmlinuz*" "Kernel image"; then
        success "Kernel image available"
    else
        error "Kernel image missing"
        ((errors++))
    fi
    
    if test_command "ls -la /boot/initramfs*" "Initramfs"; then
        success "Initramfs available"
    else
        error "Initramfs missing"
        ((errors++))
    fi
    
    # Test 7: Marathon optimizations
    log "=== Testing Marathon Optimizations ==="
    if test_command "ls -la /etc/sysctl.d/99-marathon.conf" "Marathon sysctl config"; then
        success "Marathon sysctl config available"
    else
        warning "Marathon sysctl config missing"
        ((warnings++))
    fi
    
    if test_command "ls -la /etc/systemd/system/pipewire.service.d/50-priority.conf" "PipeWire RT config"; then
        success "PipeWire RT config available"
    else
        warning "PipeWire RT config missing"
        ((warnings++))
    fi
    
    # Test 8: Output images
    log "=== Testing Output Images ==="
    if [ -f "$PROJECT_DIR/out/enchilada/boot.img" ]; then
        success "Boot image exists ($(ls -lh "$PROJECT_DIR/out/enchilada/boot.img" | awk '{print $5}'))"
    else
        error "Boot image missing"
        ((errors++))
    fi
    
    if [ -f "$PROJECT_DIR/out/enchilada/oneplus-enchilada-root.img" ]; then
        success "Root image exists ($(ls -lh "$PROJECT_DIR/out/enchilada/oneplus-enchilada-root.img" | awk '{print $5}'))"
    else
        error "Root image missing"
        ((errors++))
    fi
    
    # Test 9: Marathon logo files
    log "=== Testing Marathon Logo Files ==="
    if [ -f "$PROJECT_DIR/out/enchilada/marathon-boot-logo-portrait.png" ]; then
        success "Marathon boot logo (portrait) exists"
    else
        warning "Marathon boot logo (portrait) missing"
        ((warnings++))
    fi
    
    if [ -f "$PROJECT_DIR/out/enchilada/marathon-boot-logo-landscape.png" ]; then
        success "Marathon boot logo (landscape) exists"
    else
        warning "Marathon boot logo (landscape) missing"
        ((warnings++))
    fi
    
    # Final summary
    echo "" | tee -a "$LOG_FILE"
    log "=== Verification Summary ==="
    log "Errors: $errors"
    log "Warnings: $warnings"
    
    if [ $errors -eq 0 ]; then
        success "✅ System verification PASSED!"
        echo "" | tee -a "$LOG_FILE"
        echo "The system is ready for flashing!" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        echo "Flash commands:" | tee -a "$LOG_FILE"
        echo "  fastboot flash boot out/enchilada/boot.img" | tee -a "$LOG_FILE"
        echo "  fastboot flash userdata out/enchilada/oneplus-enchilada-root.img" | tee -a "$LOG_FILE"
        echo "  fastboot reboot" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        echo "Expected behavior:" | tee -a "$LOG_FILE"
        echo "  - System boots normally" | tee -a "$LOG_FILE"
        echo "  - Weston Wayland compositor starts automatically" | tee -a "$LOG_FILE"
        echo "  - Marathon logo available as wallpaper" | tee -a "$LOG_FILE"
        echo "  - No more blinking cursor!" | tee -a "$LOG_FILE"
        return 0
    else
        error "❌ System verification FAILED!"
        echo "" | tee -a "$LOG_FILE"
        echo "Please fix the errors before flashing:" | tee -a "$LOG_FILE"
        echo "  - Check the log file: $LOG_FILE" | tee -a "$LOG_FILE"
        echo "  - Rebuild the system if necessary" | tee -a "$LOG_FILE"
        return 1
    fi
}

# Run main function
main "$@"
