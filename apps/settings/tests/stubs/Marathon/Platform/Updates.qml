pragma Singleton
import QtQml

QtObject {
    property string state: "available"
    property string currentVersion: "r375"
    property string osVersion: "26101701"
    property string availableVersion: "26101801"
    property real downloadSize: 1500000000
    property string releaseNotes: "Faster boot"
    property int progress: 0
    property string blockedReason: ""
    property string rolledBackVersion: ""
    readonly property bool updateAvailable: state === "available"
    property string lastError: ""
    property real lastCheckedMs: 1760000000000
    property var calls: []

    function reset() {
        state = "available";
        availableVersion = "26101801";
        downloadSize = 1500000000;
        releaseNotes = "Faster boot";
        progress = 0;
        blockedReason = "";
        rolledBackVersion = "";
        lastError = "";
        lastCheckedMs = 1760000000000;
        calls = [];
    }
    function checkNow() {
        calls = calls.concat([["check"]]);
    }
    function install() {
        calls = calls.concat([["install"]]);
    }
    function cancel() {
        calls = calls.concat([["cancel"]]);
    }
    function reboot() {
        calls = calls.concat([["reboot"]]);
    }
}
