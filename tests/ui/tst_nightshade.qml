import QtQuick
import QtQuick.Window
import QtTest
import Sailfish.Silica 1.0 as Silica
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "Nightshade"
    when: windowShown

    Window {
        width: 720
        height: 720
        visible: true

        MarathonNightshade {
            id: nightshade

            anchors.fill: parent
        }
    }

    function minuteNow(shift) {
        const now = new Date();
        return (now.getHours() * 60 + now.getMinutes() + shift + 1440) % 1440;
    }

    // Hours that hold now, from an hour ago to an hour on (across midnight
    // when now is near it).
    function inHours() {
        SettingsManagerCpp.nightshadeFrom = minuteNow(-60);
        SettingsManagerCpp.nightshadeTo = minuteNow(60);
    }

    function init() {
        Display.nightshade = false;
        Display.screenOn = true;
        Display.offReasons = [];
        Power.isPluggedIn = true;
        Power.isCharging = true;
        Power.hasActiveCalls = false;
        AlarmManagerCpp.hasActiveAlarm = false;
        SessionStore.showLockScreen = false;
        SettingsManagerCpp.nightshadeEnabled = true;
        SettingsManagerCpp.nightshadeTint = "red";
        SettingsManagerCpp.nightshadeItems = ["clock", "battery", "weather", "notifications"];
        MMotion.reduceMotion = false;
        WeatherClient.forecast = WeatherClient.sample();
        NotificationService.unreadCount = 3;
        inHours();
    }

    function face() {
        let item = null;
        tryVerify(() => (item = findChild(nightshade, "nightshadeFace")) !== null);
        return item;
    }

    function test_offTheIdleTimerBlanks() {
        SettingsManagerCpp.nightshadeEnabled = false;
        nightshade.idle("idle timer");
        verify(!Display.nightshade);
        compare(Display.offReasons, ["idle timer"]);
    }

    function test_onTheChargerAtNightItShows() {
        nightshade.idle("idle timer");
        verify(Display.nightshade);
        verify(Display.screenOn);
        verify(nightshade.visible);
        verify(SessionStore.showLockScreen, "the lock screen waits underneath");
        compare(Display.offReasons.length, 0);
    }

    function test_offTheChargerOrInACallItBlanks() {
        Power.isPluggedIn = false;
        nightshade.idle("idle timer");
        verify(!Display.nightshade);
        Display.screenOn = true;
        Power.isPluggedIn = true;
        Power.hasActiveCalls = true;
        nightshade.idle("idle timer");
        verify(!Display.nightshade);
        compare(Display.offReasons.length, 2);
    }

    function test_outsideItsHoursItBlanks() {
        SettingsManagerCpp.nightshadeFrom = minuteNow(60);
        SettingsManagerCpp.nightshadeTo = minuteNow(120);
        nightshade.idle("idle timer");
        verify(!Display.nightshade);
        compare(Display.offReasons.length, 1);
    }

    function test_unpluggingTurnsTheScreenOff() {
        nightshade.idle("idle timer");
        Power.isPluggedIn = false;
        verify(!Display.nightshade);
        verify(!Display.screenOn);
        compare(Display.offReasons, ["Nightshade unplugged"]);
    }

    function test_aCallOrAlarmBringsTheScreenBack() {
        nightshade.idle("idle timer");
        Power.hasActiveCalls = true;
        verify(!Display.nightshade);
        verify(Display.screenOn);
        Power.hasActiveCalls = false;
        nightshade.idle("idle timer");
        AlarmManagerCpp.hasActiveAlarm = true;
        verify(!Display.nightshade);
        verify(Display.screenOn);
    }

    function test_aTapLeavesForTheLockScreen() {
        nightshade.idle("idle timer");
        mouseClick(nightshade, 100, 100);
        verify(!Display.nightshade);
        verify(Display.screenOn);
        verify(!nightshade.visible);
    }

    function test_theHoursEndingTurnTheScreenOff() {
        nightshade.idle("idle timer");
        SettingsManagerCpp.nightshadeTo = minuteNow(-30);
        nightshade.tick();
        verify(!Display.nightshade);
        compare(Display.offReasons, ["Nightshade's hours are over"]);
    }

    function test_theScreenGoingOffEndsIt() {
        nightshade.idle("idle timer");
        Display.turnScreenOff("power key");
        verify(!Display.nightshade);
    }

    function test_theChosenTint() {
        nightshade.idle("idle timer");
        const clock = findChild(face(), "nightshadeClock");
        compare(clock.color, MColors.nightshadeTints.red);
        SettingsManagerCpp.nightshadeTint = "amber";
        compare(clock.color, MColors.nightshadeTints.amber);
        SettingsManagerCpp.nightshadeTint = "green";
        compare(clock.color, MColors.nightshadeTints.green);
        compare(findChild(face(), "nightshadeBattery").children[1].color, MColors.nightshadeTints.green);
    }

    function test_theChosenItems() {
        nightshade.idle("idle timer");
        const f = face();
        verify(findChild(f, "nightshadeClock").visible);
        verify(findChild(f, "nightshadeBattery").visible);
        verify(findChild(f, "nightshadeWeather").visible);
        verify(findChild(f, "nightshadeNotifications").visible);
        compare(findChild(f, "nightshadeBattery").children[1].text, "82%");

        SettingsManagerCpp.nightshadeItems = ["battery"];
        verify(!findChild(f, "nightshadeClock").visible);
        verify(findChild(f, "nightshadeBattery").visible);
        verify(!findChild(f, "nightshadeWeather").visible);
        verify(!findChild(f, "nightshadeNotifications").visible);
    }

    function test_noUnreadNoCount() {
        NotificationService.unreadCount = 0;
        nightshade.idle("idle timer");
        verify(!findChild(face(), "nightshadeNotifications").visible);
    }

    function test_theFaceDriftsEachStep() {
        nightshade.idle("idle timer");
        const f = face();
        nightshade.step = 0;
        tryCompare(f, "x", Math.round((nightshade.width - f.width) / 2));
        const x0 = f.x;
        const y0 = f.y;
        nightshade.step = 1;
        tryCompare(f, "x", x0 + nightshade.drift);
        compare(f.y, y0);
        nightshade.step = 2;
        tryCompare(f, "y", y0 + nightshade.drift);
    }

    function test_theFaceGlidesUnlessMotionIsReduced() {
        MMotion.durations = {
            "panel": 1000
        };
        nightshade.idle("idle timer");
        const f = face();
        nightshade.step = 0;
        tryCompare(f, "x", Math.round((nightshade.width - f.width) / 2));
        const x0 = f.x;
        nightshade.step = 1;
        verify(f.x < x0 + nightshade.drift, "it glides");
        tryCompare(f, "x", x0 + nightshade.drift, 3000);

        MMotion.reduceMotion = true;
        nightshade.step = 5;
        compare(f.x, x0 - nightshade.drift, "it jumps");
        MMotion.durations = {};
    }
}
