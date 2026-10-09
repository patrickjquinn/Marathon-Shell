// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    objectName: "urlPage"
    property string label: "default"
    // Resolved through the context chain from ApplicationWindow, as in Silica.
    property int stackDepthSeen: pageStack.depth
    function pushRelative() {
        return pageStack.push("NestedPage.qml")
    }
}
