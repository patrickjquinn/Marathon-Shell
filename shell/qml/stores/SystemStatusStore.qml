pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: systemStatus

    property int batteryLevel: PowerManager.batteryLevel
    property bool isCharging: PowerManager.isCharging
    property bool isPluggedIn: PowerManager.isPluggedIn
    property string chargingType: PowerManager.isCharging ? "usb" : "none"

    property bool isWifiOn: NetworkManager.wifiEnabled
    property int wifiStrength: NetworkManager.wifiSignalStrength
    property string wifiNetwork: NetworkManager.wifiSsid
    property bool wifiConnected: NetworkManager.wifiConnected
    property bool ethernetConnected: NetworkManager.ethernetConnected

    property bool isBluetoothOn: NetworkManager.bluetoothEnabled
    property bool isBluetoothConnected: NetworkManager.bluetoothConnectedDevices > 0
    property var bluetoothDevices: NetworkManager.pairedBluetoothDevices

    property bool isAirplaneMode: NetworkManager.airplaneModeEnabled
    property bool isDndMode: NotificationService.isDndEnabled

    property int cellularStrength: NetworkManager.cellularSignalStrength
    property string carrier: NetworkManager.cellularOperator
    property string dataType: NetworkManager.cellularTechnology

    property int cpuUsage: 23
    property int memoryUsage: 45
    property real storageUsed: 45.2
    property real storageTotal: 128.0

    property date currentTime: new Date()
    property string timeString  // Updated by timer, initialized on first tick
    property string dateString  // Updated by timer, initialized on first tick

    property var notifications: []
    property int notificationCount: NotificationService.unreadCount

    property Timer updateTimer: Timer {
        interval: 16  // 60fps for immediate first update
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            updateTime();
            if (interval === 16) {
                interval = 1000;  // Switch to 1s updates after first tick
            }
        }
    }

    // Listen for time format changes using Connections (proper lifetime management)
    property Connections timeFormatConnection: Connections {
        target: typeof SettingsManagerCpp !== 'undefined' ? SettingsManagerCpp : null
        function onTimeFormatChanged() {
            updateTime();
        }
    }

    function updateTime() {
        systemStatus.currentTime = new Date();
        systemStatus.timeString = Qt.formatTime(systemStatus.currentTime, SettingsManagerCpp.timeFormat === "24h" ? "HH:mm" : "h:mm AP");
        systemStatus.dateString = Qt.formatDate(systemStatus.currentTime, "dddd, MMMM d");
    }

    function addNotification(title, message, app) {
        NotificationService.sendNotification(app, title, message, {
            category: "message",
            priority: "normal"
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

    property Connections powerManagerConnections: Connections {
        target: PowerManager
        // batteryLevel and isCharging are already bound directly (line 8-9)
        // No need to update them here - direct bindings are more efficient
    }

    property Connections networkManagerConnections: Connections {
        target: NetworkManager
        function onWifiEnabledChanged() {
            isWifiOn = NetworkManager.wifiEnabled;
        }
        function onWifiSsidChanged() {
            wifiNetwork = NetworkManager.wifiSsid;
        }
        function onBluetoothEnabledChanged() {
            isBluetoothOn = NetworkManager.bluetoothEnabled;
        }
    }

    property Connections notificationServiceConnections: Connections {
        target: NotificationService
        function onNotificationReceived(notification) {
            notifications.push(notification);
            notifications = notifications;
        // notificationCount is already bound to NotificationService.unreadCount at line 38
        }
        function onNotificationDismissed(id) {
            notifications = notifications.filter(function (n) {
                return n.id !== id;
            });
            notificationCount = NotificationService.unreadCount;
        }
    }

    Component.onCompleted: {
        console.log("[SystemStatusStore] Initialized with real services");
        notifications = NotificationService.notifications;
    }
}
