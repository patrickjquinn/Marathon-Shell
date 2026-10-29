import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

TestCase {
    id: test

    name: "TerminalApp"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: valueStub
        QtObject {
            property var key
            property var value
        }
    }
    Component {
        id: appComponent
        TerminalApp {
            width: 540
            height: 1140
        }
    }
    SignalSpy {
        id: minimizeSpy
        signalName: "minimizeRequested"
    }

    // The stubs are the app's children so they outlive its bindings.
    function makeApp() {
        const app = createTemporaryObject(appComponent, test);
        app.fontSize = valueStub.createObject(app, {
            value: 20
        });
        app.colorScheme = valueStub.createObject(app, {
            value: "ambience"
        });
        app.extraKeys = valueStub.createObject(app, {
            value: true
        });
        return app;
    }

    function page(app) {
        tryVerify(() => app.pageStack.currentPage && app.pageStack.currentPage.status === PageStatus.Active);
        return app.pageStack.currentPage;
    }

    function test_startsOneSession() {
        const app = makeApp();
        compare(app.sessions.length, 1);
        compare(app.currentSession.starts, 1);
    }

    function test_settingsAreConfigurationValues() {
        const app = createTemporaryObject(appComponent, test);
        compare(app.fontSize.key, "/apps/terminal/fontSize");
        compare(app.colorScheme.key, "/apps/terminal/colorScheme");
        compare(app.extraKeys.key, "/apps/terminal/extraKeys");
    }

    function test_newSessionBecomesCurrent() {
        const app = makeApp();
        app.newSession();
        compare(app.sessions.length, 2);
        compare(app.currentIndex, 1);
        compare(app.currentSession, app.sessions[1]);
        compare(app.currentSession.starts, 1);
    }

    function test_closeSession() {
        const app = makeApp();
        const first = app.sessions[0];
        app.newSession();
        app.closeSession(1);
        compare(app.sessions.length, 1);
        compare(app.currentSession, first);
    }

    function test_lastSessionStays() {
        const app = makeApp();
        app.closeSession(0);
        compare(app.sessions.length, 1);
    }

    function test_finishedShellClosesItsSession() {
        const app = makeApp();
        app.newSession();
        const second = app.sessions[1];
        Notices._queue = [];
        Notices._dismissCurrent();
        app.sessions[0].finished(0);
        compare(app.sessions.length, 1);
        compare(app.currentSession, second);
        compare(Notices._current.text, "Session 1 closed");
    }

    function test_finishedLastShellWaitsForATap() {
        const app = makeApp();
        const only = app.sessions[0];
        only.running = false;
        only.finished(0);
        compare(app.sessions.length, 1);
        compare(only.starts, 1, "the output stays until the user restarts");
        const p = page(app);
        verify(findChild(p, "exitedHint").visible);
        mouseClick(findChild(p, "touchArea"));
        compare(only.starts, 2);
        verify(!findChild(p, "exitedHint").visible);
    }

    function test_shellThatCantStartIsNotRespawned() {
        const app = makeApp();
        const only = app.sessions[0];
        only.failed = true;
        only.finished(-1);
        compare(only.starts, 1);
        compare(app.sessions.length, 1);
        app.newSession();
        app.sessions[1].failed = true;
        app.sessions[1].finished(-1);
        compare(app.sessions.length, 2);
    }

    function test_terminalHasFocus() {
        const app = makeApp();
        page(app);
        const renderer = findChild(app.pageStack.currentPage, "renderer");
        tryVerify(() => renderer.activeFocus);
    }

    // Escape and Ctrl+M belong to the shell, not to back and the pulley menu.
    function test_escapeAndCtrlMReachTheShell() {
        const app = makeApp();
        page(app);
        minimizeSpy.target = app;
        minimizeSpy.clear();
        const renderer = findChild(app.pageStack.currentPage, "renderer");
        tryVerify(() => renderer.activeFocus);
        keyClick(Qt.Key_Escape);
        keyClick(Qt.Key_M, Qt.ControlModifier);
        compare(minimizeSpy.count, 0);
        const sent = app.currentSession.sent;
        compare(sent.length, 2);
        compare(sent[0].key, Qt.Key_Escape);
        compare(sent[1].key, Qt.Key_M);
        compare(sent[1].modifiers & Qt.ControlModifier, Qt.ControlModifier);
    }

    // The on-screen keyboard commits text through the input method.
    function test_keyboardTextReachesTheShell() {
        const app = makeApp();
        page(app);
        const renderer = findChild(app.pageStack.currentPage, "renderer");
        renderer.textCommitted("s");
        renderer.parent.extraModifiers = Qt.ControlModifier;
        renderer.textCommitted("c");
        const sent = app.currentSession.sent;
        compare(sent.length, 2);
        compare(sent[0].input, "s");
        compare(sent[1].key, Qt.Key_C);
        compare(sent[1].modifiers & Qt.ControlModifier, Qt.ControlModifier);
    }

    function test_menuKeyOpensPulley() {
        const app = makeApp();
        const p = page(app);
        tryVerify(() => findChild(p, "renderer").activeFocus);
        keyClick(Qt.Key_Menu);
        const menu = findChild(p, "pulley");
        tryVerify(() => menu.active, 5000, "menu opens");
        keyClick(Qt.Key_Escape);
        tryVerify(() => !menu.active, 5000, "menu closes");
        tryVerify(() => findChild(p, "renderer").activeFocus, 5000, "focus returns");
        compare(app.currentSession.sent.length, 0);
    }

    function test_scrollsBackThroughHistory() {
        const app = makeApp();
        const p = page(app);
        const flick = findChild(p, "terminalFlick");
        const renderer = findChild(p, "renderer");
        renderer.historyLines = 10;
        compare(flick.contentHeight, flick.height + 200);
        compare(flick.contentY, 200);
        compare(renderer.scrollOffset, 0);
        flick.contentY = 0;
        flick.following = false;
        compare(renderer.scrollOffset, 200);
        renderer.historyLines = 12;
        compare(flick.contentY, 0);
        compare(renderer.scrollOffset, 240);
        tryVerify(() => renderer.activeFocus);
        keyClick(Qt.Key_A);
        compare(flick.contentY, 240);
        compare(renderer.scrollOffset, 0);
        verify(flick.following);
    }

    function test_closingThePulleyReturnsToLiveOutput() {
        const app = makeApp();
        const p = page(app);
        const flick = findChild(p, "terminalFlick");
        findChild(p, "renderer").historyLines = 10;
        tryVerify(() => findChild(p, "renderer").activeFocus);
        keyClick(Qt.Key_Menu);
        const menu = findChild(p, "pulley");
        tryVerify(() => menu.active, 5000);
        keyClick(Qt.Key_Escape);
        tryVerify(() => !menu.active, 5000);
        tryCompare(flick, "contentY", 200, 5000);
    }
}
