import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

TestCase {
    id: test

    name: "TerminalPages"
    when: windowShown
    visible: true
    width: 540; height: 1140

    Component {
        id: valueStub
        QtObject {
            property var value
        }
    }
    Component {
        id: appComponent
        TerminalApp { width: 540; height: 1140 }
    }

    function makeApp() {
        const app = createTemporaryObject(appComponent, test);
        app.fontSize = valueStub.createObject(app, { value: 20 });
        app.colorScheme = valueStub.createObject(app, { value: "ambience" });
        app.extraKeys = valueStub.createObject(app, { value: true });
        tryVerify(() => app.pageStack.currentPage && app.pageStack.currentPage.status === PageStatus.Active);
        return app;
    }

    function openMenu(app) {
        const menu = item(app, "pulley");
        menu.openFromKeyboard(app.pageStack.currentPage.currentView);
        tryVerify(() => menu.active);
        return menu;
    }

    function item(app, name) {
        const found = findChild(app.pageStack.currentPage, name);
        verify(found, name);
        return found;
    }

    function pushed(app, depth) {
        tryCompare(app.pageStack, "depth", depth);
        tryVerify(() => !app.pageStack.busy);
        return app.pageStack.currentPage;
    }

    function test_menuWithOneSession() {
        const app = makeApp();
        openMenu(app);
        verify(!item(app, "sessionsItem").visible);
        verify(!item(app, "copyItem").visible);
        verify(item(app, "newSessionItem").visible);
    }

    function test_newSessionFromMenu() {
        const app = makeApp();
        openMenu(app);
        item(app, "newSessionItem").clicked();
        compare(app.sessions.length, 2);
        verify(item(app, "sessionsItem").visible);
        compare(item(app, "sessionsItem").text, "Sessions (2)");
    }

    function test_onlyCurrentSessionShows() {
        const app = makeApp();
        app.newSession();
        const page = app.pageStack.currentPage;
        tryVerify(() => findChild(page, "renderer").terminal !== undefined);
        app.currentIndex = 0;
        tryVerify(() => findChild(page, "renderer").activeFocus);
        compare(page.currentView.session, app.sessions[0]);
        verify(page.currentView.visible);
    }

    function test_textSizeSteps() {
        const app = makeApp();
        item(app, "largerItem").clicked();
        compare(app.fontSize.value, 22);
        item(app, "smallerItem").clicked();
        item(app, "smallerItem").clicked();
        compare(app.fontSize.value, 18);
        app.fontSize.value = app.maxFontSize;
        verify(!item(app, "largerItem").enabled);
    }

    function test_pasteSendsClipboard() {
        const app = makeApp();
        Clipboard.text = "ls -la";
        tryVerify(() => item(app, "pasteItem").enabled);
        item(app, "pasteItem").clicked();
        compare(app.currentSession.sent[0].input, "ls -la");
    }

    function test_copySelection() {
        const app = makeApp();
        const view = app.pageStack.currentPage.currentView;
        view.selection = "hello";
        openMenu(app);
        verify(item(app, "copyItem").visible);
        item(app, "copyItem").clicked();
        compare(Clipboard.text, "hello");
        compare(view.selection, "");
    }

    function test_extraKeysCanBeHidden() {
        const app = makeApp();
        verify(item(app, "keyRow").visible);
        app.extraKeys.value = false;
        verify(!item(app, "keyRow").visible);
    }

    function test_settingsPage() {
        const app = makeApp();
        item(app, "settingsItem").clicked();
        const page = pushed(app, 2);
        const slider = findChild(page, "fontSizeSlider");
        compare(slider.value, 20);
        slider.value = 26;
        compare(app.fontSize.value, 26);
        const box = findChild(page, "colorSchemeBox");
        compare(box.currentIndex, 0);
        box.currentIndex = 2;
        compare(app.colorScheme.value, "light");
        const keys = findChild(page, "extraKeysSwitch");
        verify(keys.checked);
        waitForRendering(page);
        mouseClick(keys);
        compare(app.extraKeys.value, false);
    }

    function test_sessionsPageSwitches() {
        const app = makeApp();
        app.newSession();
        compare(app.currentIndex, 1);
        item(app, "sessionsItem").clicked();
        const page = pushed(app, 2);
        const list = findChild(page, "sessionList");
        tryCompare(list, "count", 2);
        let first = null;
        tryVerify(() => (first = list.itemAtIndex(0)) !== null);
        mouseClick(first);
        compare(app.currentIndex, 0);
        pushed(app, 1);
    }

    function test_sessionsPageCloses() {
        const app = makeApp();
        app.newSession();
        item(app, "sessionsItem").clicked();
        const page = pushed(app, 2);
        const list = findChild(page, "sessionList");
        let second = null;
        tryVerify(() => (second = list.itemAtIndex(1)) !== null);
        const menu = second.openMenu();
        tryVerify(() => menu._open && menu.height > 0);
        wait(300);
        const close = findChild(menu, "closeItem");
        mouseClick(close);
        tryVerify(() => app.sessions.length === 1, 10000);
    }
}
