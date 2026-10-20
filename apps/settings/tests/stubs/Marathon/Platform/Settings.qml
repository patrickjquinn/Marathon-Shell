pragma Singleton
import QtQml

QtObject {
    property string timeZone: "Europe/London"
    property string wallpaperPath: "file:///wallpapers/slate-aurora.svg"
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
    property real ringtoneVolume: 0.8
    property real notificationVolume: 0.7
    property real alarmVolume: 0.9
    property bool showNotificationsOnLockScreen: true
    property bool filterMobileFriendlyApps: true
    property bool searchNativeApps: false
    property bool showNotificationBadges: true
    property var enabledQuickSettingsTiles: ["wifi", "bluetooth"]
    property string deviceName: "Librem 5"
    property int autoLockTimeout: 0
    property bool automaticTime: true
    property bool automaticTimeZone: true
    property var systemTimes: []
    property bool vibrationEnabled: true

    signal dateTimeChangeFailed(string reason)

    function setSystemTime(ms) {
        systemTimes = systemTimes.concat([ms]);
    }

    function reset() {
        timeZone = "Europe/London";
        wallpaperPath = "file:///wallpapers/slate-aurora.svg";
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
        ringtoneVolume = 0.8;
        notificationVolume = 0.7;
        alarmVolume = 0.9;
        showNotificationsOnLockScreen = true;
        filterMobileFriendlyApps = true;
        searchNativeApps = false;
        showNotificationBadges = true;
        enabledQuickSettingsTiles = ["wifi", "bluetooth"];
        deviceName = "Librem 5";
        autoLockTimeout = 0;
        automaticTime = true;
        automaticTimeZone = true;
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
    function formatSoundName(path) {
        const base = String(path).split("/").pop().replace(/\.[a-z0-9]+$/, "").replace("alarm_", "").replace("ring_", "");
        return base.charAt(0).toUpperCase() + base.slice(1);
    }
}
