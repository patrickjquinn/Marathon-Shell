// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// Installed Reef packages and their updates. Only packages from the Reef
// repository appear here; system updates stay in Settings.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import "../components"
import "../components/Texts.js" as Texts

Page {
    id: page
    objectName: "installedPage"

    SilicaListView {
        id: list
        anchors.fill: parent
        model: Reef.installedModel

        PullDownMenu {
            busy: Reef.busy
            MenuItem {
                objectName: "updateAllItem"
                // Lists every package it touches before anything happens.
                text: qsTr("Update all…")
                visible: Reef.updateCount > 0
                enabled: !Reef.busy
                onClicked: Reef.updateAll()
            }
            MenuItem {
                objectName: "checkItem"
                text: qsTr("Check for updates")
                // Reef ignores a refresh while it is busy; the menu shows the
                // busy state meanwhile.
                onClicked: Reef.refresh()
            }
        }

        header: PageHeader {
            title: qsTr("Installed")
            description: Reef.updateCount > 0
                         ? Texts.updatesText(Reef.appUpdateCount, Reef.updateCount)
                         : qsTr("Up to date")
        }

        delegate: PackageDelegate {
            onClicked: pageStack.push(Qt.resolvedUrl("PackagePage.qml"), { packageName: name })
        }

        footer: Column {
            width: list.width
            spacing: Theme.paddingMedium
            Item { width: 1; height: Theme.paddingLarge }
            ProgressBar {
                width: parent.width
                visible: Reef.busy
                minimumValue: 0
                maximumValue: 100
                indeterminate: Reef.progress < 0
                value: Math.max(0, Reef.progress)
                valueText: Reef.progress >= 0 ? qsTr("%1%").arg(Reef.progress) : ""
                label: Texts.busyText(Reef.busyText)
            }
            // The last failure (an update-all that did not go through, a
            // check that could not reach PackageKit), and the way out.
            Label {
                objectName: "lastError"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !Reef.busy && Reef.lastError.length > 0
                wrapMode: Text.Wrap
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                text: Texts.message(Reef.lastError)
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !Reef.busy && Reef.lastError.length > 0
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: qsTr("Pull down to try again")
            }
        }

        // Not while a failure is shown: Reef could not find out what is
        // installed, so "nothing installed" would be wrong (and the two
        // overlapped at large text sizes).
        ViewPlaceholder {
            enabled: list.count === 0 && !Reef.busy && Reef.lastError.length === 0
            text: qsTr("Nothing installed from Reef")
            hintText: qsTr("Apps you install from Reef appear here, with their updates")
        }

        VerticalScrollDecorator {}
    }
}
