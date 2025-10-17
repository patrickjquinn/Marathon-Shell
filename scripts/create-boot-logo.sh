#!/bin/bash
# Marathon OS Boot Logo Creator
# Converts Marathon logo to Android boot logo format

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCES_DIR="$PROJECT_DIR/resources"
OUTPUT_DIR="$PROJECT_DIR/out/enchilada"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if required tools are available
check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v convert >/dev/null 2>&1; then
        error "ImageMagick not found. Please install it:"
        echo "  Fedora: sudo dnf install ImageMagick"
        echo "  Ubuntu: sudo apt install imagemagick"
        exit 1
    fi
    
    if ! command -v python3 >/dev/null 2>&1; then
        error "Python3 not found. Please install it."
        exit 1
    fi
    
    success "Dependencies OK"
}

# Create Android boot logo from Marathon logo
create_boot_logo() {
    log "Creating Android boot logo from Marathon logo..."
    
    # Use the main marathon.png logo
    SOURCE_LOGO="$RESOURCES_DIR/marathon.png"
    
    if [ ! -f "$SOURCE_LOGO" ]; then
        error "Marathon logo not found: $SOURCE_LOGO"
        exit 1
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Convert to Android boot logo format
    # Android boot logos are typically 1080x1920 (portrait) or 1920x1080 (landscape)
    # We'll create both orientations
    
    log "Creating portrait boot logo (1080x1920)..."
    convert "$SOURCE_LOGO" \
        -resize 1080x1920 \
        -background black \
        -gravity center \
        -extent 1080x1920 \
        "$OUTPUT_DIR/marathon-boot-logo-portrait.png"
    
    log "Creating landscape boot logo (1920x1080)..."
    convert "$SOURCE_LOGO" \
        -resize 1920x1080 \
        -background black \
        -gravity center \
        -extent 1920x1080 \
        "$OUTPUT_DIR/marathon-boot-logo-landscape.png"
    
    # Create a simple boot logo for fastboot (splash screen)
    log "Creating fastboot splash screen..."
    convert "$SOURCE_LOGO" \
        -resize 1080x1920 \
        -background black \
        -gravity center \
        -extent 1080x1920 \
        -format bmp \
        "$OUTPUT_DIR/marathon-splash.bmp"
    
    success "Boot logos created successfully"
}

# Create a simple boot logo script for flashing
create_flash_script() {
    log "Creating boot logo flash script..."
    
    cat > "$OUTPUT_DIR/flash-boot-logo.sh" << 'EOF'
#!/bin/bash
# Flash Marathon boot logo to OnePlus 6

echo "Marathon OS Boot Logo Flasher"
echo "============================="
echo ""

# Check if device is in fastboot mode
if ! fastboot devices | grep -q "fastboot"; then
    echo "ERROR: Device not in fastboot mode"
    echo "Please boot your OnePlus 6 into fastboot mode:"
    echo "1. Power off the device"
    echo "2. Hold Power + Volume Down"
    echo "3. Wait for fastboot mode"
    echo ""
    echo "Then run this script again"
    exit 1
fi

echo "Device detected in fastboot mode"
echo ""

# Flash the boot logo (this replaces the OnePlus boot logo)
echo "Flashing Marathon boot logo..."
echo "WARNING: This will replace the OnePlus boot logo with Marathon logo"
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 1
fi

# Note: OnePlus 6 doesn't have a separate boot logo partition
# The boot logo is embedded in the boot.img
echo "Note: OnePlus 6 boot logo is embedded in boot.img"
echo "To change the boot logo, you need to rebuild boot.img with the new logo"
echo ""
echo "The Marathon logo files are ready:"
echo "  - marathon-boot-logo-portrait.png (1080x1920)"
echo "  - marathon-boot-logo-landscape.png (1920x1080)"
echo "  - marathon-splash.bmp (for fastboot)"
echo ""
echo "To integrate the logo into boot.img, you would need to:"
echo "1. Extract the current boot.img"
echo "2. Replace the logo in the boot.img"
echo "3. Repack the boot.img"
echo "4. Flash the new boot.img"
echo ""
echo "This is a complex process that requires Android boot image tools."
echo "For now, the Marathon logo will be visible in the Marathon Shell interface."
EOF

    chmod +x "$OUTPUT_DIR/flash-boot-logo.sh"
    success "Flash script created"
}

# Create a simple boot animation (optional)
create_boot_animation() {
    log "Creating boot animation..."
    
    # Create a simple boot animation directory
    ANIM_DIR="$OUTPUT_DIR/boot-animation"
    mkdir -p "$ANIM_DIR"
    
    # Create desc.txt (boot animation descriptor)
    cat > "$ANIM_DIR/desc.txt" << 'EOF'
1080 1920 30
p 1 0 part0
EOF
    
    # Create part0 directory
    mkdir -p "$ANIM_DIR/part0"
    
    # Copy the Marathon logo as the boot animation frame
    cp "$OUTPUT_DIR/marathon-boot-logo-portrait.png" "$ANIM_DIR/part0/boot_000.png"
    
    # Create a simple boot animation zip
    cd "$ANIM_DIR"
    zip -r "$OUTPUT_DIR/marathon-boot-animation.zip" .
    cd "$PROJECT_DIR"
    
    success "Boot animation created"
}

# Main execution
main() {
    echo "Marathon OS Boot Logo Creator"
    echo "============================="
    echo ""
    
    check_dependencies
    create_boot_logo
    create_flash_script
    create_boot_animation
    
    echo ""
    success "Marathon boot logo setup complete!"
    echo ""
    echo "Generated files:"
    echo "  - marathon-boot-logo-portrait.png (1080x1920)"
    echo "  - marathon-boot-logo-landscape.png (1920x1080)"
    echo "  - marathon-splash.bmp (fastboot splash)"
    echo "  - marathon-boot-animation.zip (boot animation)"
    echo "  - flash-boot-logo.sh (flash script)"
    echo ""
    echo "Note: OnePlus 6 boot logo is embedded in boot.img"
    echo "The Marathon logo will be visible in the Marathon Shell interface"
    echo "To change the actual boot logo, you would need to modify boot.img"
}

# Run main function
main "$@"
