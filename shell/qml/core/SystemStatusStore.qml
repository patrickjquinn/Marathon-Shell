pragma Singleton
import QtQuick
import MarathonOS.Shell

// What the status bar shows, from the shell's system objects.
QtObject {
    id: root

    readonly property int batteryLevel: Power.batteryLevel
    readonly property bool isCharging: Power.isCharging
    readonly property bool isPluggedIn: Power.isPluggedIn
    readonly property bool isWifiOn: Network.wifiEnabled
    readonly property int wifiStrength: Network.wifiSignalStrength
    readonly property string wifiNetwork: Network.wifiSsid
    readonly property bool wifiConnected: Network.wifiConnected
    readonly property bool ethernetConnected: Network.ethernetConnected
    readonly property bool isBluetoothOn: BluetoothManagerCpp.enabled
    readonly property bool isBluetoothConnected: BluetoothManagerCpp.pairedDevices.some(d => d.connected)
    readonly property bool isAirplaneMode: Network.airplaneModeEnabled
    readonly property bool isDndMode: SettingsManagerCpp.dndEnabled
    readonly property int cellularStrength: Modem.signalStrength
    readonly property string carrier: Modem.operatorName
    readonly property string dataType: Modem.networkType

    property date currentTime: new Date()
    readonly property string timeString: Qt.formatTime(currentTime, SettingsManagerCpp.timeFormat === "24h" ? "HH:mm" : "h:mm AP")
    readonly property string dateString: currentTime.toLocaleDateString(Qt.locale(), Locale.LongFormat)

    // Fires on each minute's turn, when the shown time changes.
    readonly property Timer clock: Timer {
        running: true
        repeat: true
        interval: 60000 - (root.currentTime.getSeconds() * 1000 + root.currentTime.getMilliseconds()) + 5
        onTriggered: root.currentTime = new Date()
    }

    readonly property Connections zone: Connections {
        function onTimeZoneChanged() {
            root.currentTime = new Date();
        }

        target: SettingsManagerCpp
    }
}
