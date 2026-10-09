// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Reference scene: an app cover at Theme.coverSizeLarge with a label and two
// cover actions. Written for Keel.
import QtQuick 2.0
import Sailfish.Silica 1.0

Item {
    width: Theme.coverSizeLarge.width
    height: Theme.coverSizeLarge.height
    Rectangle { anchors.fill: parent; color: "#202830" }
    CoverBackground {
        anchors.fill: parent
        Label {
            anchors.centerIn: parent
            text: "Keel"
            font.pixelSize: Theme.fontSizeLarge
        }
        CoverActionList {
            CoverAction { iconSource: "image://theme/icon-cover-refresh" }
            CoverAction { iconSource: "image://theme/icon-cover-new" }
        }
    }
}
