pragma Singleton
import QtQuick

QtObject {
    id: statusBarIconService
    
    function getBatteryIcon(level, isCharging) {
        if (isCharging) {
            return "battery-charging"
        }
        
        if (level <= 10) {
            return "battery-low"
        } else if (level <= 25) {
            return "battery-low"
        } else if (level <= 50) {
            return "battery-medium"
        } else if (level <= 90) {
            return "battery-medium"
        } else {
            return "battery-full"
        }
    }
    
    function getBatteryColor(level, isCharging) {
        if (isCharging) {
            return "#00CCCC"
        }
        
        if (level <= 10) {
            return "#FF4444"
        } else if (level <= 20) {
            return "#FF8800"
        } else {
            return "#FFFFFF"
        }
    }
    
    function getSignalIcon(strength) {
        return "signal"
    }
    
    function getSignalOpacity(strength) {
        if (strength <= 0) return 0.3
        if (strength <= 25) return 0.4
        if (strength <= 50) return 0.6
        if (strength <= 75) return 0.8
        return 1.0
    }
    
    function getWifiIcon(isEnabled, strength) {
        return "wifi"
    }
    
    function getWifiOpacity(isEnabled, strength) {
        if (!isEnabled) return 0.3
        
        if (strength <= 0) return 0.3
        if (strength <= 25) return 0.5
        if (strength <= 50) return 0.7
        if (strength <= 75) return 0.85
        return 1.0
    }
    
    function getBluetoothIcon(isEnabled, isConnected) {
        return "bluetooth"
    }
    
    function getBluetoothOpacity(isEnabled, isConnected) {
        if (!isEnabled) return 0.3
        if (isConnected) return 1.0
        return 0.6
    }
    
    function shouldShowAirplaneMode(isEnabled) {
        return isEnabled
    }
    
    function shouldShowDND(isEnabled) {
        return isEnabled
    }
    
    function shouldShowBluetooth(isEnabled) {
        return isEnabled
    }
}

