import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: testCase

    property var oobe: null

    name: "OobeFlow"
    when: windowShown

    Window {
        id: window

        width: 540
        height: 1140
        visible: true
    }

    Component {
        id: oobeComponent

        MarathonOOBE {}
    }

    SignalSpy {
        id: completeSpy

        signalName: "setupComplete"
    }

    function init() {
        SessionStore.isLocked = true;
        SettingsManagerCpp.firstRunComplete = false;
        SettingsManagerCpp.language = "";
        SettingsManagerCpp.reduceMotion = false;
        SettingsManagerCpp.userScaleFactor = 1;
        window.requestActivate();
        tryVerify(() => window.active);
        oobe = createTemporaryObject(oobeComponent, window.contentItem);
        verify(oobe);
        completeSpy.target = oobe;
        completeSpy.clear();
        waitForRendering(oobe);
    }

    function cleanup() {
        SessionStore.isLocked = false;
        SettingsManagerCpp.firstRunComplete = false;
    }

    function child(name) {
        const item = findChild(oobe, name);
        verify(item, name);
        return item;
    }

    function drag(item, x, y, dx, dy) {
        mousePress(item, x, y);
        const steps = 8;
        for (let i = 1; i <= steps; ++i)
            mouseMove(item, x + dx * i / steps, y + dy * i / steps, 16);
        mouseRelease(item, x + dx, y + dy);
    }

    function swipeUp() {
        const nav = child("oobeNavBar");
        drag(nav, nav.width / 2, nav.height / 2, 0, -150);
    }

    function swipeBack() {
        const nav = child("oobeNavBar");
        drag(nav, nav.width / 2, nav.height / 2, -200, 0);
    }

    function test_startsOnHelloWithoutProgress() {
        compare(oobe.beat, 0);
        verify(child("oobeHello").visible);
        verify(!child("oobeProgress").visible);
        verify(!child("oobeOnline").visible);
    }

    function test_swipeUpOnTheBarBegins() {
        verify(child("oobeNavBar").setupMode);
        swipeUp();
        compare(oobe.beat, 1);
        verify(child("oobeOnline").visible);
        verify(!child("oobeHello").visible);
    }

    function test_tapOnThePillBegins() {
        const nav = child("oobeNavBar");
        mouseClick(nav, nav.width / 2, nav.height / 2);
        compare(oobe.beat, 1);
    }

    function test_enterBegins() {
        tryVerify(() => child("oobeHello").activeFocus);
        keyClick(Qt.Key_Return);
        compare(oobe.beat, 1);
    }

    function test_swipeUpOnALaterBeatDoesNotSkip() {
        oobe.beat = 2;
        swipeUp();
        compare(oobe.beat, 2);
    }

    function test_backOnHelloStays() {
        swipeBack();
        compare(oobe.beat, 0);
        verify(child("oobeHello").visible);
    }

    function test_backGoesOneBeatBack() {
        oobe.beat = 4;
        swipeBack();
        compare(oobe.beat, 3);
        verify(child("oobeLook").visible);
        verify(!child("oobeSize").visible);
    }

    function test_backAsksTheBeatFirst() {
        oobe.beat = 2;
        const passcode = child("oobePasscode");
        for (const d of "123456")
            passcode.appendDigit(d);
        compare(passcode.stage, "confirm");
        swipeBack();
        compare(oobe.beat, 2);
        compare(passcode.stage, "enter");
        swipeBack();
        compare(oobe.beat, 1);
    }

    function test_onlyTheCurrentBeatIsShown() {
        const names = ["oobeHello", "oobeOnline", "oobePasscode", "oobeLook", "oobeSize", "oobeHub", "oobeFinish"];
        for (let b = 0; b < names.length; ++b) {
            oobe.beat = b;
            for (let i = 0; i < names.length; ++i)
                compare(child(names[i]).visible, i === b, names[i] + " on beat " + b);
        }
    }

    function test_beatsAdvanceWhenDone() {
        oobe.beat = 1;
        child("oobeOnline").done();
        compare(oobe.beat, 2);
        oobe.beat = 3;
        child("oobeLook").done();
        compare(oobe.beat, 4);
    }

    function test_progressShowsOneOfFiveOnGetOnline() {
        swipeUp();
        const progress = child("oobeProgress");
        verify(progress.visible);
        compare(progress.count, 5);
        compare(progress.current, 1);
        oobe.beat = 5;
        compare(progress.current, 5);
        verify(progress.visible);
        oobe.beat = 6;
        verify(!progress.visible);
    }

    function test_accessibilitySheetWritesReduceMotion() {
        mouseClick(child("helloAccessibility"));
        const sheet = child("accessibilitySheet");
        tryCompare(sheet, "open", true);
        const toggle = child("reduceMotionSwitch");
        tryVerify(() => toggle.visible);
        mouseClick(toggle);
        compare(SettingsManagerCpp.reduceMotion, true);
        compare(child("textSizeSlider").value, 100);
        compare(SettingsManagerCpp.userScaleFactor, 1);
    }

    function test_backClosesASheetFirst() {
        mouseClick(child("helloAccessibility"));
        const sheet = child("accessibilitySheet");
        tryCompare(sheet, "open", true);
        swipeBack();
        compare(sheet.open, false);
        compare(oobe.beat, 0);
    }

    function test_languageSheetListsAndWritesLanguage() {
        const button = child("helloLanguage");
        compare(button.text, "English");
        mouseClick(button);
        const sheet = child("languageSheet");
        tryCompare(sheet, "open", true);
        for (const lang of SettingsManagerCpp.availableLanguages) {
            const row = child("language-" + lang.code);
            compare(row.nativeName, lang.nativeName);
            compare(child("preview-" + lang.code).visible, lang.status === "preview", lang.code);
            compare(child("preview-" + lang.code).text, "Preview");
        }
        const de = child("language-de");
        tryVerify(() => de.visible);
        mouseClick(de);
        compare(SettingsManagerCpp.language, "de");
        compare(button.text, "Deutsch");
    }

    function test_greetingsComeFromTheShippedLanguages() {
        const hello = child("oobeHello");
        compare(hello.greetings, ["Hello", "Hallo", "Bonjour", "Hola", "Dia dhuit"]);
        compare(hello.shown, 0);
        tryCompare(hello, "shown", 1, 3500);
    }

    function test_freshSetupStartsOnHello() {
        oobe.beat = 3;
        const again = createTemporaryObject(oobeComponent, window.contentItem);
        compare(again.beat, 0);
    }

    function test_setupModeReportsSwipeUpProgress() {
        verify(SessionStore.isLocked);
        const nav = child("oobeNavBar");
        mousePress(nav, nav.width / 2, nav.height / 2);
        for (let i = 1; i <= 8; ++i)
            mouseMove(nav, nav.width / 2, nav.height / 2 - 20 * i, 16);
        verify(nav.gestureProgress > 0, "progress " + nav.gestureProgress);
        mouseRelease(nav, nav.width / 2, nav.height / 2 - 160);
    }

    function test_wallpaperChoiceRevealsAcrossTheScreen() {
        oobe.beat = 3;
        const look = child("oobeLook");
        const backdrop = child("oobeBackdrop");
        compare(backdrop.width, oobe.width);
        const chosen = AmbienceService.wallpapers[1].path;
        look.wallpaperChosen(backdrop.current, chosen, Qt.point(100, 900));
        compare(backdrop.target, chosen);
        compare(backdrop.centerX, 100);
        compare(backdrop.centerY, 900);
    }

    function test_finishingCompletesSetup() {
        oobe.beat = 6;
        swipeUp();
        compare(completeSpy.count, 1);
        verify(SettingsManagerCpp.firstRunComplete);
    }
}
