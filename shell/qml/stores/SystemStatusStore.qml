pragma Singleton
import QtQuick

QtObject {
    // batteryLevel and isCharging are already bound directly (line 8-9)
    // No need to update them here - direct bindings are more efficient
    // notificationCount is already bound to NotificationService.unreadCount at line 38
    // Switch to 1s updates after first tick

    id: systemStatus

    property int batteryLevel: (typeof PowerManagerService !== "undefined" && PowerManagerService) ? PowerManagerService.batteryLevel : 0
    property bool isCharging: (typeof PowerManagerService !== "undefined" && PowerManagerService) ? PowerManagerService.isCharging : false
    property bool isPluggedIn: (typeof PowerManagerService !== "undefined" && PowerManagerService) ? PowerManagerService.isPluggedIn : false
    property string chargingType: isCharging ? "usb" : "none"
    property bool isWifiOn: typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp ? NetworkManagerCpp.wifiEnabled : true
    property int wifiStrength: typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp ? NetworkManagerCpp.wifiSignalStrength : 0
    property string wifiNetwork: typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp ? NetworkManagerCpp.wifiSsid : ""
    property bool wifiConnected: typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp ? NetworkManagerCpp.wifiConnected : false
    property bool ethernetConnected: typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp ? NetworkManagerCpp.ethernetConnected : false
    property bool isBluetoothOn: typeof BluetoothManagerCpp !== "undefined" && BluetoothManagerCpp ? BluetoothManagerCpp.enabled : false
    property var bluetoothDevices: typeof BluetoothManagerCpp !== "undefined" && BluetoothManagerCpp ? BluetoothManagerCpp.pairedDevices : []
    readonly property int bluetoothConnectedDevicesCount: {
        var count = 0;
        var list = bluetoothDevices || [];
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].connected)
                count++;
        }
        return count;
    }
    readonly property bool isBluetoothConnected: bluetoothConnectedDevicesCount > 0
    property bool isAirplaneMode: typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp ? NetworkManagerCpp.airplaneModeEnabled : false
    property bool isDndMode: NotificationService.isDndEnabled
    property int cellularStrength: typeof ModemManagerCpp !== "undefined" && ModemManagerCpp ? ModemManagerCpp.signalStrength : 0
    property string carrier: typeof ModemManagerCpp !== "undefined" && ModemManagerCpp ? ModemManagerCpp.operatorName : ""
    property string dataType: typeof ModemManagerCpp !== "undefined" && ModemManagerCpp ? ModemManagerCpp.networkType : ""
    property int cpuUsage: 23
    property int memoryUsage: 45
    property real storageUsed: 45.2
    property real storageTotal: 128
    property date currentTime: new Date()
    property string timeString // Updated by timer, initialized on first tick
    property string dateString // Updated by timer, initialized on first tick
    property var notifications: []
    property int notificationCount: NotificationService.unreadCount
    property Timer updateTimer
    // Listen for time format changes using Connections (proper lifetime management)
    property Connections timeFormatConnection
    property Connections powerManagerConnections
    property Connections notificationServiceConnections

    function updateTime() {
        systemStatus.currentTime = new Date();
        // In strict app process isolation, apps may import MarathonOS.Shell QML but won't have
        // shell-only context properties like SettingsManagerCpp. Guard to avoid ReferenceError spam.
        var tf = (typeof SettingsManagerCpp !== "undefined" && SettingsManagerCpp) ? SettingsManagerCpp.timeFormat : "24h";
        systemStatus.timeString = Qt.formatTime(systemStatus.currentTime, tf === "24h" ? "HH:mm" : "h:mm AP");
        systemStatus.dateString = Qt.formatDate(systemStatus.currentTime, "dddd, MMMM d");
    }

    function addNotification(title, message, app) {
        NotificationService.sendNotification(app, title, message, {
            "category": "message",
            "priority": "normal"
        });
    }

    function removeNotification(notificationId) {
        NotificationService.dismissNotification(notificationId);
    }

    function clearAllNotifications() {
        NotificationService.dismissAllNotifications();
    }

    function updateSystemInfo() {
        cpuUsage = Math.floor(Math.random() * 30) + 10;
        memoryUsage = Math.floor(Math.random() * 20) + 35;
    }

    Component.onCompleted: {
        console.log("[SystemStatusStore] Initialized with real services");
        notifications = NotificationService.notifications;
    }

    updateTimer: Timer {
        interval: 16 // 60fps for immediate first update
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            updateTime();
            if (interval === 16)
                interval = 1000;
        }
    }

    timeFormatConnection: Connections {
        function onTimeFormatChanged() {
            updateTime();
        }

        target: typeof SettingsManagerCpp !== 'undefined' ? SettingsManagerCpp : null
    }

    powerManagerConnections: Connections {
        target: typeof PowerManagerService !== "undefined" ? PowerManagerService : null
    }

    notificationServiceConnections: Connections {
        function onNotificationReceived(notification) {
            notifications.push(notification);
            notifications = notifications;
        }

        function onNotificationDismissed(id) {
            notifications = notifications.filter(function (n) {
                return n.id !== id;
            });
            notificationCount = NotificationService.unreadCount;
        }

        target: NotificationService
    }
}
