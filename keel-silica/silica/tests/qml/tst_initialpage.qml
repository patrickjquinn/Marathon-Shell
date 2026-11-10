// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// ApplicationWindow.initialPage as a relative URL string resolves against
// the file that declares the window (the app's main QML), not against
// Silica's module directory. The window file is loaded as an app's main
// QML file is (here with a Loader, as the root of its own document).
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

Item {
    width: 540
    height: 960

    Loader {
        id: loader
        anchors.fill: parent
        source: "appdir/SubdirWindow.qml"
    }
    property var win: loader.item

    TestCase {
        name: "InitialPage"
        when: windowShown

        function test_relativeStringInitialPage() {
            tryVerify(function() { return win && win.pageStack.currentPage !== null })
            compare(win.pageStack.currentPage.objectName, "subPage")
            compare(win.pageStack.depth, 1)
        }
    }
}
