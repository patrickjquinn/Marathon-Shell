// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// A full-area message over a tab's page: the HTTPS-first interstitial, a
// certificate problem, a page that failed to load, a crashed page.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Rectangle {
    id: panel

    property alias iconSource: icon.source
    property alias title: titleLabel.text
    property alias text: textLabel.text
    property alias primaryText: primary.text
    property alias secondaryText: secondary.text
    signal primaryClicked()
    signal secondaryClicked()

    // Opaque: the page behind must not show through.
    color: Theme.highlightDimmerColor

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + 2 * Theme.paddingLarge

        Column {
            id: column
            y: Theme.paddingLarge * 2
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            spacing: Theme.paddingLarge

            Icon {
                id: icon
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.iconSizeLarge
                height: Theme.iconSizeLarge
            }
            Label {
                id: titleLabel
                width: parent.width
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                textFormat: Text.PlainText
            }
            Label {
                id: textLabel
                width: parent.width
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                color: Theme.secondaryHighlightColor
                textFormat: Text.PlainText
            }
            Button {
                id: primary
                anchors.horizontalCenter: parent.horizontalCenter
                preferredWidth: Theme.buttonWidthMedium
                visible: text !== ""
                onClicked: panel.primaryClicked()
            }
            Button {
                id: secondary
                anchors.horizontalCenter: parent.horizontalCenter
                preferredWidth: Theme.buttonWidthMedium
                visible: text !== ""
                onClicked: panel.secondaryClicked()
            }
        }
        VerticalScrollDecorator {}
    }
}
