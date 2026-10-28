// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Pilot, on Keel (Sailfish.Silica 1.0 under Qt 6). All state comes from the
// `Pilot` singleton (Shipwright.Pilot 1.0, imported by the pages), a CXX-Qt object that talks to
// pilotd on the session bus; see ../README.md.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0
import "components"

ApplicationWindow {
    id: app

    initialPage: Qt.resolvedUrl("pages/MainPage.qml")
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    // Pilot's entry in Lipstick's Events view opens the events page: at
    // start (`--events`) or, when the app already runs, through pilotd's
    // EventsRequested (see shoal/pilot/lipstick/README.md).
    function showEvents() {
        activate()
        var top = pageStack.currentPage
        if (!top || top.objectName !== "triagePage")
            pageStack.push(Qt.resolvedUrl("pages/TriagePage.qml"))
        else
            top.reload()
    }

    // The system-wide bottom-edge gesture (the gesture patch,
    // shoal/pilot/lipstick/patch): over another app, the overlay
    // (Overlay.qml) above it; in Pilot, or without the overlay (a desktop),
    // the sheet on the main page.
    readonly property var overlay: Conversation.overlay
    readonly property var mainView: overlay ? overlay.mainView : null
    function showSheet() {
        if (overlay && !(mainView && mainView.visible && mainView.active)) {
            overlay.show()
            return
        }
        openMain()
        var main = mainPage()
        if (main)
            main.openSheet()
    }

    // The main window, also when it was kept hidden for the overlay.
    function openMain() {
        if (mainView && !mainView.visible)
            mainView.showFullScreen()
        activate()
    }
    function mainPage() {
        var main = pageStack.find(function(p) { return p.objectName === "mainPage" })
        if (main)
            pageStack.pop(main, PageStackAction.Immediate)
        return main
    }

    Connections {
        target: app.overlay
        function onExpandRequested() {
            app.openMain()
            var main = app.mainPage()
            if (main)
                main.showLatest()
        }
    }

    Connections {
        target: Pilot
        function onEventsRequested() { app.showEvents() }
        function onSheetRequested() { app.showSheet() }
    }

    Component.onCompleted: {
        if (Pilot.startOnEvents())
            pageStack.push(Qt.resolvedUrl("pages/TriagePage.qml"), {}, PageStackAction.Immediate)
        else if (Pilot.startOnSheet())
            Qt.callLater(app.showSheet)
    }
}
