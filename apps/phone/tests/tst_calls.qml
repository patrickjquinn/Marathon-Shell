import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import ".."
import "../cover"

TestCase {
    id: testCase

    name: "Calls"
    when: windowShown
    visible: true
    width: 720
    height: 1440

    QtObject {
        id: seenStub

        property var value: 0
    }
    Component {
        id: appComponent

        PhoneApp {
            width: 720
            height: 1440
        }
    }
    Component {
        id: coverComponent

        PhoneCover {}
    }
    SignalSpy {
        id: hangupSpy

        signalName: "hangupRequested"
    }

    function init() {
        Telephony.reset();
        Contacts.reset();
        CallHistory.reset();
        Permissions.reset();
        seenStub.value = 0;
        Contacts.contacts = [{ id: 1, name: "Grace Hopper", phone: "+1 555 123 4567" }];
    }

    function makeApp() {
        const app = createTemporaryObject(appComponent, testCase, { callLogSeen: seenStub });
        tryVerify(() => app.pageStack.currentPage !== null);
        return app;
    }

    function waitIdle(app) {
        tryVerify(() => !app.pageStack.busy);
    }

    function test_incomingShowsCallerAndAnswerActivates() {
        const app = makeApp();
        Telephony.incomingCall("5551234567");
        tryVerify(() => app.incomingPage !== null && app.pageStack.currentPage === app.incomingPage);
        waitIdle(app);
        compare(findChild(app.incomingPage, "callerLabel").text, "Grace Hopper");
        findChild(app.incomingPage, "answerButton").clicked(null);
        compare(Telephony.log, ["answer"]);
        Telephony.setState("active");
        tryVerify(() => app.callPage !== null && app.pageStack.currentPage === app.callPage);
        verify(app.incomingPage === null);
        verify(app.callStartedAt > 0);
        waitIdle(app);
        compare(app.pageStack.depth, 2);
    }

    function test_declineHangsUpAndCloses() {
        const app = makeApp();
        Telephony.incomingCall("0871234567");
        tryVerify(() => app.incomingPage !== null);
        waitIdle(app);
        compare(findChild(app.incomingPage, "callerLabel").text, "087 123 4567");
        findChild(app.incomingPage, "declineButton").clicked(null);
        compare(Telephony.log, ["hangup"]);
        tryVerify(() => app.pageStack.depth === 1 && !app.pageStack.busy);
    }

    function test_declineWithMessage() {
        Navigation.reset();
        const app = makeApp();
        Telephony.incomingCall("5551234567");
        tryVerify(() => app.incomingPage !== null);
        waitIdle(app);
        findChild(app.incomingPage, "messageButton").clicked(null);
        compare(Telephony.log, ["hangup"]);
        compare(Navigation.launches.length, 1);
        compare(JSON.parse(Navigation.launches[0].params).number, "5551234567");
        tryVerify(() => app.pageStack.depth === 1 && !app.pageStack.busy);
    }

    function test_activeCallControls() {
        const app = makeApp();
        app.call("5551234567");
        tryVerify(() => app.callPage !== null);
        waitIdle(app);
        const page = app.callPage;
        compare(findChild(page, "statusLabel").text, "Calling…");
        compare(findChild(page, "nameLabel").text, "Grace Hopper");
        findChild(page, "muteButton").clicked(null);
        findChild(page, "speakerButton").clicked(null);
        findChild(page, "keypadButton").clicked(null);
        verify(findChild(page, "dtmfKeypad").visible);
        findChild(page, "dtmfKeypad").clicked("5");
        compare(Telephony.log, ["dial:5551234567", "mute:true", "speaker:true", "dtmf:5"]);
        findChild(page, "endCallButton").clicked(null);
        compare(Telephony.log[4], "hangup");
        tryVerify(() => app.pageStack.depth === 1 && !app.pageStack.busy);
    }

    function test_callTogglesAreLabelledSwitches() {
        const app = makeApp();
        app.call("5551234567");
        tryVerify(() => app.callPage !== null);
        waitIdle(app);
        const page = app.callPage;
        compare(findChild(page, "muteLabel").text, "Mute");
        compare(findChild(page, "keypadLabel").text, "Keypad");
        compare(findChild(page, "speakerLabel").text, "Speaker");
        findChild(page, "muteButton").clicked(null);
        findChild(page, "speakerButton").clicked(null);
        findChild(page, "keypadButton").clicked(null);
        verify(findChild(page, "muteButton").checked);
        verify(findChild(page, "keypadButton").checked);
        verify(findChild(page, "speakerButton").checked);
        verify(findChild(page, "dtmfKeypad").visible);
        compare(findChild(page, "muteButton").Accessible.name, "Mute");
    }

    function test_callDurationShownWhenConnected() {
        const app = makeApp();
        app.call("5551234567");
        tryVerify(() => app.callPage !== null);
        Telephony.setState("active");
        app.callStartedAt = Date.now() - 65000;
        app.callPage.now = Date.now();
        compare(findChild(app.callPage, "statusLabel").text, "1:05");
    }

    function test_remoteHangupShowsCallEnded() {
        const app = makeApp();
        app.call("5551234567");
        Telephony.setState("active");
        tryVerify(() => app.callPage !== null);
        waitIdle(app);
        app.callStartedAt = Date.now() - 222000;
        Telephony.setState("idle");
        const page = app.callPage;
        verify(page !== null);
        verify(findChild(page, "endedLabel").visible);
        compare(findChild(page, "statusLabel").text, "3:42");
        compare(findChild(page, "nameLabel").text, "Grace Hopper");
        verify(!findChild(page, "endCallButton").enabled);
        tryVerify(() => app.callPage === null && app.pageStack.depth === 1 && !app.pageStack.busy, 4000);
        compare(app.callNumber, "");
    }

    function test_ownHangupClosesAtOnce() {
        const app = makeApp();
        app.call("5551234567");
        Telephony.setState("active");
        tryVerify(() => app.callPage !== null);
        waitIdle(app);
        findChild(app.callPage, "endCallButton").clicked(null);
        verify(app.callPage === null);
        Telephony.setState("idle");
        tryVerify(() => app.pageStack.depth === 1 && !app.pageStack.busy);
    }

    function test_incomingDuringCallEndedShowsIncoming() {
        const app = makeApp();
        app.call("5551234567");
        Telephony.setState("active");
        tryVerify(() => app.callPage !== null);
        waitIdle(app);
        Telephony.setState("idle");
        Telephony.incomingCall("0871234567");
        tryVerify(() => app.incomingPage !== null && app.callPage === null);
    }

    function test_returnToCallAfterLeavingPage() {
        const app = makeApp();
        app.call("5551234567");
        Telephony.setState("dialing");
        tryVerify(() => app.callPage !== null);
        waitIdle(app);
        app.pageStack.pop();
        tryVerify(() => app.callPage === null && !app.pageStack.busy);
        const banner = findChild(app.pageStack.currentPage, "returnToCall");
        verify(banner.visible);
        banner.clicked(null);
        tryVerify(() => app.callPage !== null && app.pageStack.currentPage === app.callPage);
    }

    function test_coverShowsDurationAndHangs() {
        const app = makeApp();
        app.call("5551234567");
        Telephony.setState("active");
        app.callStartedAt = Date.now() - 125000;
        const cover = createTemporaryObject(coverComponent, testCase, { phone: app });
        cover.now = Date.now();
        compare(findChild(cover, "coverHeadline").value, "2:05");
        compare(findChild(cover, "coverHeadline").label, "Grace Hopper");
        verify(!findChild(cover, "coverPlaceholder").visible);
        hangupSpy.target = cover;
        hangupSpy.clear();
        findChild(cover, "hangupAction").trigger();
        compare(hangupSpy.count, 1);
    }

    function test_coverShowsMissedCalls() {
        CallHistory.history = [{ id: 1, number: "1", type: "missed", timestamp: 1700000000 }, { id: 2, number: "2", type: "missed", timestamp: 1700000001 }];
        const app = makeApp();
        const cover = createTemporaryObject(coverComponent, testCase, { phone: app });
        compare(findChild(cover, "coverHeadline").value, "2");
        compare(findChild(cover, "coverHeadline").label, "missed calls");
        seenStub.value = Date.now();
        verify(findChild(cover, "coverPlaceholder").visible);
    }

    function test_openingWithActiveCallShowsIt() {
        Telephony.callState = "active";
        Telephony.activeNumber = "+15551234567";
        const app = makeApp();
        tryVerify(() => app.callPage !== null);
        compare(app.callName, "Grace Hopper");
    }
}
