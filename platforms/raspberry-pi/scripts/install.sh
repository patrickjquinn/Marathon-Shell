#!/bin/bash
# Marathon Shell on Hackberry Pi - Automated Installation Script
# This script installs and configures Marathon Shell as the default desktop environment

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║   Marathon Shell on Hackberry Pi - Installation       ║"
echo "║   BlackBerry BB10 Successor on Raspberry Pi           ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running on Raspberry Pi
if [ ! -f /proc/device-tree/model ] || ! grep -q "Raspberry Pi" /proc/device-tree/model; then
    echo -e "${YELLOW}Warning: This doesn't appear to be a Raspberry Pi${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if Marathon Shell is installed
if [ ! -f /usr/bin/marathon-shell-bin ]; then
    echo -e "${RED}Error: Marathon Shell binary not found at /usr/bin/marathon-shell-bin${NC}"
    echo "Please compile and install Marathon Shell first."
    echo "See: https://github.com/MarathonOS/marathon-shell#building"
    exit 1
fi

# Check if Marathon Shell source directory exists
if [ ! -d "$HOME/Marathon-Shell" ]; then
    echo -e "${YELLOW}Warning: Marathon Shell source not found at $HOME/Marathon-Shell${NC}"
    echo "Patches cannot be applied. Please update the path if Marathon Shell is installed elsewhere."
    read -p "Continue without applying patches? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    SKIP_PATCHES=1
fi

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}=== Step 1: Backing up existing configuration ===${NC}"

# Backup LightDM config
if [ -f /etc/lightdm/lightdm.conf ]; then
    sudo cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup.$(date +%Y%m%d_%H%M%S)
    echo "✓ Backed up /etc/lightdm/lightdm.conf"
fi

# Backup existing marathon session files if they exist
if [ -f /usr/local/bin/marathon-shell-session ]; then
    sudo cp /usr/local/bin/marathon-shell-session /usr/local/bin/marathon-shell-session.backup.$(date +%Y%m%d_%H%M%S)
    echo "✓ Backed up /usr/local/bin/marathon-shell-session"
fi

if [ -f /usr/share/wayland-sessions/marathon.desktop ]; then
    sudo cp /usr/share/wayland-sessions/marathon.desktop /usr/share/wayland-sessions/marathon.desktop.backup.$(date +%Y%m%d_%H%M%S)
    echo "✓ Backed up /usr/share/wayland-sessions/marathon.desktop"
fi

if [ "$SKIP_PATCHES" != "1" ]; then
    echo -e "\n${GREEN}=== Step 2: Applying QML patches ===${NC}"
    
    cd "$HOME/Marathon-Shell"
    
    # Check if patches are already applied
    if grep -q "property double lastActivityTime" shell/qml/services/SessionManager.qml; then
        echo "✓ SessionManager patch already applied"
    else
        echo "Applying SessionManager patch..."
        patch -p1 < "$REPO_DIR/patches/01-sessionmanager-fix.patch"
        echo "✓ Applied SessionManager patch"
    fi
    
    # Check if SessionStore patch is needed
    if grep -q "30 second guard" shell/qml/stores/SessionStore.qml; then
        echo "Applying SessionStore patch..."
        patch -p1 < "$REPO_DIR/patches/02-sessionstore-fix.patch"
        echo "✓ Applied SessionStore patch"
    else
        echo "✓ SessionStore patch already applied or not needed"
    fi
    
    # Rebuild Marathon Shell
    echo -e "\n${BLUE}Rebuilding Marathon Shell...${NC}"
    if [ -d build ]; then
        cd build
        ninja install
        echo "✓ Marathon Shell rebuilt and installed"
    else
        echo -e "${YELLOW}Warning: build directory not found. Please rebuild Marathon Shell manually:${NC}"
        echo "  cd ~/Marathon-Shell/build"
        echo "  ninja install"
    fi
else
    echo -e "\n${YELLOW}=== Step 2: Skipping patches (source not found) ===${NC}"
fi

echo -e "\n${GREEN}=== Step 3: Installing session files ===${NC}"

# Install session startup script
sudo cp "$REPO_DIR/config/marathon-shell-session" /usr/local/bin/
sudo chmod +x /usr/local/bin/marathon-shell-session
echo "✓ Installed /usr/local/bin/marathon-shell-session"

# Install desktop entry
sudo mkdir -p /usr/share/wayland-sessions
sudo cp "$REPO_DIR/config/marathon.desktop" /usr/share/wayland-sessions/
echo "✓ Installed /usr/share/wayland-sessions/marathon.desktop"

echo -e "\n${GREEN}=== Step 4: Configuring LightDM ===${NC}"

# Install LightDM configuration
sudo cp "$REPO_DIR/config/lightdm.conf" /etc/lightdm/
echo "✓ Installed LightDM configuration"

# Ensure lightdm-gtk-greeter is installed
if ! dpkg -l | grep -q lightdm-gtk-greeter; then
    echo "Installing lightdm-gtk-greeter..."
    sudo apt-get update
    sudo apt-get install -y lightdm-gtk-greeter
fi

echo -e "\n${GREEN}=== Step 5: Setting up permissions ===${NC}"

# Add user to video and render groups
sudo usermod -a -G video,render $USER
echo "✓ Added $USER to video,render groups"

# Grant capabilities to Marathon Shell
sudo setcap cap_sys_nice+ep /usr/bin/marathon-shell-bin
echo "✓ Granted Marathon Shell real-time priority capability"

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Installation Complete! 🎉                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${BLUE}Marathon Shell is now configured as your default desktop environment.${NC}"
echo -e "\n${YELLOW}Please reboot to start using Marathon Shell:${NC}"
echo -e "  ${GREEN}sudo reboot${NC}"

echo -e "\n${BLUE}After reboot:${NC}"
echo "  • Marathon Shell will start automatically"
echo "  • Swipe up on the lock screen to unlock"
echo "  • Auto-lock after 1 hour of inactivity"
echo "  • GPU-accelerated rendering (eglfs)"

echo -e "\n${YELLOW}Troubleshooting:${NC}"
echo "  • If you see a black screen, press Ctrl+Alt+F2 for a terminal"
echo "  • Check logs: journalctl -u lightdm | tail -50"
echo "  • See docs/TROUBLESHOOTING.md for common issues"

echo -e "\n${BLUE}To restore the original Raspberry Pi desktop:${NC}"
echo -e "  ${GREEN}./scripts/uninstall.sh${NC}"

echo -e "\n${GREEN}Enjoy your BlackBerry BB10 successor! 📱✨${NC}"

