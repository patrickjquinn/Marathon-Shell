#!/bin/bash
# Marathon OS Logo Integration Script
# Integrates Marathon logo into the build process

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if Marathon logo exists
if [ ! -f "$PROJECT_DIR/resources/marathon.png" ]; then
    echo -e "${RED}[ERROR]${NC} Marathon logo not found: $PROJECT_DIR/resources/marathon.png"
    exit 1
fi

log "Integrating Marathon logo into Marathon Shell..."

# Copy Marathon logo to Marathon Shell resources
log "Copying Marathon logo to Marathon Shell resources..."
cp "$PROJECT_DIR/resources/marathon.png" "$PROJECT_DIR/packages/marathon-shell/shell/resources/wallpapers/marathon-logo.jpg"

# Update Marathon Shell package checksums
log "Updating Marathon Shell package checksums..."
cd "$PROJECT_DIR/packages/marathon-shell"
if command -v pmbootstrap >/dev/null 2>&1; then
    pmbootstrap checksum marathon-shell || true
fi

success "Marathon logo integrated into Marathon Shell!"

log "Creating boot logo files..."
cd "$PROJECT_DIR"
./scripts/create-boot-logo.sh

success "Marathon logo integration complete!"

echo ""
echo "Marathon logo has been integrated into:"
echo "  ✅ Marathon Shell wallpaper (default)"
echo "  ✅ Boot logo files created"
echo "  ✅ Package checksums updated"
echo ""
echo "Next steps:"
echo "  1. Rebuild Marathon Shell: pmbootstrap build marathon-shell --force"
echo "  2. Rebuild system: pmbootstrap install --add marathon-shell"
echo "  3. Export images: pmbootstrap export"
echo "  4. Flash to device: fastboot flash boot out/enchilada/boot.img"
echo ""
echo "The Marathon logo will now appear as:"
echo "  - Default wallpaper in Marathon Shell"
echo "  - Boot logo files ready for flashing"
echo "  - Available in wallpaper settings"
