pragma Singleton
import QtQml

QtObject {
    property bool isWifiOn: true
    property bool isCellularDataOn: false
    property bool isBluetoothOn: false
    property bool isAirplaneModeOn: false
    property bool isDndMode: false
    property bool isFlashlightOn: false
    property bool isLocationOn: false
    property bool isHotspotOn: false
    property bool isNightLightOn: false
    property bool isRotationLocked: false
    property bool isAutoBrightnessOn: false
    property bool isLowPowerMode: false
    property bool isVibrationOn: true
    property var pendingSwitches: []
    property real brightness: 50
    property real volume: 50
    property string hotspotSsid: ""
    property string hotspotPassword: ""
    function setBrightnessFromUser(v) {
        brightness = v;
    }
    function setVolume(v) {
        volume = v;
    }
}
