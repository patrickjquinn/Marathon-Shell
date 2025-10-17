#!/bin/bash
# Marathon OS Optimized Rebuild Script
# Rebuilds packages with performance optimizations and updates Marathon Shell

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES_DIR="$WORK_DIR/packages"
MARATHON_SHELL_DIR="$PACKAGES_DIR/marathon-shell"

echo -e "${BLUE}=== Marathon OS Optimized Rebuild Script ===${NC}"
echo "Working directory: $WORK_DIR"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${BLUE}Step 1: Checking prerequisites...${NC}"

if ! command_exists pmbootstrap; then
    print_error "pmbootstrap not found. Please install it first."
    exit 1
fi

if ! command_exists git; then
    print_error "git not found. Please install it first."
    exit 1
fi

print_status "Prerequisites check passed"
echo ""

# Update Marathon Shell from latest repo
echo -e "${BLUE}Step 2: Updating Marathon Shell from latest repository...${NC}"

if [ ! -d "$MARATHON_SHELL_DIR" ]; then
    print_error "Marathon Shell directory not found: $MARATHON_SHELL_DIR"
    exit 1
fi

cd "$MARATHON_SHELL_DIR"

# Check if this is a git repository
if [ ! -d ".git" ]; then
    print_warning "Not a git repository, skipping Marathon Shell update"
else
    echo "Pulling latest changes from Marathon Shell repository..."
    if git pull origin main; then
        print_status "Marathon Shell updated successfully"
    else
        print_warning "Failed to update Marathon Shell (continuing anyway)"
    fi
fi

cd "$WORK_DIR"
echo ""

# Shutdown any existing pmbootstrap processes
echo -e "${BLUE}Step 3: Cleaning up existing pmbootstrap processes...${NC}"
if pmbootstrap shutdown >/dev/null 2>&1; then
    print_status "pmbootstrap processes cleaned up"
else
    print_warning "No existing pmbootstrap processes to clean up"
fi
echo ""

# Rebuild kernel package
echo -e "${BLUE}Step 4: Rebuilding kernel package with optimizations...${NC}"
echo "This includes XZ compression and mobile optimizations..."

if pmbootstrap build linux-marathon-enchilada --force; then
    print_status "Kernel package rebuilt successfully"
else
    print_error "Kernel package rebuild failed"
    exit 1
fi
echo ""

# Rebuild base-config package
echo -e "${BLUE}Step 5: Rebuilding base-config package with optimizations...${NC}"
echo "This includes enhanced sysctl tuning and memory management..."

if pmbootstrap build marathon-base-config --force; then
    print_status "Base-config package rebuilt successfully"
else
    print_error "Base-config package rebuild failed"
    exit 1
fi
echo ""

# Rebuild Marathon Shell package
echo -e "${BLUE}Step 6: Rebuilding Marathon Shell package...${NC}"

if pmbootstrap build marathon-shell --force; then
    print_status "Marathon Shell package rebuilt successfully"
else
    print_error "Marathon Shell package rebuild failed"
    exit 1
fi
echo ""

# Build complete system
echo -e "${BLUE}Step 7: Building complete optimized system...${NC}"
echo "This will create the final images with all optimizations..."

if ./scripts/build-and-flash.sh enchilada; then
    print_status "Complete system built successfully"
else
    print_error "Complete system build failed"
    exit 1
fi
echo ""

# Summary
echo -e "${BLUE}=== Build Complete ===${NC}"
echo -e "${GREEN}✓${NC} All packages rebuilt with optimizations"
echo -e "${GREEN}✓${NC} Marathon Shell updated from latest repository"
echo -e "${GREEN}✓${NC} Complete system images generated"
echo ""
echo -e "${YELLOW}Optimizations applied:${NC}"
echo "  • XZ kernel compression (~30% smaller kernel)"
echo "  • Enhanced TCP/UDP network tuning"
echo "  • Memory compaction and OOM tuning"
echo "  • Real-time scheduling for mobile responsiveness"
echo "  • Flash-optimized storage (F2FS + Kyber)"
echo "  • zram compression with LZ4"
echo ""
echo -e "${BLUE}Images ready for flashing:${NC}"
echo "  • boot.img (kernel + initramfs)"
echo "  • oneplus-enchilada-root.img (complete system)"
echo ""
echo -e "${YELLOW}To flash to device:${NC}"
echo "  fastboot flash boot out/enchilada/boot.img"
echo "  fastboot flash system out/enchilada/oneplus-enchilada-root.img"
echo "  fastboot reboot"
echo ""
echo -e "${GREEN}Marathon OS with optimizations is ready! 🚀${NC}"
