// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The app as marathon-app-runner drives it: back and forward (the gestures,
// Escape and Alt+arrows), a tab another app opened, and freezing.

import QtQuick
import QtTest
import Shipwright.Pacific 1.0
import PacificTest 1.0

TestCase {
    id: testCase

    name: "Pacific"
    when: windowShown
    visible: true
    width: 720
    height: 1064

    // Each window is the panel less the status and gesture bars.
    function windows() {
        return [
            {
                tag: "Zinwa Q25, 720x720",
                width: 720,
                height: 633
            },
            {
                tag: "phone canvas, 540x1140",
                width: 540,
                height: 1064
            }
        ];
    }

    function makeApp(data) {
        const component = Qt.createComponent(Qt.resolvedUrl("../ui/qml/shipwright-pacific.qml"));
        verify(component.status === Component.Ready, component.errorString());
        const app = createTemporaryObject(component, testCase, {
            width: data.width,
            height: data.height
        });
        tryVerify(() => Pacific.ready, 10000);
        // The first start's welcome page goes with back, as any pushed page.
        tryVerify(() => !app.pageStack.busy && app.pageStack.depth >= 1, 5000);
        while (app.pageStack.depth > 1) {
            verify(app.handleBack());
            tryVerify(() => !app.pageStack.busy);
        }
        tryVerify(() => browserPage(app) && browserPage(app).pageMenu && browserPage(app).tabsMenu, 5000);
        return app;
    }

    function browserPage(app) {
        return findChild(app, "browserPage");
    }

    function load(app, url) {
        const browser = browserPage(app).browser;
        browser.navigate(url);
        tryVerify(() => browser.currentTab && String(browser.currentTab.webView.url) === url && !browser.currentTab.webView.loading, 5000);
    }

    function test_backClosesThenGoesBack_data() {
        return windows();
    }

    function test_backClosesThenGoesBack(data) {
        const app = makeApp(data);
        const page = browserPage(app);
        const browser = page.browser;
        load(app, "https://news.example/a");
        load(app, "https://en.wikipedia.org/wiki/Sailfish_OS");

        page.pageMenu.open = true;
        verify(app.handleBack());
        verify(!page.pageMenu.open);

        page.tabsMenu.open = true;
        verify(app.handleBack());
        verify(!page.tabsMenu.open);

        page.finding = true;
        verify(app.handleBack());
        verify(!page.finding);

        page.openAddress();
        const sheet = findChild(page, "addressSheet");
        tryVerify(() => sheet.shown);
        verify(app.handleBack());
        tryVerify(() => !sheet.shown);

        browser.fullscreen = true;
        verify(app.handleBack());
        verify(!browser.fullscreen);

        page.push("SettingsPage.qml", {
            browser: browser
        });
        tryVerify(() => !app.pageStack.busy && app.pageStack.depth === 2);
        verify(app.handleBack());
        tryVerify(() => !app.pageStack.busy && app.pageStack.depth === 1);

        verify(app.handleBack());
        tryVerify(() => String(browser.currentTab.webView.url) === "https://news.example/a");
        verify(app.handleForward());
        tryVerify(() => String(browser.currentTab.webView.url) === "https://en.wikipedia.org/wiki/Sailfish_OS");
        verify(!app.handleForward());
    }

    function test_firstPageIsUnhandled() {
        const app = makeApp(windows()[0]);
        const browser = browserPage(app).browser;
        browser.newTab(false);
        load(app, "https://news.example/a");
        compare(app.handleBack(), false);
        compare(browser.normalTabs.count > 0, true);
    }

    // A link another app opened: back from its first page closes the tab and
    // leaves Pacific, back to that app.
    function test_appOpenedTabReturnsToCaller() {
        const app = makeApp(windows()[1]);
        const browser = browserPage(app).browser;
        const before = browser.normalTabs.count;
        Pacific.openUrlRequested("https://shop.example/basket");
        tryVerify(() => browser.currentTab && browser.currentTab.openedByApp && !browser.currentTab.webView.loading, 5000);
        const tabs = browser.normalTabs.count;
        verify(tabs >= before);
        compare(app.handleBack(), false);
        tryCompare(browser.normalTabs, "count", tabs - 1);
    }

    function test_keys() {
        const app = makeApp(windows()[0]);
        const page = browserPage(app);
        const browser = page.browser;
        load(app, "https://news.example/a");
        load(app, "https://en.wikipedia.org/wiki/Sailfish_OS");
        keyClick(Qt.Key_Left, Qt.AltModifier);
        tryVerify(() => String(browser.currentTab.webView.url) === "https://news.example/a");
        keyClick(Qt.Key_Right, Qt.AltModifier);
        tryVerify(() => String(browser.currentTab.webView.url) === "https://en.wikipedia.org/wiki/Sailfish_OS");
        page.pageMenu.open = true;
        keyClick(Qt.Key_Escape);
        verify(!page.pageMenu.open);
    }

    function exists(path) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + path, false);
        try {
            xhr.send();
        } catch (e) {
            return false;
        }
        return xhr.status === 200 || xhr.responseText.length > 0;
    }

    // Frozen, the session is saved as a clean exit (a kill for memory then
    // shows no "closed unexpectedly"); thawed, a kill is a crash again.
    function test_freezeKeepsASessionAndAQuietExit() {
        const app = makeApp(windows()[1]);
        load(app, "https://news.example/a");
        tryVerify(() => exists(Paths.profile + "/running"), 5000);
        app.handleFreeze();
        verify(!exists(Paths.profile + "/running"));
        verify(exists(Paths.profile + "/session.lz4"));
        app.handleThaw();
        tryVerify(() => exists(Paths.profile + "/running"), 5000);
    }
}
