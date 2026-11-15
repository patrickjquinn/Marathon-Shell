pragma Singleton
import QtQml

QtObject {
    property bool hasActiveCalls: false
    property bool isCharging: false
    property bool isPluggedIn: false
    property int batteryLevel: 82
    property bool isPowerSaveMode: false
    property string powerProfile: "balanced"
}
