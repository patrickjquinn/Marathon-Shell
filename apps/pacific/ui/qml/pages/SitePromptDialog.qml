// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// A site's question, as the Sailfish Browser asks it: a Dialog pushed over
// the page, accepted with the header's button and declined by going back.
// Used for permission requests (with "remember for this site") and for
// saving a login in Shoal Keys.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Dialog {
    id: dialog
    objectName: "sitePromptDialog"

    property string site
    property string question
    property string detail
    property string acceptText: qsTr("Allow")
    property string cancelText: qsTr("Deny")
    property string iconSource
    property bool rememberVisible
    property alias remember: rememberSwitch.checked

    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            DialogHeader {
                acceptText: dialog.acceptText
                cancelText: dialog.cancelText
            }
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: dialog.iconSource !== ""
                source: dialog.iconSource
                width: Theme.iconSizeLarge
                height: width
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                text: dialog.question
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                visible: text !== ""
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                color: Theme.secondaryHighlightColor
                text: dialog.detail
            }
            TextSwitch {
                id: rememberSwitch
                visible: dialog.rememberVisible
                text: qsTr("Remember for %1").arg(dialog.site)
                checked: true
            }
        }
        VerticalScrollDecorator {}
    }
}
