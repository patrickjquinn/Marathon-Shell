#!/bin/bash
# Marathon Shell on Hackberry Pi - Uninstall Script
# Restores the original Raspberry Pi desktop environment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║   Marathon Shell - Uninstall                           ║"
echo "║   Restore Raspberry Pi Desktop                         ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${RED}This will restore your Raspberry Pi to the default desktop environment.${NC}"
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo -e "\n${GREEN}=== Step 1: Restoring LightDM configuration ===${NC}"

# Find most recent backup
BACKUP=$(ls -t /etc/lightdm/lightdm.conf.backup.* 2>/dev/null | head -1)

if [ -n "$BACKUP" ]; then
    sudo cp "$BACKUP" /etc/lightdm/lightdm.conf
    echo "✓ Restored LightDM config from: $BACKUP"
else
    echo -e "${YELLOW}Warning: No backup found. Resetting to default Raspberry Pi session...${NC}"
    sudo sed -i 's/^user-session=marathon/user-session=LXDE-pi-wayfire/' /etc/lightdm/lightdm.conf
    sudo sed -i 's/^autologin-session=marathon/autologin-session=LXDE-pi-wayfire/' /etc/lightdm/lightdm.conf
    sudo sed -i 's/^greeter-session=lightdm-gtk-greeter/#greeter-session=lightdm-gtk-greeter/' /etc/lightdm/lightdm.conf
    echo "✓ Reset to default session"
fi

echo -e "\n${GREEN}=== Step 2: Keeping Marathon Shell files (optional removal) ===${NC}"

echo "Marathon Shell files remain installed in case you want to use it again."
echo "To completely remove Marathon Shell:"
echo "  sudo rm /usr/local/bin/marathon-shell-session"
echo "  sudo rm /usr/share/wayland-sessions/marathon.desktop"
echo "  sudo rm /usr/bin/marathon-shell-bin"

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            Uninstallation Complete!                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${YELLOW}Please reboot to return to the Raspberry Pi desktop:${NC}"
echo -e "  ${GREEN}sudo reboot${NC}"

echo -e "\n${BLUE}To reinstall Marathon Shell later:${NC}"
echo -e "  ${GREEN}./scripts/install.sh${NC}"

