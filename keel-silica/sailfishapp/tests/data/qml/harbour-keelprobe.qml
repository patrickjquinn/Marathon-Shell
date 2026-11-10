// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Main QML of the probe app: a Silica ApplicationWindow that checks it was
// loaded through SailfishApp::main() and exits with a known code.
import QtQuick 2.0
import Sailfish.Silica 1.0

ApplicationWindow {
    id: app
    initialPage: Component {
        Page {
            PageHeader { title: "Probe" }
        }
    }
    Timer {
        interval: 50
        running: true
        onTriggered: {
            var ok = app.pageStack.depth === 1 && app.width > 0 && Qt.application.name === "harbour-keelprobe"
            Qt.exit(ok ? 42 : 3)
        }
    }
}
