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
        Security.hasQuickPIN = false;
        Security.firstRunPins = [];
        SettingsManagerCpp.firstRunComplete = false;
        SettingsManagerCpp.language = "";
        SettingsManagerCpp.reduceMotion = false;
        SettingsManagerCpp.userScaleFactor = 1;
        MMotion.reduceMotion = false;
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

    // Up the bar and let go short of beginning or the minimise threshold.
    function shortRelease() {
        const nav = child("oobeNavBar");
        const x = nav.width / 2, y = nav.height / 2;
        mousePress(nav, x, y);
        for (let i = 1; i <= 8; ++i)
            mouseMove(nav, x, y - 3 * i, 16);
        mouseRelease(nav, x, y - 24);
    }

    function demoOn(beat) {
        const item = findChild(child(beat), "practiceDemo");
        verify(item, "practiceDemo on " + beat);
        return item;
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

    function test_flickPastTheThresholdCompletes() {
        oobe.beat = 6;
        swipeUp();
        compare(completeSpy.count, 1);
        tryVerify(() => SettingsManagerCpp.firstRunComplete);
        compare(completeSpy.count, 1);
    }

    function test_shortReleaseSpringsBack() {
        oobe.beat = 6;
        const nav = child("oobeNavBar");
        const surface = child("oobeSurface");
        const x = nav.width / 2, y = nav.height / 2;
        mousePress(nav, x, y);
        for (let i = 1; i <= 8; ++i)
            mouseMove(nav, x, y - 4 * i, 16);
        verify(surface.scale < 1, "scale " + surface.scale);
        mouseRelease(nav, x, y - 32);
        tryCompare(surface, "scale", 1);
        wait(50);
        compare(completeSpy.count, 0);
        verify(!SettingsManagerCpp.firstRunComplete);
        compare(oobe.beat, 6);
    }

    function test_scaleTracksProgressDownToFortyFivePercent() {
        oobe.beat = 6;
        const tracker = child("oobeNavBar").minimizeTracker;
        const surface = child("oobeSurface");
        compare(surface.scale, 1);
        tracker.value = tracker.to / 2;
        fuzzyCompare(surface.scale, 1 - 0.55 / 2, 0.001);
        tracker.value = tracker.to;
        fuzzyCompare(surface.scale, 0.45, 0.001);
        tracker.value = tracker.to * 2;
        fuzzyCompare(surface.scale, 0.45, 0.001);
        verify(surface.y < 0, "rises: " + surface.y);
        tracker.value = 0;
        compare(surface.scale, 1);
        compare(surface.y, 0);
    }

    function test_swipeUpOnHelloDoesNotShrink() {
        const tracker = child("oobeNavBar").minimizeTracker;
        tracker.value = tracker.to;
        compare(child("oobeSurface").scale, 1);
        tracker.value = 0;
    }

    function test_reduceMotionFadesInsteadOfShrinking() {
        MMotion.reduceMotion = true;
        oobe.beat = 6;
        const tracker = child("oobeNavBar").minimizeTracker;
        tracker.value = tracker.to;
        compare(child("oobeSurface").scale, 1);
        tracker.value = 0;
        swipeUp();
        compare(completeSpy.count, 1);
        compare(child("oobeSurface").scale, 1);
        tryVerify(() => SettingsManagerCpp.firstRunComplete);
    }

    function test_tapOnThePillFinishes() {
        oobe.beat = 6;
        const nav = child("oobeNavBar");
        mouseClick(nav, nav.width / 2, nav.height / 2);
        compare(completeSpy.count, 1);
        tryVerify(() => SettingsManagerCpp.firstRunComplete);
    }

    function test_enterFinishes() {
        oobe.beat = 6;
        tryVerify(() => child("oobeFinish").activeFocus);
        keyClick(Qt.Key_Return);
        compare(completeSpy.count, 1);
        tryVerify(() => SettingsManagerCpp.firstRunComplete);
    }

    function test_finishingTwiceCompletesOnce() {
        oobe.beat = 6;
        const nav = child("oobeNavBar");
        mouseClick(nav, nav.width / 2, nav.height / 2);
        mouseClick(nav, nav.width / 2, nav.height / 2);
        tryVerify(() => SettingsManagerCpp.firstRunComplete);
        compare(completeSpy.count, 1);
    }

    function test_enterDoesNotBeginBehindASheet() {
        mouseClick(child("helloLanguage"));
        tryCompare(child("languageSheet"), "open", true);
        child("oobeHello").forceActiveFocus();
        keyClick(Qt.Key_Return);
        compare(oobe.beat, 0);
        swipeBack();
        tryCompare(child("languageSheet"), "visible", false);
        mouseClick(child("helloAccessibility"));
        tryCompare(child("accessibilitySheet"), "open", true);
        child("oobeHello").forceActiveFocus();
        keyClick(Qt.Key_Return);
        compare(oobe.beat, 0);
    }

    function test_pillNamesItsActionForScreenReaders() {
        const nav = child("oobeNavBar");
        compare(nav.pillAction, "Begin setup");
        oobe.beat = 3;
        compare(nav.pillAction, "");
        oobe.beat = 6;
        compare(nav.pillAction, "Go home");
    }

    function test_glowSettlesAfterHello() {
        const glow = child("oobeGlow");
        wait(300);
        swipeUp();
        compare(oobe.beat, 1);
        tryCompare(glow, "opacity", 0.6, 1000);
    }

    function test_finishIdleStartsTheDemo() {
        oobe.beat = 6;
        const demo = demoOn("oobeFinish");
        verify(!demo.running);
        tryVerify(() => demo.running, 10000);
        verify(!child("finishGoHome").visible);
    }

    function test_finishTwoShortReleasesStartTheDemo() {
        oobe.beat = 6;
        const demo = demoOn("oobeFinish");
        shortRelease();
        compare(completeSpy.count, 0);
        verify(!demo.running);
        shortRelease();
        tryVerify(() => demo.running, 1000);
        compare(completeSpy.count, 0);
    }

    function test_finishGoHomeAfterTheDemoCompletes() {
        oobe.beat = 6;
        tryVerify(() => demoOn("oobeFinish").running, 10000);
        const goHome = child("finishGoHome");
        tryVerify(() => goHome.visible, 15000);
        verify(!findChild(child("oobeFinish"), "practiceNotNow").visible);
        mouseClick(goHome);
        compare(completeSpy.count, 1);
        tryVerify(() => SettingsManagerCpp.firstRunComplete);
    }

    function test_finishDemoPlaysOnceUnderReduceMotion() {
        MMotion.reduceMotion = true;
        oobe.beat = 6;
        const demo = demoOn("oobeFinish");
        tryVerify(() => demo.running, 10000);
        compare(demo.loops, 1);
    }

    function test_helloIdleStartsTheDemo() {
        const demo = demoOn("oobeHello");
        verify(!demo.running);
        tryVerify(() => demo.running, 10000);
        verify(!child("helloBegin").visible);
    }

    function test_helloTwoShortReleasesStartTheDemo() {
        const demo = demoOn("oobeHello");
        shortRelease();
        compare(oobe.beat, 0);
        verify(!demo.running);
        shortRelease();
        tryVerify(() => demo.running, 1000);
        compare(oobe.beat, 0);
    }

    function test_helloBeginAfterTheDemoBegins() {
        tryVerify(() => demoOn("oobeHello").running, 10000);
        const begin = child("helloBegin");
        tryVerify(() => begin.visible, 15000);
        verify(!findChild(child("oobeHello"), "practiceNotNow").visible);
        mouseClick(begin);
        compare(oobe.beat, 1);
    }

    function test_backDoesNothingOnceLeaving() {
        oobe.beat = 6;
        oobe.finish();
        oobe.back();
        compare(oobe.beat, 6);
    }

    function enterPasscode() {
        const passcode = child("oobePasscode");
        for (const d of "123456123456")
            passcode.appendDigit(d);
    }

    function test_backPastASetPasscodeSkipsIt() {
        oobe.beat = 2;
        enterPasscode();
        compare(oobe.beat, 3);
        swipeBack();
        compare(oobe.beat, 1);
        verify(child("oobeOnline").visible);
        child("oobeOnline").done();
        compare(oobe.beat, 3);
        compare(Security.firstRunPins, ["123456"]);
    }

    function test_existingPinNeverAsksForAPasscode() {
        Security.hasQuickPIN = true;
        oobe = createTemporaryObject(oobeComponent, window.contentItem);
        const passcode = child("oobePasscode");
        let shown = false;
        passcode.visibleChanged.connect(() => shown = shown || passcode.visible);
        const progress = child("oobeProgress");
        swipeUp();
        compare(oobe.beat, 1);
        compare(progress.count, 4);
        compare(progress.current, 1);
        child("oobeOnline").done();
        compare(oobe.beat, 3);
        compare(progress.current, 2);
        oobe.beat = 5;
        compare(progress.current, 4);
        oobe.beat = 3;
        swipeBack();
        compare(oobe.beat, 1);
        verify(!shown);
        compare(Security.firstRunPins, []);
    }

    function test_doneFromABeatNotShownIsIgnored() {
        oobe.beat = 3;
        child("oobeHub").done();
        child("oobeOnline").done();
        compare(oobe.beat, 3);
    }

    function test_backDuringTheHubConfirmationStaysBack() {
        oobe.beat = 5;
        child("oobeHub").succeed();
        swipeBack();
        compare(oobe.beat, 4);
        wait(1700);
        compare(oobe.beat, 4);
        verify(child("oobeSize").visible);
    }
}
