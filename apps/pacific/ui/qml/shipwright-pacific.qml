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
