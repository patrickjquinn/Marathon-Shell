// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Pacific, the web browser: the window, the browser state shared by every
// page, the cover and the Keel Actions Pilot uses.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Shipwright.Pacific 1.0
import "components"
import "pages"
import "cover"
import "actions"

ApplicationWindow {
    id: window

    property bool _started: false

    // The system back gesture (marathon-app-runner), Escape and Alt+Left:
    // what is open over the page, DOM fullscreen, reader mode, the page
    // stack, the tab's history, then a tab another app opened goes back to
    // that app. false: the shell leaves Pacific.
    function handleBack(): bool {
        var current = pageStack.currentPage
        var menu = current ? window._openMenu(current) : null
        if (menu) {
            menu.close()
            return true
        }
        if (current && current.objectName === "browserPage") {
            if (current.closeOverlay())
                return true
            if (browserState.fullscreen) {
                browserState.exitFullscreen()
                return true
            }
            if (browserState.currentTab && browserState.currentTab.readerMode) {
                browserState.currentTab.toggleReader()
                return true
            }
        }
        if (current && current.objectName === "tabsPage") {
            browserState.returnFromTabs()
            return true
        }
        if (pageStack.depth > 1) {
            pageStack.pop()
            return true
        }
        var tab = browserState.currentTab
        if (tab && tab.webView.canGoBack) {
            tab.webView.goBack()
            return true
        }
        if (tab && tab.openedByApp)
            browserState.close(tab.tabId)
        return false
    }

    // The forward gesture and Alt+Right.
    function handleForward(): bool {
        var tab = browserState.currentTab
        if (pageStack.depth > 1 || !tab || !tab.webView.canGoForward)
            return false
        tab.webView.goForward()
        return true
    }

    function start(): var {
        if (_started || !Pacific.ready)
            return
        _started = true
        browserState.restore()
        if (!browserState.settings.first_run_done)
            pageStack.push(Qt.resolvedUrl("pages/FirstRunPage.qml"), { browser: browserState })
    }

    appId: "shipwright-pacific"
    allowedOrientations: Orientation.All
    initialPage: Component {
        BrowserPage {
            browser: browserState
        }
    }
    cover: Component {
        CoverPage {
            browser: browserState
        }
    }

    Component.onCompleted: start()

    Browser {
        id: browserState
        window: window
    }

    // The page's own handling of these keys never sees them (the web view
    // passes them on).
    Shortcut {
        sequences: ["Alt+Left", "Escape"]
        onActivated: window.handleBack()
    }
    Shortcut {
        sequence: "Alt+Right"
        onActivated: window.handleForward()
    }

    // Pilot's actions: declared right after the first frame (the Keel
    // Actions runtime waits for them when D-Bus starts the app).
    Loader {
        id: actionsLoader
        active: false
        asynchronous: true
        sourceComponent: PacificActions {
            browser: browserState
            window: window
        }
    }
    Timer {
        interval: 100
        running: true
        onTriggered: actionsLoader.active = true
    }

    Connections {
        target: Pacific
        function onReadyChanged() { window.start() }
    }
}
