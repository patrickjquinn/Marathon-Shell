#!/bin/bash
# Marathon Shell - Session Installation Script
# Installs the shell and session files for LightDM/GDM/SDDM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================"
echo "Marathon Shell - Session Installer"
echo "============================================"
echo ""

# Check for sudo
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  This script requires root privileges to install to /usr/local"
    echo "   Please run with sudo: sudo ./scripts/install-session.sh"
    exit 1
fi

echo "This will install Marathon Shell to /usr/local"
echo "It will be available as a session in LightDM/GDM"
echo ""

# Build Release version
echo "🏗  Building Release version..."
cd "$PROJECT_ROOT"
cmake -B build-release -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build build-release --parallel $(nproc)

echo ""
echo "📦 Installing..."
cmake --install build-release

echo ""
echo "🔗 Symlinking to /usr/share/wayland-sessions (for LightDM visibility)..."
mkdir -p /usr/share/wayland-sessions
ln -sf /usr/local/share/wayland-sessions/marathon.desktop /usr/share/wayland-sessions/marathon.desktop

# Fix for Raspberry Pi OS: Disable autologin and force lightdm-gtk-greeter
echo ""
echo "🔧 Configuring LightDM..."

# 1. Force LightDM to use lightdm-gtk-greeter via high-priority config
echo "   Creating /etc/lightdm/lightdm.conf.d/99-marathon-greeter.conf..."
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/99-marathon-greeter.conf <<EOF
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=marathon
autologin-user=
autologin-user-timeout=0
EOF

# 2. Configure lightdm-gtk-greeter to explicitly show the session menu
echo "   Configuring /etc/lightdm/lightdm-gtk-greeter.conf..."
cat > /etc/lightdm/lightdm-gtk-greeter.conf <<EOF
[greeter]
# Use a dark background or standard color
background=#2d2d2d
# Ensure standard theme is used
theme-name=Adwaita
icon-theme-name=Adwaita
font-name=Sans 10
# CRITICAL: Explicitly list indicators including ~session
indicators=~host;~spacer;~clock;~spacer;~session;~a11y;~power
# Position the login window in the center
position=50%,center 50%,center
EOF

# 3. Ensure dependencies are installed
if ! dpkg -l | grep -q lightdm-gtk-greeter; then
    echo "   Installing lightdm-gtk-greeter..."
    apt-get update && apt-get install -y lightdm-gtk-greeter gnome-themes-extra adwaita-icon-theme
fi

echo "   ✓ LightDM configured"

echo ""
echo "✅ Installation Complete!"
echo "   - Binary: /usr/local/bin/marathon-shell-bin"
echo "   - Session: /usr/local/bin/marathon-shell-session"
echo "   - Desktop: /usr/local/share/wayland-sessions/marathon.desktop"
echo ""
echo "You can now log out and select 'Marathon Shell' from the session list."
