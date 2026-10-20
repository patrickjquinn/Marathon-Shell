pragma Singleton
import QtQml
QtObject {
    property int cancelledConnects: 0
    property var availableNetworks: []
    property bool wifiConnected: false
    property string wifiSsid: ""
    signal connectionSuccess
    signal connectionFailed(string message)
    function cancelPendingConnection() { cancelledConnects++; }
    function scanWifi() {}
    function connectToNetwork(ssid, password) {}
}
