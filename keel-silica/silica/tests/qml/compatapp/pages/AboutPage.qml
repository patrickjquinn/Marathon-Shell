// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sample app in the style of Harbour apps (SDK template layout), used by
// tst_compat_app.qml. Written for Keel; no third-party code.
import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    objectName: "aboutPage"

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PushUpMenu {
            MenuItem { text: qsTr("Back to top"); onClicked: parent.scrollToTop() }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge
            PageHeader { title: qsTr("About") }
            SectionHeader { text: qsTr("Version") }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                wrapMode: Text.Wrap
                text: "Keel sample 1.0"
                color: Theme.highlightColor
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Copy version")
                onClicked: Clipboard.text = "1.0"
            }
        }
    }
}
