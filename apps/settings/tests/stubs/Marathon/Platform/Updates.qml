pragma Singleton
import QtQml

QtObject {
    property string currentVersion: "r375"
    property string latestVersion: "r380"
    property string releaseUrl: "https://example.org/r380"
    property bool updateAvailable: true
    property bool checking: false
    property string lastError: ""
    property real lastCheckedMs: 1760000000000
    property string channel: "stable"
    property var calls: []

    function reset() {
        updateAvailable = true;
        checking = false;
        lastError = "";
        latestVersion = "r380";
        lastCheckedMs = 1760000000000;
        channel = "stable";
        calls = [];
    }
    function checkNow() {
        calls = calls.concat([["check"]]);
    }
    function openInBrowser() {
        calls = calls.concat([["open"]]);
    }
    function setChannel(c) {
        channel = c;
    }
}
