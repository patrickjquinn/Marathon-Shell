#!/bin/bash
# Check if required system services are running
# Run this before starting Marathon Shell on a new system

echo "🔍 Checking Marathon Shell System Requirements..."
echo ""

# Function to check D-Bus service
check_dbus_service() {
    local service=$1
    local name=$2
    if busctl --system status "$service" &>/dev/null 2>&1; then
        echo "✅ $name - Running"
        return 0
    else
        echo "❌ $name - Not running or not installed"
        return 1
    fi
}

# Check system D-Bus services
echo "📡 System D-Bus Services:"
check_dbus_service "org.freedesktop.NetworkManager" "NetworkManager (WiFi/Ethernet)"
check_dbus_service "org.freedesktop.UPower" "UPower (Battery)"
check_dbus_service "org.freedesktop.ModemManager1" "ModemManager (Cellular)"
check_dbus_service "org.freedesktop.login1" "systemd-logind (Power management)"
check_dbus_service "org.bluez" "BlueZ (Bluetooth)"
check_dbus_service "org.freedesktop.GeoClue2" "GeoClue2 (Location services)"

echo ""
echo "🎮 Hardware Access:"

# Check backlight
if ls /sys/class/backlight/*/brightness &>/dev/null; then
    echo "✅ Backlight devices found"
    ls /sys/class/backlight/
else
    echo "⚠️  No backlight devices (normal for VMs)"
fi

# Check IIO sensors
if ls /sys/bus/iio/devices/ &>/dev/null 2>&1; then
    echo "✅ IIO sensors available"
else
    echo "⚠️  No IIO sensors (normal for VMs)"
fi

# Check PulseAudio
if pactl info &>/dev/null; then
    echo "✅ PulseAudio/PipeWire running"
else
    echo "❌ PulseAudio/PipeWire not running"
fi

echo ""
echo "🚀 To start missing services (on Alpine/postmarketOS):"
echo "   sudo rc-service networkmanager start"
echo "   sudo rc-service modemmanager start"
echo "   sudo rc-service upower start"
echo "   sudo rc-service bluetooth start"
echo "   sudo rc-service geoclue start"
echo ""

