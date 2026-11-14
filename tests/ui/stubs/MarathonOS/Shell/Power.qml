pragma Singleton
import QtQml

QtObject {
    property bool hasActiveCalls: false
    property bool isCharging: false
    property bool isPowerSaveMode: false
    property string powerProfile: "balanced"
}
