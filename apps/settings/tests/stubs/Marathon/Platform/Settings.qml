pragma Singleton
import QtQml

QtObject {
    property string timeZone: "Europe/London"
    property string timeFormat: "24h"
    property var hiddenApps: []
    property int appGridColumns: 0
    property bool dndEnabled: false
    property bool reduceMotion: false
    property real userScaleFactor: 1
    property int screenTimeout: 60000
    property string ringtone: "/sounds/ring_classic.wav"
    property string notificationSound: "/sounds/chime.wav"
    property string alarmSound: "/sounds/alarm_dawn.wav"
    property bool showNotificationsOnLockScreen: true
    property bool filterMobileFriendlyApps: true
    property bool searchNativeApps: false
    property bool showNotificationBadges: true
    property var enabledQuickSettingsTiles: ["wifi", "bluetooth"]
    property string deviceName: "Librem 5"
    property int autoLockTimeout: 0
    property bool automaticTime: true
    property var systemTimes: []
    property bool vibrationEnabled: true

    signal dateTimeChangeFailed(string reason)

    function setSystemTime(ms) {
        systemTimes = systemTimes.concat([ms]);
    }

    function reset() {
        timeZone = "Europe/London";
        timeFormat = "24h";
        hiddenApps = [];
        appGridColumns = 0;
        dndEnabled = false;
        reduceMotion = false;
        userScaleFactor = 1;
        screenTimeout = 60000;
        ringtone = "/sounds/ring_classic.wav";
        notificationSound = "/sounds/chime.wav";
        alarmSound = "/sounds/alarm_dawn.wav";
        showNotificationsOnLockScreen = true;
        filterMobileFriendlyApps = true;
        searchNativeApps = false;
        showNotificationBadges = true;
        enabledQuickSettingsTiles = ["wifi", "bluetooth"];
        deviceName = "Librem 5";
        autoLockTimeout = 0;
        automaticTime = true;
        systemTimes = [];
        vibrationEnabled = true;
    }
    function availableRingtones() {
        return ["/sounds/ring_classic.wav", "/sounds/ring_bright.wav"];
    }
    function availableNotificationSounds() {
        return ["/sounds/chime.wav", "/sounds/pop.wav"];
    }
    function availableAlarmSounds() {
        return ["/sounds/alarm_dawn.wav", "/sounds/alarm_bell.wav"];
    }
    function screenTimeoutOptions() {
        return ["30 seconds", "1 minute", "2 minutes", "5 minutes", "Never"];
    }
    function screenTimeoutValue(option) {
        return { "30 seconds": 30000, "1 minute": 60000, "2 minutes": 120000, "5 minutes": 300000, "Never": 0 }[option];
    }
    function formatSoundName(path) {
        const base = String(path).split("/").pop().replace(/\.[a-z0-9]+$/, "").replace("alarm_", "").replace("ring_", "");
        return base.charAt(0).toUpperCase() + base.slice(1);
    }
}
