pragma Singleton
import QtQuick

QtObject {
    id: systemStatus
    
    // Battery
    property int batteryLevel: 85
    property bool isCharging: false
    property string chargingType: "none" // none, usb, wireless
    
    // WiFi
    property bool isWifiOn: true
    property int wifiStrength: 75
    property string wifiNetwork: "Home Network"
    
    // Bluetooth
    property bool isBluetoothOn: false
    property var bluetoothDevices: []
    
    // Cellular
    property int cellularStrength: 80
    property string carrier: "AT&T"
    property string dataType: "5G"
    
    // System
    property int cpuUsage: 23
    property int memoryUsage: 45
    property real storageUsed: 45.2
    property real storageTotal: 128.0
    
    // Time/Date
    property date currentTime: new Date()
    property string timeString: Qt.formatTime(currentTime, "h:mm")
    property string dateString: Qt.formatDate(currentTime, "dddd, MMMM d")
    
    // Notifications
    property var notifications: []
    property int notificationCount: 0
    
    // Update timer
    property Timer updateTimer: Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            systemStatus.currentTime = new Date()
            systemStatus.timeString = Qt.formatTime(systemStatus.currentTime, "h:mm")
            systemStatus.dateString = Qt.formatDate(systemStatus.currentTime, "dddd, MMMM d")
            
            // Simulate battery drain
            if (!systemStatus.isCharging && systemStatus.batteryLevel > 0) {
                if (Math.random() < 0.01) { // 1% chance per second
                    systemStatus.batteryLevel = Math.max(0, systemStatus.batteryLevel - 1)
                }
            }
        }
    }
    
    // Methods
    function addNotification(title, message, app) {
        var notification = {
            id: Date.now().toString(),
            title: title,
            message: message,
            app: app,
            timestamp: new Date()
        }
        notifications.push(notification)
        notifications = notifications // Trigger property change
        notificationCount = notifications.length
    }
    
    function removeNotification(notificationId) {
        notifications = notifications.filter(n => n.id !== notificationId)
        notificationCount = notifications.length
    }
    
    function clearAllNotifications() {
        notifications = []
        notificationCount = 0
    }
    
    function updateSystemInfo() {
        // Simulate system updates
        cpuUsage = Math.floor(Math.random() * 30) + 10
        memoryUsage = Math.floor(Math.random() * 20) + 35
    }
    
    Component.onCompleted: {
        // Add some initial mock notifications
        addNotification("Email", "New message from John", "Mail")
        addNotification("Messages", "Hey, how are you?", "Messages")
    }
}

