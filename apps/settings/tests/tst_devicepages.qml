import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0
import ".."

TestCase {
    id: testCase

    name: "DevicePages"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: appComponent

        SettingsApp {
            width: 540
            height: 1140
        }
    }

    function init() {
        Settings.reset();
        Display.reset();
        Haptics.reset();
        Modem.reset();
        Audio.reset();
        Power.reset();
        KeyboardSettingsStore.reset();
        SettingsController.reset();
    }

    function open(name) {
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null);
        verify(app.openPage(name, PageStackAction.Immediate));
        const page = app.pageStack.currentPage;
        tryCompare(page, "status", PageStatus.Active);
        return { app: app, page: page };
    }

    function child(parent, name) {
        let item = null;
        tryVerify(() => (item = findChild(parent, name)) !== null, 3000, name);
        return item;
    }

    function pushed(app, from) {
        tryVerify(() => app.pageStack.currentPage !== from && app.pageStack.currentPage.status === PageStatus.Active, 3000);
        return app.pageStack.currentPage;
    }

    // Picks a ComboBox entry the way a tap on its menu item does.
    function pick(combo, index) {
        let n = 0;
        let found = null;
        combo.menu._foreachMenuItem(function (item) {
            if (n++ === index)
                found = item;
            return found === null;
        });
        verify(found !== null);
        found.clicked();
    }

    function test_display() {
        const s = open("display");
        const slider = child(s.page, "brightnessSlider");
        compare(slider.value, 50);
        Display.brightness = 0.8;
        compare(slider.value, 80);
        s.page.setBrightness(25);
        compare(Display.brightness, 0.25);

        child(s.page, "autoBrightnessSwitch").clicked(null);
        verify(Display.autoBrightnessEnabled);
        child(s.page, "rotationSwitch").clicked(null);
        verify(Display.rotationLocked);
        child(s.page, "reduceMotionSwitch").clicked(null);
        verify(Settings.reduceMotion);

        const timeout = child(s.page, "timeoutCombo");
        compare(timeout.currentIndex, 1);
        pick(timeout, 3);
        compare(Settings.screenTimeout, 300000);
        Settings.screenTimeout = 30000;
        compare(timeout.currentIndex, 0);

        const scale = child(s.page, "scaleCombo");
        compare(scale.currentIndex, 2);
        pick(scale, 4);
        compare(Settings.userScaleFactor, 1.25);

        compare(findChild(s.page, "clockCombo"), null);

        compare(findChild(s.page, "wallpaperButton"), null);
    }

    function test_displayHidesAbsentSensors() {
        Display.lightSensorAvailable = false;
        Display.rotationAvailable = false;
        const s = open("display");
        verify(!child(s.page, "autoBrightnessSwitch").visible);
        verify(!child(s.page, "rotationSwitch").visible);
        verify(child(s.page, "reduceMotionSwitch").visible);
    }

    function test_noModemNoRingtone() {
        Modem.available = false;
        const page = open("sound").page;
        verify(!child(page, "ringtoneButton").visible);
        verify(child(page, "notificationSoundButton").visible);
    }

    function test_noVibrator() {
        Haptics.available = false;
        verify(!child(open("sound").page, "vibrationSwitch").visible);
        verify(!child(open("keyboard").page, "hapticSwitch").visible);
    }

    function test_ambience() {
        const page = open("ambience").page;
        const grid = child(page, "ambienceGrid");
        compare(grid.count, 2);
        verify(!child(page, "placeholder").enabled);
        verify(child(page, "ambience-Slate Aurora").current);
        const dawn = child(page, "ambience-Dawn");
        verify(!dawn.current);
        dawn.clicked(null);
        compare(Settings.wallpaperPath, "file:///wallpapers/dawn.svg");
        verify(dawn.current);
    }

    function test_sounds() {
        const s = open("sound");
        const volume = child(s.page, "volumeSlider");
        compare(volume.value, 40);
        s.page.setVolume(70);
        compare(Audio.volume, 0.7);
        const muteSwitch = child(s.page, "muteSwitch");
        verify(!muteSwitch.checked);
        muteSwitch.clicked(null);
        verify(Audio.muted);
        verify(muteSwitch.checked);
        compare(volume.valueText, "Muted");
        muteSwitch.clicked(null);
        verify(!Audio.muted);
        compare(child(s.page, "ringtoneButton").value, "Classic");

        // The tones' own levels, apart from the media volume.
        compare(child(s.page, "alarmVolumeSlider").value, 90);
        compare(child(s.page, "notificationVolumeSlider").value, 70);
        s.page.setToneVolume("alarmVolume", 15);
        compare(Settings.alarmVolume, 0.15);
        compare(child(s.page, "alarmVolumeSlider").value, 15);
        s.page.setToneVolume("ringtoneVolume", 120);
        compare(Settings.ringtoneVolume, 1);
        const vibration = child(s.page, "vibrationSwitch");
        verify(vibration.checked);
        vibration.clicked(null);
        verify(!Settings.vibrationEnabled);
        verify(!vibration.checked);

        Audio.streams.append({ streamId: 7, appName: "Music", volume: 0.5, muted: false });
        const mute = child(s.page, "muteButton");
        mute.clicked(null);
        verify(Audio.streams.get(0).muted);

        child(s.page, "ringtoneButton").clicked(null);
        const picker = pushed(s.app, s.page);
        compare(child(picker, "soundList").count, 2);
        child(picker, "sound-Bright").clicked(null);
        compare(Settings.ringtone, "/sounds/ring_bright.wav");
        compare(Audio.previewed, ["/sounds/ring_bright.wav"]);
        verify(child(picker, "sound-Bright").selected);
    }

    function test_alarmSoundPicker() {
        const s = open("sound");
        child(s.page, "alarmSoundButton").clicked(null);
        const picker = pushed(s.app, s.page);
        compare(picker.title, "Alarm sound");
        child(picker, "sound-Bell").clicked(null);
        compare(Settings.alarmSound, "/sounds/alarm_bell.wav");
        compare(Settings.ringtone, "/sounds/ring_classic.wav");
    }

    function test_notifications() {
        const s = open("notifications");
        child(s.page, "dndSwitch").clicked(null);
        verify(Settings.dndEnabled);
        verify(Audio.doNotDisturb);
        child(s.page, "lockScreenSwitch").clicked(null);
        verify(!Settings.showNotificationsOnLockScreen);
        compare(child(s.page, "appSwitches").count, 2);
        const weather = child(s.page, "notify-weather");
        verify(!weather.checked);
        weather.clicked(null);
        compare(SettingsController.calls, [["notify", "weather", true]]);
        verify(child(s.page, "notify-weather").checked);
        child(s.page, "soundButton").clicked(null);
        const picker = pushed(s.app, s.page);
        compare(picker.soundType, "notification");
        child(picker, "sound-Pop").clicked(null);
        compare(Settings.notificationSound, "/sounds/pop.wav");
    }

    function test_dateTime() {
        const s = open("datetime");
        const clock = child(s.page, "clockSwitch");
        verify(clock.checked);
        clock.clicked(null);
        compare(Settings.timeFormat, "12h");
        compare(child(s.page, "zoneButton").value, "London (UTC+00:00)");
        child(s.page, "zoneButton").clicked(null);
        const zones = pushed(s.app, s.page);
        const list = child(zones, "zoneList");
        compare(list.count, 3);
        child(zones, "searchField").text = "new";
        compare(list.count, 1);
        child(zones, "searchField").text = "zzz";
        verify(child(zones, "placeholder").enabled);
        child(zones, "searchField").text = "ber";
        child(zones, "zone-Europe/Berlin").clicked(null);
        compare(Settings.timeZone, "Europe/Berlin");
        tryVerify(() => s.app.pageStack.currentPage === s.page);
        compare(child(s.page, "zoneButton").value, "Berlin (UTC+01:00)");
    }

    function test_automaticTimeZone() {
        const s = open("datetime");
        const auto = child(s.page, "automaticZoneSwitch");
        verify(auto.checked);
        verify(!child(s.page, "zoneButton").enabled);
        auto.clicked(null);
        verify(!Settings.automaticTimeZone);
        verify(!auto.checked);
        verify(child(s.page, "zoneButton").enabled);
        auto.clicked(null);
        verify(Settings.automaticTimeZone);
    }

    function test_timeZoneSearchTakesKeys() {
        const s = open("datetime");
        child(s.page, "zoneButton").clicked(null);
        const zones = pushed(s.app, s.page);
        const field = child(zones, "searchField");
        const list = child(zones, "zoneList");
        mouseClick(field);
        keyClick(Qt.Key_B);
        keyClick(Qt.Key_E);
        keyClick(Qt.Key_R);
        compare(field.text, "ber");
        compare(list.count, 1);
        verify(field.activeFocus);
    }

    function test_automaticAndManualTime() {
        const s = open("datetime");
        const auto = child(s.page, "automaticSwitch");
        verify(auto.checked);
        verify(!child(s.page, "timeButton").enabled);
        verify(!child(s.page, "dateButton").enabled);
        auto.clicked(null);
        verify(!Settings.automaticTime);
        verify(child(s.page, "timeButton").enabled);
        child(s.page, "timeButton").clicked(null);
        const picker = pushed(s.app, s.page);
        compare(picker.hour, s.page.now.getHours());
        picker.reject();
        tryVerify(() => s.app.pageStack.currentPage === s.page && s.page.status === PageStatus.Active);
        compare(Settings.systemTimes.length, 0);
        const wanted = new Date();
        wanted.setHours(7, 45, 0, 0);
        s.page.setClock(wanted);
        compare(Settings.systemTimes.length, 1);
        const set = new Date(Settings.systemTimes[0]);
        compare(set.getHours(), 7);
        compare(set.getMinutes(), 45);
        compare(child(s.page, "timeButton").value, "07:45");
        Settings.dateTimeChangeFailed("denied");
        verify(Math.abs(s.page.now.getTime() - Date.now()) < 5000);
    }

    function test_battery() {
        const s = open("battery");
        compare(child(s.page, "levelLabel").text, "80%");
        compare(child(s.page, "statusLabel").text, "Discharging");
        Power.isCharging = true;
        compare(child(s.page, "statusLabel").text, "Charging");
        compare(findChild(s.page, "saverSwitch"), null);
        const profile = child(s.page, "profileCombo");
        compare(profile.currentIndex, 1);
        pick(profile, 2);
        verify(Power.isPowerSaveMode);
        compare(profile.currentIndex, 2);
        pick(profile, 0);
        verify(!Power.isPowerSaveMode);
        compare(Power.powerProfile, "performance");
        compare(profile.currentIndex, 0);
        Power.setPowerSaveMode(true);
        compare(profile.currentIndex, 2);
        Power.powerProfilesSupported = false;
        verify(!profile.visible);
    }

    function test_noBattery() {
        Power.batteryLevel = -1;
        const s = open("battery");
        compare(child(s.page, "levelLabel").text, "No battery");
        verify(!child(s.page, "statusLabel").visible);
    }

    function test_storage() {
        const s = open("storage");
        compare(child(s.page, "usageBar").value, 0.625);
        compare(child(s.page, "usedItem").value, "40.0 GB");
        compare(child(s.page, "availableItem").value, "24.0 GB");
        compare(child(s.page, "totalItem").value, "64.0 GB");
    }

    function test_keyboard() {
        const s = open("keyboard");
        const language = child(s.page, "languageCombo");
        compare(language.currentIndex, 0);
        pick(language, 1);
        compare(KeyboardSettingsStore.currentLanguage, "de_DE");
        ["autoCorrectSwitch", "autoCapitalizeSwitch", "predictionsSwitch", "hapticSwitch"].forEach(name => child(s.page, name).clicked(null));
        verify(!KeyboardSettingsStore.autoCorrectEnabled);
        verify(!KeyboardSettingsStore.autoCapitalizeEnabled);
        verify(!KeyboardSettingsStore.predictionsEnabled);
        verify(!KeyboardSettingsStore.hapticFeedbackEnabled);
        Settings.vibrationEnabled = false;
        verify(!child(s.page, "hapticSwitch").enabled);
        compare(child(s.page, "hapticSwitch").description, "Turn on Vibration in Sounds first");
    }
}
