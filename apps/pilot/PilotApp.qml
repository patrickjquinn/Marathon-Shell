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
