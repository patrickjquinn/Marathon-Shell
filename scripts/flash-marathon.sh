#!/bin/bash
# Marathon OS Flash Script

set -e

echo "=== Marathon OS Flash Script ==="
echo ""
echo "⚠️  Make sure your device is in fastboot mode!"
echo "    (Power + Volume Down)"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

cd "$(dirname "$0")"

echo ""
echo "Flashing boot image..."
fastboot flash boot out/enchilada/boot-MARATHON-FINAL.img

echo ""
echo "Flashing root filesystem..."
fastboot flash userdata out/enchilada/oneplus-enchilada-MARATHON-FINAL.img

echo ""
echo "✅ Flash complete!"
echo ""
echo "Rebooting device..."
fastboot reboot

echo ""
echo "🎉 Marathon OS is booting!"
echo ""
echo "Expected boot time: ~20-25 seconds"
echo "Marathon Shell will start automatically"
echo ""
echo "SSH access: ssh user@172.16.101.2"
echo "Password: 147147"
echo ""
