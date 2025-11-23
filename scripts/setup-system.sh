#!/bin/bash
# Marathon Shell - System Setup Script
# Configures system permissions and dependencies for full mobile functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================"
echo "Marathon Shell - System Setup"
echo "============================================"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "⚠️  Please run this script as your normal user (with sudo available)"
    echo "   Usage: ./scripts/setup-system.sh"
    exit 1
fi

# Check for sudo
if ! command -v sudo &> /dev/null; then
    echo "❌ sudo command not found. Please install sudo first."
    exit 1
fi

echo "This script will configure:"
echo "  1. Backlight (brightness control) permissions"
echo "  2. Bluetooth service (BlueZ)"
echo "  3. PAM authentication"
echo "  4. Screenshot directory"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1/4: Backlight Permissions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Install udev rule for backlight permissions
echo "Installing udev rule for brightness control..."
if [ -f "$SCRIPT_DIR/90-backlight.rules" ]; then
    sudo cp "$SCRIPT_DIR/90-backlight.rules" /etc/udev/rules.d/90-backlight.rules
else
    echo "⚠️  90-backlight.rules not found in script directory. Creating default..."
    sudo tee /etc/udev/rules.d/90-backlight.rules > /dev/null <<'EOF'
# Marathon Shell - Allow brightness control without root
SUBSYSTEM=="backlight", ACTION=="add", RUN+="/bin/chmod 666 /sys/class/backlight/%k/brightness"
EOF
fi

echo "✓ udev rule created: /etc/udev/rules.d/90-backlight.rules"

# Reload udev rules
echo "Reloading udev rules..."
sudo udevadm control --reload-rules
# Filter out harmless Apple SMC warnings on Apple Silicon
sudo udevadm trigger 2>&1 | grep -v "macsmc" || true

# Verify backlight device exists
if [ -d "/sys/class/backlight" ]; then
    BACKLIGHT_DEVICE=$(ls /sys/class/backlight/ 2>/dev/null | head -n 1)
    if [ -n "$BACKLIGHT_DEVICE" ]; then
        echo "✓ Backlight device detected: $BACKLIGHT_DEVICE"
        # Try to set permissions now
        sudo chmod 666 /sys/class/backlight/*/brightness 2>/dev/null || true
    else
        echo "⚠️  No backlight device found (expected on desktop/VM)"
    fi
else
    echo "⚠️  No backlight interface available"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2/4: Bluetooth (BlueZ)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if BlueZ is already installed
if systemctl list-unit-files bluetooth.service &> /dev/null; then
    echo "✓ Bluetooth service already available"
    
    # Check if it's running
    if systemctl is-active --quiet bluetooth; then
        echo "✓ Bluetooth service is running"
    else
        echo "Starting Bluetooth service..."
        sudo systemctl enable bluetooth
        sudo systemctl start bluetooth
        echo "✓ Bluetooth service started"
    fi
else
    echo "Installing Bluetooth (BlueZ)..."
    
    # Detect package manager
    if command -v dnf &> /dev/null; then
        sudo dnf install -y bluez
    elif command -v apt &> /dev/null; then
        sudo apt install -y bluez
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm bluez
    else
        echo "⚠️  Unknown package manager. Please install bluez manually:"
        echo "   Fedora: sudo dnf install bluez"
        echo "   Ubuntu: sudo apt install bluez"
        echo "   Arch:   sudo pacman -S bluez"
    fi
    
    # Enable and start
    sudo systemctl enable bluetooth
    sudo systemctl start bluetooth
    echo "✓ Bluetooth installed and started"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3/4: PAM Authentication"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Install PAM configuration
if [ ! -f "/etc/pam.d/marathon-shell" ]; then
    echo "Installing PAM configuration..."
    sudo cp "$PROJECT_ROOT/pam.d/marathon-shell" /etc/pam.d/marathon-shell
    echo "✓ PAM configuration installed"
else
    echo "✓ PAM configuration already installed"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4/4: User Directories"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create screenshot directory
SCREENSHOTS_DIR="$HOME/Pictures/Screenshots"
if [ ! -d "$SCREENSHOTS_DIR" ]; then
    echo "Creating screenshots directory..."
    mkdir -p "$SCREENSHOTS_DIR"
    echo "✓ Created $SCREENSHOTS_DIR"
else
    echo "✓ Screenshots directory exists"
fi

echo ""
echo "============================================"
echo "✓ System Setup Complete!"
echo "============================================"
echo ""
echo "Configuration applied:"
echo "  • Brightness control permissions configured"
echo "  • Bluetooth service installed and running"
echo "  • PAM authentication configured"
echo "  • Screenshot directory created"
echo ""
echo "⚠️  IMPORTANT: Reboot recommended for all changes to take effect"
echo ""
echo "To test without rebooting, you can:"
echo "  1. Manually set brightness permissions:"
echo "     sudo chmod 666 /sys/class/backlight/*/brightness"
echo "  2. Restart Bluetooth:"
echo "     sudo systemctl restart bluetooth"
echo ""
