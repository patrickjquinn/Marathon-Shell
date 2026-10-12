pragma Singleton
import QtQml

QtObject {
    property bool available: true
    property bool simPresent: true
    property bool registered: true
    property string operatorName: "Vodafone"
    property int signalStrength: 80
    property string networkType: "LTE"
    property bool roaming: false
    property bool dataEnabled: false
    property bool dataRoamingAllowed: false
    property var supportedModes: [14, 6, 2]
    property int allowedModes: 14

    function reset() {
        available = true;
        simPresent = true;
        registered = true;
        operatorName = "Vodafone";
        signalStrength = 80;
        networkType = "LTE";
        roaming = false;
        dataEnabled = false;
        dataRoamingAllowed = false;
        supportedModes = [14, 6, 2];
        allowedModes = 14;
    }
    function enableData() {
        dataEnabled = true;
    }
    function disableData() {
        dataEnabled = false;
    }
    function setDataRoamingAllowed(allowed) {
        dataRoamingAllowed = allowed;
    }
    function setAllowedModes(mask) {
        allowedModes = mask;
    }
}
