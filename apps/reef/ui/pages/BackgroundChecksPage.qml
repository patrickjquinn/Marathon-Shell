// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// Asked once, at Reef's first start: may Reef check for updates in the
// background? Until the person answers, nothing runs in the background
// (the package no longer starts the check's timer at install). Yes turns
// on the 4-hourly check (src/check.rs), No leaves its timer off; Settings
// changes it later. Going back answers nothing, and Reef asks again.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0

Page {
    id: page
    objectName: "backgroundChecksPage"

    function answer(yes) {
        Reef.answerBackgroundChecks(yes)
        pageStack.pop()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader { title: qsTr("Updates") }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                text: qsTr("Check for updates in the background?")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                text: qsTr("Every few hours Reef can look for new versions of the apps you installed from it, and tell you in a notification. "
                           + "It never installs anything without asking you. You can change this in Reef's settings.")
            }
            Button {
                objectName: "backgroundYes"
                anchors.horizontalCenter: parent.horizontalCenter
                preferredWidth: Theme.buttonWidthLarge
                text: qsTr("Yes, check every few hours")
                onClicked: page.answer(true)
            }
            Button {
                objectName: "backgroundNo"
                anchors.horizontalCenter: parent.horizontalCenter
                preferredWidth: Theme.buttonWidthLarge
                backgroundColor: "transparent"
                text: qsTr("No, only when I open Reef")
                onClicked: page.answer(false)
            }
        }

        VerticalScrollDecorator {}
    }
}
