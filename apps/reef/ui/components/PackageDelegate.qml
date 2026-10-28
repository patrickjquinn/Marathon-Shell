// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// One app in a list (catalogueModel, installedModel): the icon, the title,
// what it does in a line, its category (and who publishes it, when that is
// not Shipwright), and on the right what matters now: an update, that it
// is installed, or what it costs.

import QtQuick
import Sailfish.Silica 1.0
import "Texts.js" as Texts

ListItem {
    id: row

    required property string name
    required property string title
    required property string summary
    required property string categoryLabel
    required property string installState
    required property string installedVersion
    required property string version
    required property string licenceModel
    required property bool licensed
    required property string publisher
    required property string iconPath
    required property bool isNew

    contentHeight: Math.max(Theme.itemSizeLarge, column.height + 2 * Theme.paddingMedium)

    function stateText() {
        // Versions are on the app's page; the list says what matters.
        if (installState === "update_available")
            return qsTr("Update")
        if (installState === "installed")
            return qsTr("Installed")
        return Texts.price(licenceModel, licensed)
    }

    AppIcon {
        id: appIcon
        anchors {
            left: parent.left
            leftMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        iconPath: row.iconPath
        title: row.title
    }

    Column {
        id: column
        anchors {
            left: appIcon.right
            right: stateLabel.left
            leftMargin: Theme.paddingLarge
            // Room before the price, so a long summary fades out well
            // short of it.
            rightMargin: 2 * Theme.paddingLarge
            verticalCenter: parent.verticalCenter
        }

        Label {
            id: titleLabel
            width: parent.width
            text: row.title
            color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
            truncationMode: TruncationMode.Fade
        }
        Label {
            width: parent.width
            text: row.summary
            color: row.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            truncationMode: TruncationMode.Fade
        }
        Label {
            width: parent.width
            text: [row.isNew && row.installState === "not_installed" ? qsTr("New") : "",
                   row.categoryLabel,
                   row.publisher !== "Shipwright" ? row.publisher : ""]
                  .filter(function(s) { return s.length > 0 }).join(" · ")
            // Plain like the rest of the row: an update waiting (on the
            // right) is the one thing a row highlights.
            color: row.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            opacity: Theme.opacityHigh
            font.pixelSize: Theme.fontSizeTiny
            truncationMode: TruncationMode.Fade
        }
    }

    Label {
        id: stateLabel
        anchors.right: parent.right
        anchors.rightMargin: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        text: row.stateText()
        color: row.installState === "update_available" ? Theme.highlightColor : Theme.secondaryColor
        font.pixelSize: Theme.fontSizeSmall
        font.bold: row.installState === "update_available"
    }
}
