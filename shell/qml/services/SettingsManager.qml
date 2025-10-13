pragma Singleton

import QtQuick
import QtCore

QtObject {
    id: settingsManager
    
    // Qt Settings provides automatic persistence to disk
    property Settings settings: Settings {
        category: "System"
        
        property string deviceName: "Marathon OS"
        property string notificationSound: "Default"
        property bool autoLock: true
        property int autoLockTimeout: 300 // seconds
        property string wallpaper: "default"
        property bool showNotificationPreviews: true
        property string timeFormat: "12h" // "12h" or "24h"
        property string dateFormat: "US" // "US" or "EU"
    }
    
    // Expose settings as read-only properties
    readonly property string deviceName: settings.deviceName
    readonly property string notificationSound: settings.notificationSound
    readonly property bool autoLock: settings.autoLock
    readonly property int autoLockTimeout: settings.autoLockTimeout
    readonly property string wallpaper: settings.wallpaper
    readonly property bool showNotificationPreviews: settings.showNotificationPreviews
    readonly property string timeFormat: settings.timeFormat
    readonly property string dateFormat: settings.dateFormat
    
    // Setters
    function setDeviceName(name) {
        console.log("[SettingsManager] Setting device name:", name)
        settings.deviceName = name
        settings.sync() // Force write to disk
        Logger.info("SettingsManager", "Device name set to: " + name)
    }
    
    function setNotificationSound(sound) {
        console.log("[SettingsManager] Setting notification sound:", sound)
        settings.notificationSound = sound
        settings.sync()
        Logger.info("SettingsManager", "Notification sound set to: " + sound)
    }
    
    function setAutoLock(enabled) {
        settings.autoLock = enabled
        settings.sync()
        Logger.info("SettingsManager", "Auto-lock set to: " + enabled)
    }
    
    function setAutoLockTimeout(seconds) {
        settings.autoLockTimeout = seconds
        settings.sync()
        Logger.info("SettingsManager", "Auto-lock timeout set to: " + seconds)
    }
    
    function setWallpaper(wallpaper) {
        settings.wallpaper = wallpaper
        settings.sync()
        Logger.info("SettingsManager", "Wallpaper set to: " + wallpaper)
    }
    
    function setShowNotificationPreviews(show) {
        settings.showNotificationPreviews = show
        settings.sync()
        Logger.info("SettingsManager", "Show notification previews set to: " + show)
    }
    
    function setTimeFormat(format) {
        settings.timeFormat = format
        settings.sync()
        Logger.info("SettingsManager", "Time format set to: " + format)
    }
    
    function setDateFormat(format) {
        settings.dateFormat = format
        settings.sync()
        Logger.info("SettingsManager", "Date format set to: " + format)
    }
    
    Component.onCompleted: {
        console.log("qml: [SettingsManager] Initialized")
        console.log("qml: [SettingsManager] Device name:", deviceName)
        console.log("qml: [SettingsManager] Notification sound:", notificationSound)
    }
}

