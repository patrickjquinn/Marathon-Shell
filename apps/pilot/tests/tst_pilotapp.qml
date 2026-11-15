import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Pilot 1.0
import ".."
import "../components"

TestCase {
    id: testCase

    name: "PilotApp"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: appComponent
        PilotApp {
            width: 540
            height: 1140
        }
    }

    function init() {
        Pilot.reset();
        Conversation.model.clear();
        Conversation.loadSettings();
    }

    function settle(app) {
        tryVerify(() => !app.pageStack.busy);
    }

    function makeApp(props) {
        const app = createTemporaryObject(appComponent, testCase, props || {});
        tryCompare(app.pageStack, "depth", 1);
        settle(app);
        return app;
    }

    function push(app, file) {
        app.pageStack.push(Qt.resolvedUrl("../pages/" + file), {}, PageStackAction.Immediate);
        settle(app);
    }

    function test_backPopsPagesThenMinimises() {
        const app = makeApp();
        push(app, "SettingsPage.qml");
        push(app, "EgressLogPage.qml");
        compare(app.pageStack.depth, 3);
        verify(app.handleBack());
        tryCompare(app.pageStack, "depth", 2);
        settle(app);
        compare(app.pageStack.currentPage.objectName, "settingsPage");
        verify(app.handleBack());
        tryCompare(app.pageStack, "depth", 1);
        settle(app);
        let minimized = false;
        app.minimizeRequested.connect(() => minimized = true);
        verify(app.handleBack());
        verify(minimized);
        compare(app.pageStack.depth, 1);
    }

    function test_forwardPutsBackWhatBackTookOff() {
        const app = makeApp();
        verify(!app.handleForward());
        push(app, "SettingsPage.qml");
        push(app, "EgressLogPage.qml");
        app.handleBack();
        settle(app);
        app.handleBack();
        settle(app);
        compare(app.pageStack.depth, 1);
        verify(app.handleForward());
        settle(app);
        compare(app.pageStack.currentPage.objectName, "settingsPage");
        verify(app.handleForward());
        settle(app);
        compare(app.pageStack.currentPage.objectName, "egressLogPage");
        verify(!app.handleForward());
    }

    function test_newPageDropsForward() {
        const app = makeApp();
        push(app, "SettingsPage.qml");
        app.handleBack();
        settle(app);
        compare(app.forwardPages.length, 1);
        push(app, "GuidePage.qml");
        compare(app.forwardPages.length, 0);
        verify(!app.handleForward());
    }

    function test_escapeIsBackAndForwardFollows() {
        const app = makeApp();
        push(app, "TriagePage.qml");
        app.pageStack.currentPage.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        tryCompare(app.pageStack, "depth", 1);
        settle(app);
        verify(app.handleForward());
        settle(app);
        compare(app.pageStack.currentPage.objectName, "triagePage");
    }

    function test_backClosesAnOpenMenuFirst() {
        const app = makeApp();
        const menu = findChild(app.pageStack.currentPage, "mainMenu");
        verify(menu);
        menu.openFromKeyboard(null);
        tryVerify(() => menu.active);
        verify(app.handleBack());
        tryVerify(() => !menu.active);
        compare(app.pageStack.depth, 1);
    }

    Component {
        id: valueStub
        QtObject {
            property var value: ""
        }
    }

    function stores(draft, page) {
        return {
            savedDraft: valueStub.createObject(testCase, {
                value: draft
            }),
            savedPage: valueStub.createObject(testCase, {
                value: page
            })
        };
    }

    function test_freezeKeepsDraftAndPageForAColdStart() {
        const kept = stores("", "");
        const app = makeApp(kept);
        app.findMainPage().draft = "what is a marathon";
        push(app, "SettingsPage.qml");
        app.handleFreeze();
        compare(kept.savedDraft.value, "what is a marathon");
        compare(kept.savedPage.value, "settingsPage");

        const again = createTemporaryObject(appComponent, testCase, kept);
        tryCompare(again.pageStack, "depth", 2);
        settle(again);
        compare(again.pageStack.currentPage.objectName, "settingsPage");
        compare(again.findMainPage().draft, "what is a marathon");
        compare(kept.savedPage.value, "");
    }

    function test_thawRestoresNothingAndRefreshes() {
        const kept = stores("", "");
        const app = makeApp(kept);
        push(app, "GuidePage.qml");
        app.handleFreeze();
        compare(kept.savedPage.value, "guidePage");
        const before = Pilot.refreshes;
        app.handleThaw();
        compare(kept.savedPage.value, "");
        verify(Pilot.refreshes > before);
    }

    function test_coldStartIgnoresAPageForwardCannotOpen() {
        const app = makeApp(stores("", "onboardingDialog"));
        compare(app.pageStack.depth, 1);
    }

    function test_fieldKeepsFocusAndQueuesWhileBusy() {
        const app = makeApp();
        const input = findChild(app.findMainPage(), "input");
        input.forceActiveFocus();
        input.text = "first";
        keyClick(Qt.Key_Return);
        compare(Pilot.asked, ["first"]);
        verify(Pilot.busy);
        verify(input.enabled);
        verify(input.activeFocus);
        compare(input.text, "");
        input.text = "second";
        keyClick(Qt.Key_Return);
        compare(Pilot.asked.length, 1);
        compare(Conversation.queued.length, 1);
        compare(Conversation.model.count, 2);
        Pilot.finish(JSON.stringify({
            route: "answer",
            cards: [
                {
                    kind: "response",
                    text: "one"
                }
            ]
        }));
        compare(Pilot.asked, ["first", "second"]);
        compare(Conversation.queued.length, 0);
        verify(input.activeFocus);
    }

    function answer(text) {
        Pilot.finish(JSON.stringify({
            route: "answer",
            cards: [
                {
                    kind: "response",
                    text: text
                }
            ]
        }));
    }

    function test_ctrlLFocusesTheFieldFromAnyPage() {
        const app = makeApp();
        push(app, "SettingsPage.qml");
        keyClick(Qt.Key_L, Qt.ControlModifier);
        tryCompare(app.pageStack, "depth", 1);
        verify(findChild(app.findMainPage(), "input").activeFocus);
    }

    function test_ctrlNStartsANewConversation() {
        const app = makeApp();
        Conversation.send("hello");
        answer("hi");
        compare(Conversation.model.count, 2);
        keyClick(Qt.Key_N, Qt.ControlModifier);
        verify(findChild(app.findMainPage(), "input").activeFocus);
        tryCompare(Conversation.model, "count", 0, 10000);
    }

    function test_upRecallsTheLastQuestion() {
        const app = makeApp();
        const input = findChild(app.findMainPage(), "input");
        Conversation.send("what is a marathon");
        answer("a race");
        input.forceActiveFocus();
        keyClick(Qt.Key_Up);
        compare(input.text, "what is a marathon");
        keyClick(Qt.Key_Up);
        compare(input.text, "what is a marathon");
    }

    Component {
        id: overlayComponent
        Overlay {
            width: 720
            height: 720
        }
    }

    function test_escapeClosesTheOverlay() {
        const overlay = createTemporaryObject(overlayComponent, testCase);
        overlay.show();
        verify(overlay.shown);
        verify(findChild(overlay, "overlayInput").activeFocus);
        keyClick(Qt.Key_Escape);
        verify(!overlay.shown);
        // After a question the keyboard is down, and Escape still works.
        overlay.show();
        overlay.send("summarise this");
        verify(!findChild(overlay, "overlayInput").activeFocus);
        keyClick(Qt.Key_Escape);
        verify(!overlay.shown);
    }

    Component {
        id: orbComponent
        Orb {
            glyph: true
            property int clicks: 0
            onClicked: clicks++
        }
    }

    function test_micOrbIsAKeyboardButton() {
        const orb = createTemporaryObject(orbComponent, testCase);
        verify(orb.activeFocusOnTab);
        orb.forceActiveFocus();
        verify(findChild(orb, "focusFrame").visible);
        keyClick(Qt.Key_Space);
        keyClick(Qt.Key_Return);
        compare(orb.clicks, 2);
    }

    Component {
        id: glowComponent
        EdgeGlow {
            width: 540
            height: 540
        }
    }

    function test_reduceMotionStillsTheGlow() {
        Conversation.reduceMotion = true;
        const still = createTemporaryObject(glowComponent, testCase, {
            active: true
        });
        wait(300);
        compare(still.phase, 0);
        compare(still.bloom, 0);
        Conversation.reduceMotion = false;
        const moving = createTemporaryObject(glowComponent, testCase, {
            active: true
        });
        tryVerify(() => moving.phase > 0);
    }

    function test_modelCardFollowsModelState() {
        const app = makeApp();
        const card = findChild(app.findMainPage(), "modelCard");
        verify(!card.visible);
        Pilot.modelState = JSON.stringify({
            state: "absent",
            bytes: 0,
            total: 900000000,
            error: "metered"
        });
        verify(card.visible);
        verify(findChild(card, "downloadOnMobileData").visible);
        findChild(card, "downloadModel").clicked(null);
        findChild(card, "downloadOnMobileData").clicked(null);
        compare(Pilot.downloads, [false, true]);
        Pilot.modelState = JSON.stringify({
            state: "downloading",
            bytes: 450000000,
            total: 900000000
        });
        verify(findChild(card, "modelProgress").visible);
        verify(!findChild(card, "downloadModel").visible);
        compare(findChild(card, "modelProgress").value, 450000000);
        Pilot.modelState = JSON.stringify({
            state: "failed"
        });
        verify(findChild(card, "downloadModel").visible);
        Pilot.modelState = JSON.stringify({
            state: "ready"
        });
        verify(!card.visible);
        Pilot.modelState = JSON.stringify({
            state: "none"
        });
        verify(!card.visible);
    }

    function fail(code) {
        Pilot.finish(JSON.stringify({
            error: code,
            cards: [
                {
                    kind: code === "offline" ? "offline" : "error",
                    code: code,
                    text: "pilotd's words"
                }
            ]
        }));
    }

    function failedCard(app) {
        const list = findChild(app.findMainPage(), "conversation");
        list.forceLayout();
        const found = list.contentItem.children.filter(c => c.failed === true);
        compare(found.length, 1);
        return found[0];
    }

    function test_typedErrorsOfferTheirAction() {
        const app = makeApp();
        let opened = 0;
        const cases = [["timeout", "retryButton"], ["offline", "retryButton"], ["model-loading", "retryButton"], ["internal", "retryButton"], ["consent-needed", "settingsButton"], ["model-unavailable", "downloadButton"]];
        for (const [code, action] of cases) {
            Conversation.model.clear();
            Pilot.asked = [];
            Conversation.send("what is a marathon");
            fail(code);
            const card = failedCard(app);
            compare(card.code, code);
            verify(findChild(card, "cardTitle").text.length > 0);
            for (const name of ["retryButton", "settingsButton", "downloadButton"])
                compare(findChild(card, name).visible, name === action, code + " " + name);
            findChild(card, action).clicked(null);
            if (action === "retryButton") {
                compare(Pilot.asked, ["what is a marathon", "what is a marathon"]);
                verify(!findChild(card, "retryButton").visible);
                Pilot.finish(JSON.stringify({
                    cards: []
                }));
            }
            if (action === "settingsButton") {
                tryCompare(app.pageStack.currentPage, "objectName", "settingsPage");
                app.handleBack();
                settle(app);
            }
        }
        compare(Pilot.downloads, [false]);
    }

    function test_voiceUnavailableOffersNothing() {
        const app = makeApp();
        Conversation.send("hello");
        fail("voice-unavailable");
        const card = failedCard(app);
        for (const name of ["retryButton", "settingsButton", "downloadButton"])
            verify(!findChild(card, name).visible);
    }

    function test_aFailureWithoutCardsIsInternal() {
        const app = makeApp();
        Conversation.send("hello");
        Pilot.finish(JSON.stringify({
            error: "Pilot is not running"
        }));
        const card = failedCard(app);
        compare(card.code, "internal");
        verify(findChild(card, "retryButton").visible);
    }

    function test_closingTheOverlayWindowHidesIt() {
        const app = makeApp();
        const win = findChild(app, "overlayWindow");
        verify(win);
        app.overlay.show();
        tryVerify(() => win.visible);
        win.close();
        verify(!app.overlay.shown);
        tryVerify(() => !win.visible);
        compare(app.pageStack.depth, 1);
    }

    function test_backKeyClosesTheOverlay() {
        const overlay = createTemporaryObject(overlayComponent, testCase);
        overlay.show();
        keyClick(Qt.Key_Back);
        verify(!overlay.shown);
    }

    function test_voiceHiddenUntilPilotdHasIt() {
        const app = makeApp();
        const main = app.findMainPage();
        verify(!Conversation.voiceAvailable);
        verify(!findChild(main, "micButton").visible);
        verify(!findChild(app.overlay, "overlayMic").visible);
        compare(Conversation.guideSteps.indexOf("voice"), -1);
        Conversation.listen();
        compare(Pilot.listens, 0);
        verify(!Conversation.listening);
        push(app, "SettingsPage.qml");
        const settings = app.pageStack.currentPage;
        verify(!findChild(settings, "consent_voice_cloud"));
        verify(!findChild(settings, "consent_spoken_nudges"));
        verify(findChild(settings, "consent_vision"));
        verify(!findChild(settings, "removeVoiceModelsButton").parent.visible);

        Pilot.voiceAvailable = true;
        app.handleBack();
        settle(app);
        verify(findChild(main, "micButton").visible);
        verify(Conversation.guideSteps.indexOf("voice") >= 0);
        Conversation.listen();
        compare(Pilot.listens, 1);
    }

    function test_backClosesTheOverlayFirst() {
        const app = makeApp();
        push(app, "SettingsPage.qml");
        app.overlay.show();
        verify(app.overlay.shown);
        verify(!app.handleForward());
        verify(app.handleBack());
        verify(!app.overlay.shown);
        compare(app.pageStack.depth, 2);
    }
}
