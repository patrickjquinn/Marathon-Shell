// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// A note above the toolbar that does not block the page, on the browser's
// glass: a login form could be filled from Shoal Keys, Pilot is browsing.
// (A site's questions that need an answer are Dialogs: SitePromptDialog.)

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Rectangle {
    id: bar

    property alias text: label.text
    property alias acceptText: accept.text
    property alias rejectText: reject.text
    property alias rememberVisible: remember.visible
    property alias remember: remember.checked
    signal accepted()
    signal rejected()

    height: column.height + 2 * Theme.paddingMedium
    color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)

    // The glass's top edge.
    Rectangle {
        width: parent.width
        height: Theme.paddingSmall / 4
        color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
    }

    Column {
        id: column
        y: Theme.paddingMedium
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * x
        spacing: Theme.paddingSmall

        Label {
            id: label
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeSmall
        }
        TextSwitch {
            id: remember
            text: qsTr("Remember for this site")
            checked: true
            visible: false
            leftMargin: 0
        }
        Row {
            anchors.right: parent.right
            spacing: Theme.paddingMedium
            Button {
                id: reject
                visible: text !== ""
                preferredWidth: Theme.buttonWidthExtraSmall
                onClicked: bar.rejected()
            }
            Button {
                id: accept
                visible: text !== ""
                preferredWidth: Theme.buttonWidthExtraSmall
                onClicked: bar.accepted()
            }
        }
    }
}
