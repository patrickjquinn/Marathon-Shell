pragma Singleton
import QtQml

// Mirrors src/MmsSettings: mmsd-tng's carrier settings, set by the tests.
QtObject {
    property bool available: true
    property bool loaded: true
    property string mmsc: ""
    property string apn: ""
    property string proxy: ""
    property bool autoDownload: true
    property var calls: []
    property string error: ""

    signal saved
    signal failed(string error)

    function reset() {
        available = true;
        loaded = true;
        mmsc = "http://mms.vodafone.ie/servlets/mms";
        apn = "live.vodafone.com";
        proxy = "10.24.59.200:80";
        autoDownload = true;
        calls = [];
        error = "";
    }
    function refresh() {
        calls = calls.concat([["refresh"]]);
    }
    function save(newMmsc, newApn, newProxy) {
        calls = calls.concat([["save", newMmsc, newApn, newProxy]]);
        if (error !== "") {
            failed(error);
            return;
        }
        mmsc = newMmsc;
        apn = newApn;
        proxy = newProxy;
        saved();
    }
    function setAutoDownload(on) {
        calls = calls.concat([["setAutoDownload", on]]);
        autoDownload = on;
    }
}
