pragma Singleton
import QtQml

QtObject {
    property int batteryLevel: 80
    property bool isCharging: false
    property bool isPluggedIn: false
    property bool isPowerSaveMode: false
    property int estimatedBatteryTime: 0
    property string powerProfile: "balanced"
    property bool powerProfilesSupported: true

    function reset() {
        batteryLevel = 80;
        isCharging = false;
        isPluggedIn = false;
        isPowerSaveMode = false;
        estimatedBatteryTime = 0;
        powerProfile = "balanced";
        powerProfilesSupported = true;
    }
    function setPowerSaveMode(on) {
        isPowerSaveMode = on;
    }
    function setPowerProfile(profile) {
        powerProfile = profile;
    }
}
