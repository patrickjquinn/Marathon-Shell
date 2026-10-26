pragma Singleton
import QtQml
QtObject {
    property int appGridColumns: 0
    property string wallpaperPath: ""
    property real userScaleFactor: 1
    property bool reduceMotion: false
    property bool firstRunComplete: false
    property string language: ""
    property string timeFormat: "12h"
    readonly property var availableLanguages: [
        { code: "en", nativeName: "English", englishName: "English", status: "complete" },
        { code: "de", nativeName: "Deutsch", englishName: "German", status: "preview" },
        { code: "fr", nativeName: "Français", englishName: "French", status: "preview" },
        { code: "es", nativeName: "Español", englishName: "Spanish", status: "preview" },
        { code: "ga", nativeName: "Gaeilge", englishName: "Irish", status: "preview" }
    ]
    property int screenTimeout: 0
    property string timeZone: "Europe/Dublin"
    property bool automaticTimeZone: true
    property bool showNotificationBadges: true
    property bool keyboardAutoCapitalize: true
    property bool keyboardAutoCorrection: true
    property bool keyboardPredictiveText: true
    property var enabledQuickSettingsTiles: ["wifi", "cellular", "bluetooth", "airplane", "dnd", "torch", "location", "hotspot", "nightlight", "rotation", "autobrightness", "lowpower", "vibration", "power"]
    property var store: ({})
    function get(key, fallback) { return key in store ? store[key] : fallback; }
    function set(key, value) { store[key] = value; }
}
