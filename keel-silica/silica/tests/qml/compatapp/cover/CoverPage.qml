// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sample app in the style of Harbour apps (SDK template layout), used by
// tst_compat_app.qml. Written for Keel; no third-party code.
import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    objectName: "cover"
    property alias countLabel: count

    Label {
        id: count
        anchors.centerIn: parent
        text: app.notes.count
        font.pixelSize: Theme.fontSizeHuge
    }

    CoverActionList {
        CoverAction {
            iconSource: "image://theme/icon-cover-new"
            onTriggered: {
                app.addNote("From cover", "normal", false)
                app.activate()
            }
        }
    }
}
