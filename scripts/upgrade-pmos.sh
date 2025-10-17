#!/bin/bash
# postmarketOS Upgrade Utility
# Handles upgrading both build environment and device

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PMBOOTSTRAP_CONFIG="$HOME/.config/pmbootstrap.cfg"
BACKUP_CONFIG="$HOME/.config/pmbootstrap.cfg.backup"

echo -e "${BLUE}=== postmarketOS Upgrade Utility ===${NC}"
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

print_status "Prerequisites check passed"
echo ""

# Show current version
echo -e "${BLUE}Current postmarketOS version:${NC}"
if [ -f "$PMBOOTSTRAP_CONFIG" ]; then
    CURRENT_CHANNEL=$(grep "^channel" "$PMBOOTSTRAP_CONFIG" | cut -d'"' -f2)
    echo "  Channel: $CURRENT_CHANNEL"
else
    print_error "pmbootstrap config not found"
    exit 1
fi
echo ""

# Get target version
echo -e "${BLUE}Available upgrade options:${NC}"
echo "  1) v26.xx (next stable - when available)"
echo "  2) edge (latest development)"
echo "  3) Custom version"
echo ""

read -p "Enter target version (e.g., v26.06, edge): " TARGET_VERSION

if [ -z "$TARGET_VERSION" ]; then
    print_error "No target version specified"
    exit 1
fi

echo ""
echo -e "${YELLOW}This will upgrade from $CURRENT_CHANNEL to $TARGET_VERSION${NC}"
read -p "Continue? (y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Upgrade cancelled"
    exit 0
fi

# Backup current config
echo -e "${BLUE}Step 2: Backing up current configuration...${NC}"
if [ -f "$PMBOOTSTRAP_CONFIG" ]; then
    cp "$PMBOOTSTRAP_CONFIG" "$BACKUP_CONFIG"
    print_status "Configuration backed up to $BACKUP_CONFIG"
else
    print_warning "No existing configuration to backup"
fi
echo ""

# Upgrade build environment
echo -e "${BLUE}Step 3: Upgrading build environment...${NC}"
echo "This will re-initialize pmbootstrap with the new version..."

# Method 1: Re-initialize (recommended)
echo "Re-initializing pmbootstrap..."
echo "Please select the following options when prompted:"
echo "  - Channel: $TARGET_VERSION"
echo "  - Device: oneplus/enchilada"
echo "  - Init system: systemd"
echo "  - UI: none"
echo ""

read -p "Press Enter to continue with pmbootstrap init..."
pmbootstrap init

print_status "pmbootstrap re-initialized with $TARGET_VERSION"
echo ""

# Pull latest pmaports
echo -e "${BLUE}Step 4: Pulling latest pmaports...${NC}"
if pmbootstrap pull; then
    print_status "Latest pmaports pulled successfully"
else
    print_error "Failed to pull pmaports"
    exit 1
fi
echo ""

# Rebuild with new version
echo -e "${BLUE}Step 5: Rebuilding with new version...${NC}"
echo "This will rebuild all packages with the new postmarketOS version..."

if ./scripts/rebuild-optimized.sh; then
    print_status "Rebuild completed successfully"
else
    print_error "Rebuild failed"
    echo ""
    echo -e "${YELLOW}You can restore the previous configuration with:${NC}"
    echo "  cp $BACKUP_CONFIG $PMBOOTSTRAP_CONFIG"
    exit 1
fi
echo ""

# Summary
echo -e "${BLUE}=== Upgrade Complete ===${NC}"
echo -e "${GREEN}✓${NC} Build environment upgraded to $TARGET_VERSION"
echo -e "${GREEN}✓${NC} All packages rebuilt with new version"
echo -e "${GREEN}✓${NC} New images ready for flashing"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Flash the new images to your device"
echo "  2. On the device, run: sudo postmarketos-release-upgrade"
echo "  3. Reboot the device"
echo ""
echo -e "${BLUE}Device upgrade command:${NC}"
echo "  sudo apk add postmarketos-release-upgrade"
echo "  sudo apk update"
echo "  sudo postmarketos-release-upgrade"
echo "  sudo reboot"
echo ""
echo -e "${GREEN}postmarketOS upgrade completed! 🚀${NC}"
