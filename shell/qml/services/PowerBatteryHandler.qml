pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: root
    
    property int lastBatteryWarningLevel: 100
    property bool hasShownCriticalWarning: false
    property var errorToast: null
    property var shutdownCallback: null
    property var shutdownStopCallback: null
    
    function handleBatteryLevelChanged() {
        if (typeof PowerManager === 'undefined' || !PowerManager) {
            return
        }
        
        let level = PowerManager.batteryLevel
        let isCharging = PowerManager.isCharging
        
        if (isCharging) {
            root.lastBatteryWarningLevel = 100
            root.hasShownCriticalWarning = false
            if (root.shutdownStopCallback) {
                root.shutdownStopCallback()
            }
            return
        }
        
        if (level <= 3 && !root.hasShownCriticalWarning) {
            Logger.error("PowerBatteryHandler", "Critical battery level: " + level + "% - Initiating emergency shutdown")
            if (root.errorToast) {
                root.errorToast.show("Critical Battery", "Device will shutdown in 10 seconds to prevent data loss", "battery-warning")
            }
            if (typeof HapticService !== 'undefined') {
                HapticService.heavy()
            }
            root.hasShownCriticalWarning = true
            
            if (root.shutdownCallback) {
                root.shutdownCallback()
            }
        } else if (level <= 5 && root.lastBatteryWarningLevel > 5) {
            Logger.warn("PowerBatteryHandler", "Very low battery: " + level + "%")
            if (root.errorToast) {
                root.errorToast.show("Very Low Battery", level + "% remaining. Connect charger immediately.", "battery-warning")
            }
            if (typeof HapticService !== 'undefined') {
                HapticService.heavy()
            }
            root.lastBatteryWarningLevel = 5
        } else if (level <= 10 && root.lastBatteryWarningLevel > 10) {
            Logger.warn("PowerBatteryHandler", "Low battery: " + level + "%")
            if (root.errorToast) {
                root.errorToast.show("Low Battery", level + "% remaining. Connect charger soon.", "battery")
            }
            if (typeof HapticService !== 'undefined') {
                HapticService.medium()
            }
            root.lastBatteryWarningLevel = 10
        } else if (level <= 20 && root.lastBatteryWarningLevel > 20) {
            Logger.info("PowerBatteryHandler", "Battery getting low: " + level + "%")
            if (root.errorToast) {
                root.errorToast.show("Battery Low", level + "% remaining", "battery")
            }
            if (typeof HapticService !== 'undefined') {
                HapticService.light()
            }
            root.lastBatteryWarningLevel = 20
        }
    }
    
    function handlePowerButtonPress() {
        if (!DisplayManager.screenOn) {
            DisplayManager.turnScreenOn()
            HapticService?.medium()
            return
        }
    
        if (!SessionStore.isLocked) {
            SessionStore.lock()
            DisplayManager.turnScreenOff()
            HapticService?.medium()
            return
        }
    
        if (SessionStore.isLocked) {
            DisplayManager.turnScreenOff()
            HapticService?.medium()
            return
        }
    }
}

