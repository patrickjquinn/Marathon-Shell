pragma Singleton
import QtQuick

QtObject {
    id: statusBarIconService

    function getBatteryIcon(level, isCharging) {
        if (isCharging) {
            return "battery-charging";
        }

        // 5-level granular battery display
        if (level <= 10) {
            return "battery-warning";  // Critical (red)
        } else if (level <= 25) {
            return "battery-low";      // Low (orange)
        } else if (level <= 50) {
            return "battery-medium";   // Medium
        } else if (level <= 90) {
            return "battery-full";     // Full
        } else {
            return "battery-full";     // 91-100%
        }
    }

    function getBatteryColor(level, isCharging) {
        if (isCharging) {
            return "#00CCCC";
        }

        if (level <= 10) {
            return "#FF4444";
        } else if (level <= 20) {
            return "#FF8800";
        } else {
            return "#FFFFFF";
        }
    }

    function getSignalIcon(strength) {
        // 5-level granular cellular signal display
        if (strength === 0)
            return "signal-zero";
        if (strength <= 25)
            return "signal-low";      // 1 bar
        if (strength <= 50)
            return "signal-medium";   // 2 bars
        if (strength <= 75)
            return "signal";          // 3 bars (good)
        return "signal-high";                         // 4 bars (excellent)
    }

    function getSignalOpacity(strength) {
        // Icon shows signal level, opacity shows overall status
        if (strength === 0)
            return 0.3;   // No signal
        if (strength <= 25)
            return 0.6;   // Poor
        if (strength <= 50)
            return 0.8;   // Fair
        if (strength <= 75)
            return 0.9;   // Good
        return 1.0;                        // Excellent
    }

    function getWifiIcon(isEnabled, strength, isConnected) {
        // 4-level granular WiFi signal display
        if (!isEnabled)
            return "wifi-off";
        if (!isConnected)
            return "wifi-off";

        if (strength === 0)
            return "wifi-zero";   // Connected but no signal
        if (strength <= 33)
            return "wifi-low";     // 1-2 bars (weak)
        if (strength <= 66)
            return "wifi";         // 2-3 bars (good) - use base icon
        return "wifi-high";                        // 3-4 bars (excellent)
    }

    function getWifiOpacity(isEnabled, strength, isConnected) {
        // Icon shows signal level, opacity shows overall status
        if (!isEnabled || !isConnected)
            return 0.3;

        if (strength === 0)
            return 0.4;   // Connected but no signal
        if (strength <= 33)
            return 0.6;   // Weak
        if (strength <= 66)
            return 0.8;   // Good
        return 1.0;                        // Excellent
    }

    function getBluetoothIcon(isEnabled, isConnected) {
        return "bluetooth";
    }

    function getBluetoothOpacity(isEnabled, isConnected) {
        if (!isEnabled)
            return 0.3;
        if (isConnected)
            return 1.0;
        return 0.6;
    }

    function shouldShowAirplaneMode(isEnabled) {
        return isEnabled;
    }

    function shouldShowDND(isEnabled) {
        return isEnabled;
    }

    function shouldShowBluetooth(isEnabled) {
        return isEnabled;
    }
}
