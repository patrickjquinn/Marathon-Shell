#!/bin/bash
# Marathon Shell - Fedora Testing Environment Setup
# This script configures Fedora to simulate a phone environment for testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "+------------------------------------------------------------+"
echo "| Marathon Shell - Fedora Testing Environment Setup                 |"
echo "╠------------------------------------------------------------╣"
echo "| This script will configure your Fedora system to simulate a       |"
echo "| phone environment with all necessary services and virtual devices. |"
echo "+------------------------------------------------------------+"
echo ""

# Check if running with appropriate privileges for some operations
if [[ $EUID -ne 0 ]]; then
    echo "  Note: Some operations require root privileges."
    echo "    The script will use sudo when needed."
    echo ""
fi

# Function to check if a service exists
service_exists() {
    systemctl list-unit-files | grep -q "^$1.service"
}

# Function to check if a service is active
service_active() {
    systemctl is-active --quiet "$1"
}

echo "------------------------------------------------------------"
echo " STEP 1: Installing Required Packages"
echo "------------------------------------------------------------"

PACKAGES=(
    "bluez"                    # Bluetooth stack
    "iio-sensor-proxy"         # Sensor proxy for orientation
    "ModemManager"             # Modem management
    "NetworkManager"           # Network management
    "upower"                   # Power management
    "geoclue2"                 # Location services
    "pipewire"                 # Audio
    "wireplumber"              # PipeWire session manager
    "ofono"                    # Alternative telephony stack (optional)
    "dbus"                     # DBus daemon
)

echo "Checking and installing missing packages..."
for pkg in "${PACKAGES[@]}"; do
    if ! rpm -q "$pkg" &>/dev/null; then
        echo "  Installing: $pkg"
        sudo dnf install -y "$pkg" || echo "    Failed to install $pkg (may not be available)"
    else
        echo " Already installed: $pkg"
    fi
done

echo ""
echo "------------------------------------------------------------"
echo " STEP 2: Starting and Enabling Services"
echo "------------------------------------------------------------"

# Bluetooth
if service_exists "bluetooth"; then
    echo "Starting bluetooth.service..."
    sudo systemctl start bluetooth || echo "    Failed to start bluetooth"
    sudo systemctl enable bluetooth || echo "    Failed to enable bluetooth"
    if service_active "bluetooth"; then
        echo " Bluetooth service is running"
    else
        echo "    Bluetooth service failed to start (may need hardware)"
    fi
else
    echo "    bluetooth.service not found"
fi

# iio-sensor-proxy
if service_exists "iio-sensor-proxy"; then
    echo "Starting iio-sensor-proxy.service..."
    sudo systemctl start iio-sensor-proxy 2>/dev/null || echo "    iio-sensor-proxy requires IIO sensors (will start on-demand)"
    echo "  ℹ  iio-sensor-proxy is socket-activated (starts when needed)"
else
    echo "    iio-sensor-proxy not found"
fi

# ModemManager
if service_exists "ModemManager"; then
    echo "Starting ModemManager.service..."
    sudo systemctl start ModemManager || echo "    Failed to start ModemManager"
    sudo systemctl enable ModemManager || echo "    Failed to enable ModemManager"
    if service_active "ModemManager"; then
        echo " ModemManager service is running"
    fi
else
    echo "    ModemManager not found"
fi

# NetworkManager
if service_exists "NetworkManager"; then
    if ! service_active "NetworkManager"; then
        echo "Starting NetworkManager.service..."
        sudo systemctl start NetworkManager || echo "    Failed to start NetworkManager"
        sudo systemctl enable NetworkManager || echo "    Failed to enable NetworkManager"
    else
        echo " NetworkManager already running"
    fi
else
    echo "    NetworkManager not found"
fi

# UPower
if service_exists "upower"; then
    if ! service_active "upower"; then
        echo "Starting upower.service..."
        sudo systemctl start upower || echo "    Failed to start upower"
        sudo systemctl enable upower || echo "    Failed to enable upower"
    else
        echo " UPower already running"
    fi
else
    echo "    upower not found"
fi

# Geoclue
if service_exists "geoclue"; then
    if ! service_active "geoclue"; then
        echo "Starting geoclue.service..."
        sudo systemctl start geoclue || echo "    Failed to start geoclue"
        sudo systemctl enable geoclue || echo "    Failed to enable geoclue"
    else
        echo " Geoclue already running"
    fi
else
    echo "    geoclue not found"
fi

# PipeWire (user session)
echo "Ensuring PipeWire is running in user session..."
systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || echo "  ℹ  PipeWire may already be running"
echo " PipeWire audio configured"

echo ""
echo "------------------------------------------------------------"
echo "STEP 3: Creating Virtual Devices"
echo "------------------------------------------------------------"

# Create virtual WiFi device (if not exists)
if ! ip link show wlan0 &>/dev/null; then
    echo "Creating virtual WiFi device (wlan0)..."
    sudo modprobe mac80211_hwsim radios=1 2>/dev/null || {
        echo "    mac80211_hwsim not available (virtual WiFi not created)"
        echo "  ℹ  Using existing network interfaces instead"
    }
    
    if ip link show wlan0 &>/dev/null; then
        echo " Virtual WiFi device created: wlan0"
        sudo ip link set wlan0 up
        sudo nmcli device set wlan0 managed yes 2>/dev/null || true
    fi
else
    echo " wlan0 already exists"
fi

# Ensure dummy0 is managed by NetworkManager (already exists from previous setup)
if ip link show dummy0 &>/dev/null; then
    echo "Configuring dummy0 for NetworkManager..."
    sudo nmcli device set dummy0 managed yes 2>/dev/null || echo "  ℹ  dummy0 already configured"
    echo " dummy0 configured"
fi

echo ""
echo "------------------------------------------------------------"
echo "STEP 4: Configuring Virtual Battery (UPower)"
echo "------------------------------------------------------------"

# Create a script to mock battery for testing
BATTERY_MOCK_SCRIPT="/tmp/marathon-mock-battery.sh"
cat > "$BATTERY_MOCK_SCRIPT" << 'EOF'
#!/bin/bash
# Virtual battery mock for testing
# UPower will automatically detect this when run in test mode

echo "Virtual battery device active"
# This is a placeholder - UPower needs actual kernel devices
# For real testing, use: upower --dump to see available devices
EOF
chmod +x "$BATTERY_MOCK_SCRIPT"

echo "  ℹ  Virtual battery requires kernel-level device"
echo "  ℹ  Marathon Shell will use 'mains power' mode in VM"
echo " Battery mock script created: $BATTERY_MOCK_SCRIPT"

echo ""
echo "------------------------------------------------------------"
echo "STEP 5: Configuring Virtual Modem (ModemManager)"
echo "------------------------------------------------------------"

# Check if ofono-phonesim is available for virtual modem
if command -v ofono-phonesim &>/dev/null; then
    echo " ofono-phonesim available for virtual modem"
    echo "  ℹ  To start virtual modem: ofono-phonesim -p 12345 /path/to/phonesim.xml"
else
    echo "  ℹ  ofono-phonesim not installed (optional)"
    echo "  ℹ  Install with: sudo dnf install ofono-devel"
    echo "  ℹ  ModemManager will work without modems (mobile UI hidden)"
fi

echo ""
echo "------------------------------------------------------------"
echo "  STEP 6: Setting Permissions & RT Scheduling"
echo "------------------------------------------------------------"

# Add user to required groups
USER=$(whoami)
echo "Adding $USER to required groups..."
for group in video audio bluetooth input; do
    if getent group "$group" &>/dev/null; then
        if ! groups "$USER" | grep -q "\b$group\b"; then
            sudo usermod -a -G "$group" "$USER"
            echo " Added to group: $group"
        else
            echo " Already in group: $group"
        fi
    fi
done

# Configure RT scheduling limits
LIMITS_FILE="/etc/security/limits.d/99-marathon-shell.conf"
if [[ ! -f "$LIMITS_FILE" ]]; then
    echo "Configuring RT scheduling limits..."
    sudo tee "$LIMITS_FILE" > /dev/null << EOF
# Marathon Shell RT scheduling limits
$USER  -  rtprio  99
$USER  -  nice    -20
@audio -  rtprio  99
@audio -  nice    -20
EOF
    echo " RT limits configured: $LIMITS_FILE"
    echo "    Log out and back in for group/limit changes to take effect"
else
    echo " RT limits already configured"
fi

echo ""
echo "------------------------------------------------------------"
echo "STEP 7: Creating Test Environment Script"
echo "------------------------------------------------------------"

# Create a convenient test environment script
TEST_ENV_SCRIPT="$PROJECT_ROOT/run-with-services.sh"
cat > "$TEST_ENV_SCRIPT" << 'EOF'
#!/bin/bash
# Marathon Shell - Run with full service environment

echo " Starting Marathon Shell with full service environment..."
echo ""

# Check service status
echo "Service Status:"
for svc in NetworkManager bluetooth ModemManager upower geoclue; do
    status=$(systemctl is-active "$svc" 2>&1)
    if [[ "$status" == "active" ]]; then
        echo " $svc"
    else
        echo "    $svc ($status)"
    fi
done

echo ""
echo "-----------------------------------------------------------"
echo ""

# Export environment variables
export MARATHON_DEBUG=1
export QT_LOGGING_RULES="*.debug=true"

# Run the shell
exec "$(dirname "$0")/run.sh" "$@"
EOF
chmod +x "$TEST_ENV_SCRIPT"
echo " Created test environment script: $TEST_ENV_SCRIPT"

echo ""
echo "------------------------------------------------------------"
echo "STEP 8: Verification"
echo "------------------------------------------------------------"

echo ""
echo "System Services:"
for svc in NetworkManager bluetooth ModemManager upower geoclue iio-sensor-proxy; do
    if service_exists "$svc"; then
        status=$(systemctl is-active "$svc" 2>&1)
        case "$status" in
            active)
                echo "   $svc: running"
                ;;
            inactive)
                echo "  ⏸  $svc: inactive (will start on-demand)"
                ;;
            *)
                echo "    $svc: $status"
                ;;
        esac
    else
        echo "   $svc: not installed"
    fi
done

echo ""
echo "Available Devices:"
echo "  Network: $(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | wc -l) interfaces"
echo "  Power: $(upower -e 2>/dev/null | wc -l) devices"
echo "  Modems: $(mmcli -L 2>/dev/null | grep -c "No modems" && echo "0" || mmcli -L 2>/dev/null | grep -c "/Modem/")"

echo ""
echo "+------------------------------------------------------------+"
echo "|                     SETUP COMPLETE                               |"
echo "╠------------------------------------------------------------╣"
echo "|                                                                    |"
echo "|  Your Fedora system is now configured for Marathon Shell testing! |"
echo "|                                                                    |"
echo "|  Next Steps:                                                       |"
echo "|  1. Log out and back in (for group changes to take effect)        |"
echo "|  2. Run: ./run-with-services.sh                                   |"
echo "|  3. Or: MARATHON_DEBUG=1 ./run.sh                                 |"
echo "|                                                                    |"
echo "|  Expected Warnings on Desktop:                                    |"
echo "|  • No battery hardware (VM environment)                           |"
echo "|  • No modem hardware (no SIM card)                                |"
echo "|  • iio-sensor-proxy (no accelerometer)                            |"
echo "|  • RT scheduling (requires relogin)                               |"
echo "|                                                                    |"
echo "|  These are expected and will work on actual phone hardware!       |"
echo "|                                                                    |"
echo "+------------------------------------------------------------+"
echo ""

