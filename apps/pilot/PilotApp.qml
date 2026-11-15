// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Pilot, hosted by marathon-app-runner. All state comes from the `Pilot`
// singleton (MarathonOS.Pilot, the runner's client of pilotd); see
// README.md.

import QtQuick
import QtQuick.Window
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Pilot 1.0
import "components"

ApplicationWindow {
    id: app

    // Over another app: the overlay window above it. In Pilot: the sheet
    // on the main page.
    readonly property alias overlay: overlay

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
        var main = pageStack.find(function (p) {
            return p.objectName === "mainPage";
        });
        if (main)
            pageStack.pop(main, PageStackAction.Immediate);
        return main;
    }

    appId: "shoal-pilot"
    initialPage: Qt.resolvedUrl("pages/MainPage.qml")
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    Connections {
        target: app.pageStack
        function onDepthChanged() {
            app._trackPages();
        }
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
        title: "keel:dialog:pilot"
        transientParent: null
        color: "transparent"
        visible: false

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
