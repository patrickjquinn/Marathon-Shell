#!/bin/bash
# Mimic WaylandCompositor::launchApp environment

# 1. Setup variables
SOCKET_NAME="marathon-wayland-0"
RUNTIME_DIR="/run/user/$(id -u)"
TIMESTAMP=$(date +%s)
HASH="test_hash"
TMP_DESKTOP="/tmp/marathon-apps/marathon-${TIMESTAMP}-${HASH}.desktop"

# 2. Create temp directory
mkdir -p /tmp/marathon-apps

# 3. Create fake desktop file (as WaylandCompositor does)
cat > "$TMP_DESKTOP" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Marathon Embedded App
GenericName=Application
Comment=Application running in Marathon OS
Exec=galculator
Terminal=false
Categories=Utility;
StartupNotify=true
X-GNOME-UsesNotifications=false
X-Marathon-Embedded=true
EOF

echo "Created fake desktop file: $TMP_DESKTOP"

# 4. Set Environment Variables
export WAYLAND_DISPLAY="$SOCKET_NAME"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export QT_QPA_PLATFORM="wayland"
export GDK_BACKEND="wayland"
export CLUTTER_BACKEND="wayland"
export SDL_VIDEODRIVER="wayland"

# Mobile factors
export LIBADWAITA_MOBILE="1"
export PURISM_FORM_FACTOR="phone"
export QT_QUICK_CONTROLS_MOBILE="1"
export QT_QUICK_CONTROLS_STYLE="Mobile"
export GTK_CSD="1"
export GTK_USE_PORTAL="0"

# Unset DISPLAY to force Wayland (matching WaylandCompositor logic)
unset DISPLAY

# The suspect: GIO_LAUNCHED_DESKTOP_FILE
export GIO_LAUNCHED_DESKTOP_FILE="$TMP_DESKTOP"
export GIO_LAUNCHED_DESKTOP_FILE_PID="$$"

echo "Launching galculator with full environment..."
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "GIO_LAUNCHED_DESKTOP_FILE=$GIO_LAUNCHED_DESKTOP_FILE"

# 5. Launch
sh -c "galculator"
