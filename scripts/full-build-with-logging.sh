#!/bin/bash
# Marathon OS Full Build with Comprehensive Logging
# This script performs a complete build and logs everything for analysis

set -e

# Configuration
LOG_FILE="marathon-build-$(date +%Y%m%d-%H%M%S).log"
DEVICE="${1:-enchilada}"
WORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Marathon OS Full Build with Logging ===" | tee "$LOG_FILE"
echo "Device: $DEVICE" | tee -a "$LOG_FILE"
echo "Working directory: $WORK_DIR" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Function to log commands and output
log_command() {
    echo ">>> $*" | tee -a "$LOG_FILE"
    "$@" 2>&1 | tee -a "$LOG_FILE"
    local exit_code=${PIPESTATUS[0]}
    echo ">>> Exit code: $exit_code" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    return $exit_code
}

# Function to check prerequisites
check_prerequisites() {
    echo "=== Checking Prerequisites ===" | tee -a "$LOG_FILE"
    
    # Check if we're on Fedora
    if [ -f /etc/fedora-release ]; then
        echo "✅ Fedora detected: $(cat /etc/fedora-release)" | tee -a "$LOG_FILE"
    else
        echo "⚠️  Not on Fedora, but continuing..." | tee -a "$LOG_FILE"
    fi
    
    # Check required tools
    for tool in pmbootstrap fastboot adb git; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "✅ $tool: $(command -v $tool)" | tee -a "$LOG_FILE"
        else
            echo "❌ $tool: Not found" | tee -a "$LOG_FILE"
            echo "Install with: sudo dnf install pmbootstrap android-tools git" | tee -a "$LOG_FILE"
            return 1
        fi
    done
    
    # Check disk space
    AVAILABLE_SPACE=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$AVAILABLE_SPACE" -lt 20 ]; then
        echo "⚠️  Low disk space: ${AVAILABLE_SPACE}GB available (need 20GB+)" | tee -a "$LOG_FILE"
    else
        echo "✅ Disk space: ${AVAILABLE_SPACE}GB available" | tee -a "$LOG_FILE"
    fi
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to initialize pmbootstrap
init_pmbootstrap() {
    echo "=== Initializing pmbootstrap ===" | tee -a "$LOG_FILE"
    
    # Check if already initialized
    if pmbootstrap config device >/dev/null 2>&1; then
        echo "✅ pmbootstrap already initialized" | tee -a "$LOG_FILE"
        pmbootstrap config device | tee -a "$LOG_FILE"
    else
        echo "Initializing pmbootstrap..." | tee -a "$LOG_FILE"
        echo "Note: This will prompt for configuration. Use these settings:" | tee -a "$LOG_FILE"
        echo "  Channel: edge" | tee -a "$LOG_FILE"
        echo "  Device: oneplus/enchilada" | tee -a "$LOG_FILE"
        echo "  UI: none" | tee -a "$LOG_FILE"
        echo "  Username: user" | tee -a "$LOG_FILE"
        echo "  Hostname: marathon-phone" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        
        # Initialize pmbootstrap (this will be interactive)
        log_command pmbootstrap init
    fi
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to copy packages to pmbootstrap workspace
copy_packages() {
    echo "=== Copying Packages to pmbootstrap Workspace ===" | tee -a "$LOG_FILE"
    
    PMAPORTS_DIR="$HOME/.local/var/pmbootstrap/cache_git/pmaports"
    
    # Copy packages to pmaports
    echo "Copying marathon-base-config..." | tee -a "$LOG_FILE"
    log_command cp -r packages/marathon-base-config "$PMAPORTS_DIR/main/"
    
    echo "Copying marathon-shell..." | tee -a "$LOG_FILE"
    log_command rsync -av --exclude='.git' packages/marathon-shell/ "$PMAPORTS_DIR/main/marathon-shell/"
    
    echo "Copying linux-marathon..." | tee -a "$LOG_FILE"
    log_command cp -r packages/linux-marathon "$PMAPORTS_DIR/device/main/"
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to build packages
build_packages() {
    echo "=== Building Packages ===" | tee -a "$LOG_FILE"
    
    # Build kernel
    echo "Building linux-marathon..." | tee -a "$LOG_FILE"
    log_command pmbootstrap build linux-marathon
    
    # Build base config
    echo "Building marathon-base-config..." | tee -a "$LOG_FILE"
    log_command pmbootstrap build marathon-base-config
    
    # Build marathon shell
    echo "Building marathon-shell..." | tee -a "$LOG_FILE"
    log_command pmbootstrap build marathon-shell
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to install system
install_system() {
    echo "=== Installing System ===" | tee -a "$LOG_FILE"
    
    echo "Installing Marathon Shell into existing rootfs..." | tee -a "$LOG_FILE"
    log_command pmbootstrap chroot -r -- apk add marathon-shell
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to generate kernel modules
generate_kernel_modules() {
    echo "=== Generating Kernel Modules ===" | tee -a "$LOG_FILE"
    
    echo "Generating kernel module dependencies..." | tee -a "$LOG_FILE"
    log_command pmbootstrap chroot -r -- /bin/sh -c "depmod -a 6.17.3 || echo 'Note: depmod warning is normal for custom kernels'"
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to export images
export_images() {
    echo "=== Exporting Images ===" | tee -a "$LOG_FILE"
    
    echo "Exporting boot and rootfs images..." | tee -a "$LOG_FILE"
    log_command pmbootstrap export
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to verify build
verify_build() {
    echo "=== Verifying Build ===" | tee -a "$LOG_FILE"
    
    # Check output directory
    if [ -d "out/enchilada" ]; then
        echo "✅ Output directory exists: out/enchilada" | tee -a "$LOG_FILE"
        ls -la out/enchilada/ | tee -a "$LOG_FILE"
    else
        echo "❌ Output directory not found: out/enchilada" | tee -a "$LOG_FILE"
        return 1
    fi
    
    # Check for required images
    if [ -f "out/enchilada/boot.img" ]; then
        echo "✅ Boot image exists: $(ls -lh out/enchilada/boot.img | awk '{print $5}')" | tee -a "$LOG_FILE"
    else
        echo "❌ Boot image not found" | tee -a "$LOG_FILE"
    fi
    
    if [ -f "out/enchilada/oneplus-enchilada-root.img" ]; then
        echo "✅ Root image exists: $(ls -lh out/enchilada/oneplus-enchilada-root.img | awk '{print $5}')" | tee -a "$LOG_FILE"
    else
        echo "❌ Root image not found" | tee -a "$LOG_FILE"
    fi
    
    # Check Marathon Shell installation
    echo "Checking Marathon Shell installation..." | tee -a "$LOG_FILE"
    log_command pmbootstrap chroot -r -- ls -la /usr/bin/marathon-shell
    log_command pmbootstrap chroot -r -- ls -la /usr/share/marathon-apps/
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to analyze log for errors
analyze_log() {
    echo "=== Analyzing Build Log for Errors ===" | tee -a "$LOG_FILE"
    
    # Count different types of messages (exclude analysis section itself)
    ERROR_COUNT=$(grep -v "=== Analyzing Build Log for Errors ===" "$LOG_FILE" | grep -i "error\|failed\|fatal" | grep -v "WARNING\|WARN" | wc -l)
    WARNING_COUNT=$(grep -v "=== Analyzing Build Log for Errors ===" "$LOG_FILE" | grep -i "warning\|warn" | wc -l)
    
    echo "Errors found: $ERROR_COUNT" | tee -a "$LOG_FILE"
    echo "Warnings found: $WARNING_COUNT" | tee -a "$LOG_FILE"
    
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "❌ ERRORS DETECTED:" | tee -a "$LOG_FILE"
        grep -v "=== Analyzing Build Log for Errors ===" "$LOG_FILE" | grep -i "error\|failed\|fatal" | grep -v "WARNING\|WARN" | tee -a "$LOG_FILE"
    else
        echo "✅ No errors detected" | tee -a "$LOG_FILE"
    fi
    
    if [ "$WARNING_COUNT" -gt 0 ]; then
        echo "⚠️  WARNINGS DETECTED:" | tee -a "$LOG_FILE"
        grep -v "=== Analyzing Build Log for Errors ===" "$LOG_FILE" | grep -i "warning\|warn" | head -10 | tee -a "$LOG_FILE"
    else
        echo "✅ No warnings detected" | tee -a "$LOG_FILE"
    fi
    
    echo "" | tee -a "$LOG_FILE"
}

# Main execution
main() {
    echo "Starting Marathon OS build process..." | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # Run all build steps
    check_prerequisites || exit 1
    init_pmbootstrap || exit 1
    copy_packages || exit 1
    build_packages || exit 1
    install_system || exit 1
    generate_kernel_modules || exit 1
    export_images || exit 1
    verify_build || exit 1
    analyze_log
    
    echo "=== Build Complete ===" | tee -a "$LOG_FILE"
    echo "Finished: $(date)" | tee -a "$LOG_FILE"
    echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
    
    if [ "$ERROR_COUNT" -eq 0 ]; then
        echo "✅ BUILD SUCCESSFUL - No errors detected!" | tee -a "$LOG_FILE"
        echo "Ready for flashing to device!" | tee -a "$LOG_FILE"
    else
        echo "❌ BUILD FAILED - $ERROR_COUNT errors detected!" | tee -a "$LOG_FILE"
        echo "Check the log file for details: $LOG_FILE" | tee -a "$LOG_FILE"
    fi
}

# Run main function
main "$@"
