// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Pilot, hosted by marathon-app-runner. All state comes from the `Pilot`
// singleton (MarathonOS.Pilot, the runner's client of pilotd); see
// README.md.

import QtQuick
import QtQuick.Window
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Nemo.Configuration 1.0
import Sailfish.Share 1.0
import MarathonOS.Pilot 1.0
import "components"

ApplicationWindow {
    id: app

    // Over another app: the overlay window above it. In Pilot: the sheet
    // on the main page.
    readonly property alias overlay: overlay

    // What a frozen Pilot that is then killed comes back to: the question
    // being typed and the page on top.
    property var savedDraft: ConfigurationValue {
        key: "/apps/shoal-pilot/draft"
        defaultValue: ""
    }
    property var savedPage: ConfigurationValue {
        key: "/apps/shoal-pilot/page"
        defaultValue: ""
    }

    // The pages that forward can bring back, by objectName.
    readonly property var pageFiles: ({
            settingsPage: "pages/SettingsPage.qml",
            triagePage: "pages/TriagePage.qml",
            guidePage: "pages/GuidePage.qml",
            capabilitiesPage: "pages/CapabilitiesPage.qml",
            egressLogPage: "pages/EgressLogPage.qml",
            cameraPage: "pages/CameraPage.qml"
        })
    // The pages above the main page, and the ones taken off it (newest
    // last), whichever way they left: back, Escape or a swipe.
    property var shownPages: []
    property var forwardPages: []
    property bool _forwarding: false

    function _trackPages() {
        var shown = shownPages.slice();
        var forward = forwardPages.slice();
        var above = Math.max(0, pageStack.depth - 1);
        while (shown.length > above) {
            var name = shown.pop();
            if (pageFiles[name])
                forward.push(name);
        }
        // The stack makes a pushed page current before it counts it.
        while (shown.length < above) {
            shown.push(shown.length === above - 1 && pageStack.currentPage ? pageStack.currentPage.objectName : "");
            if (!_forwarding)
                forward = [];
        }
        shownPages = shown;
        forwardPages = forward;
    }

    // The system back: the overlay, then an open menu, then the page.
    function handleBack() {
        if (overlay.shown) {
            overlay.hide();
            return true;
        }
        var menu = pageStack.currentPage ? _openMenu(pageStack.currentPage) : null;
        if (menu) {
            menu.close();
            return true;
        }
        if (pageStack.depth > 1) {
            pageStack.pop();
            return true;
        }
        minimizeRequested();
        return true;
    }

    // The runner, before the shell freezes the app: what a kill would lose.
    function handleFreeze() {
        var main = findMainPage();
        savedDraft.value = main ? main.draft : "";
        savedPage.value = shownPages.length > 0 ? shownPages[shownPages.length - 1] : "";
    }

    // Thawed: the process lived, so nothing is restored; the home catches up.
    function handleThaw() {
        savedPage.value = "";
        Pilot.refreshNow();
    }

    // A cold start: the page a deep link names, else, after a kill, the
    // page forward could bring back; and the draft.
    function restore() {
        var main = findMainPage();
        if (main && main.draft === "")
            main.draft = savedDraft.value;
        var name = savedPage.value;
        savedPage.value = "";
        if (!openRoute(route, PageStackAction.Immediate) && pageFiles[name])
            pageStack.push(Qt.resolvedUrl(pageFiles[name]), {}, PageStackAction.Immediate);
    }

    // The manifest's deep links, with or without a leading slash.
    property string route: typeof MARATHON_APP_ROUTE !== "undefined" ? MARATHON_APP_ROUTE : ""
    readonly property var routes: ({
            settings: "settingsPage",
            memories: "settingsPage",
            events: "triagePage",
            learn: "guidePage"
        })
    function openRoute(path, operation) {
        var name = String(path || "").replace(/^\//, "");
        var page = routes[name];
        if (!page)
            return false;
        mainPage();
        pageStack.push(Qt.resolvedUrl(pageFiles[page]), name === "memories" ? {
            startAt: "memories"
        } : {}, operation);
        return true;
    }

    // From the share sheet: the text goes with the next question.
    function receiveShare(resources) {
        var text = (resources || []).map(function (r) {
            var data = String(r.data || "");
            var name = String(r.name || "");
            return data === "" ? "" : name !== "" && name !== data ? name + "\n" + data : data;
        }).filter(function (t) {
            return t !== "";
        }).join("\n\n");
        if (text === "")
            return;
        Conversation.shared = text;
        activate();
        var main = mainPage();
        if (main)
            main.openSheet();
    }

    function findMainPage() {
        return pageStack.find(function (p) {
            return p.objectName === "mainPage";
        });
    }

    // The system forward: the page back last took off.
    function handleForward() {
        if (overlay.shown || forwardPages.length === 0)
            return false;
        var forward = forwardPages.slice();
        var name = forward.pop();
        forwardPages = forward;
        _forwarding = true;
        pageStack.push(Qt.resolvedUrl(pageFiles[name]));
        _forwarding = false;
        return true;
    }

    // Pilot's events entry opens the events page.
    function showEvents() {
        activate();
        var top = pageStack.currentPage;
        if (!top || top.objectName !== "triagePage")
            pageStack.push(Qt.resolvedUrl("pages/TriagePage.qml"));
        else
            top.reload();
    }

    function showSheet() {
        if (!applicationActive) {
            overlay.show();
            return;
        }
        var main = mainPage();
        if (main)
            main.openSheet();
    }

    // The shell's assistant key, held: the sheet, already listening.
    function showListening() {
        showSheet();
        if (!Conversation.listening)
            Qt.callLater(Conversation.listen);
    }

    function mainPage() {
        var main = findMainPage();
        if (main)
            pageStack.pop(main, PageStackAction.Immediate);
        return main;
    }

    appId: "shoal-pilot"
    initialPage: Qt.resolvedUrl("pages/MainPage.qml")
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations
    Component.onCompleted: restore()

    // Closed by the person, not killed: start at home next time.
    Connections {
        target: Qt.application
        function onAboutToQuit() {
            app.savedPage.value = "";
        }
    }

    Connections {
        target: app.pageStack
        function onDepthChanged() {
            app._trackPages();
        }
    }

    Connections {
        target: typeof NavigationRouter !== "undefined" ? NavigationRouter : null
        ignoreUnknownSignals: true
        function onDeepLinkRequested(appId, route, params) {
            if (appId === app.appId) {
                app.activate();
                app.openRoute(route);
            }
        }
    }

    ShareProvider {
        method: "text"
        capabilities: ["text/plain", "text/x-url"]
        onTriggered: resources => app.receiveShare(resources)
    }

    // Keys no page used: Ctrl+N a new conversation, Ctrl+L the field.
    Keys.onPressed: function (event) {
        if (event.modifiers !== Qt.ControlModifier || (event.key !== Qt.Key_N && event.key !== Qt.Key_L))
            return;
        event.accepted = true;
        var main = mainPage();
        if (main && event.key === Qt.Key_N)
            main.newConversation();
        else if (main)
            main.focusField();
    }

    Connections {
        target: Pilot
        function onEventsRequested() {
            app.showEvents();
        }
        function onSheetRequested() {
            app.showSheet();
        }
        function onListenRequested() {
            app.showListening();
        }
    }

    // Its own top-level window, which the compositor shows over the app on
    // screen by its title.
    Window {
        id: overlayWindow
        objectName: "overlayWindow"
        title: "keel:dialog:pilot" // i18n: not user-facing
        transientParent: null
        color: "transparent"
        visible: false
        // The shell closes a dialog that ignores back; Pilot itself stays.
        onClosing: function (close) {
            close.accepted = false;
            overlay.hide();
        }

        Overlay {
            id: overlay
            anchors.fill: parent
            window: overlayWindow
            onExpandRequested: {
                app.activate();
                var main = app.mainPage();
                if (main)
                    main.showLatest();
            }
        }
    }
}
