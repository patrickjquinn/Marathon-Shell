// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The direct-mode test app (keel/tests/direct/test_direct.py, and on the
// phone tools/phase0/keel-runtime-test.sh): a Silica app with a page that
// allows every orientation, a list item to press, a text field and a cover.
// It prints "KEELTEST <name>=<value>" lines that the tests read; times are
// Date.now() (wall clock, ms): firstFrame (the first frame swapped after
// the first page is on the stack) and frameAfterPress (the first frame
// swapped after a press on the fifth row began).
import QtQuick 2.0
import QtQuick.Window 2.2
import Sailfish.Silica 1.0
import Keel 1.0

ApplicationWindow {
    id: app

    function report(name, value) { console.log("KEELTEST " + name + "=" + value) }

    property bool _firstFrameSeen
    property bool _pressPending

    allowedOrientations: Orientation.All
    initialPage: Component {
        Page {
            allowedOrientations: Orientation.All
            SilicaListView {
                anchors.fill: parent
                header: PageHeader { title: "Direct" }
                footer: TextField {
                    width: parent.width
                    placeholderText: "Type here"
                    label: "Keyboard test"
                }
                model: 8
                delegate: ListItem {
                    contentHeight: Theme.itemSizeSmall
                    onPressedChanged: {
                        if (index !== 4)
                            return
                        if (pressed)
                            app._pressPending = true
                        app.report("pressed", pressed)
                    }
                    Label { x: Theme.horizontalPageMargin; text: "Item " + index }
                }
            }
        }
    }
    cover: Component {
        CoverBackground {
            id: coverItem
            onStatusChanged: app.report("coverStatus", status === Cover.Active ? "active" : "inactive")
            Label { anchors.centerIn: parent; text: "Direct" }
            CoverActionList { CoverAction { iconSource: "image://theme/icon-cover-next" } }
        }
    }

    Connections {
        // The window is attached after this file is created: null until then.
        target: app.Window.window || null
        ignoreUnknownSignals: true
        function onFrameSwapped() {
            if (!app._firstFrameSeen && app.pageStack.depth > 0) {
                app._firstFrameSeen = true
                app.report("firstFrame", Date.now())
            }
            if (app._pressPending) {
                app._pressPending = false
                app.report("frameAfterPress", Date.now())
            }
        }
    }
    Connections {
        target: Qt.inputMethod
        function onVisibleChanged() { app.report("keyboard", Qt.inputMethod.visible) }
    }

    onDeviceOrientationChanged: report("deviceOrientation", deviceOrientation)
    onOrientationChanged: report("orientation", orientation)
    onApplicationActiveChanged: report("active", applicationActive)
    Connections {
        target: Theme
        function onHighlightColorChanged() { app.report("highlightColor", Theme.highlightColor) }
    }
    Connections {
        target: Shell
        function onCloseRequested() { app.report("closeRequested", true) }
    }
    Component.onCompleted: {
        report("mode", Shell.direct ? "direct" : (Shell.underShell ? "keel-shell" : "desktop"))
        report("highlightColor", Theme.highlightColor)
        report("active", applicationActive)
        report("platform", Qt.platform.pluginName)
    }
}
