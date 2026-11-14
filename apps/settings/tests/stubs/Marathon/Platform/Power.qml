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
    property bool hasAssistKey: true
    property bool hasTrackpad: true
    property var chargeHistory: []
    property var rateHistory: []
    signal historyChanged

    function loadHistory(hours) {
    }

    function reset() {
        batteryLevel = 80;
        isCharging = false;
        isPluggedIn = false;
        isPowerSaveMode = false;
        estimatedBatteryTime = 0;
        powerProfile = "balanced";
        powerProfilesSupported = true;
    }
    property string profileBeforeSaver: "balanced"

    function setPowerSaveMode(on) {
        if (on === isPowerSaveMode)
            return;
        if (on)
            profileBeforeSaver = powerProfile;
        powerProfile = on ? "power-saver" : profileBeforeSaver;
        isPowerSaveMode = on;
    }
    function setPowerProfile(profile) {
        powerProfile = profile;
    }
}
