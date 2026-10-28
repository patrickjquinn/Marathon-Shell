// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Installed Reef packages and their updates; system updates stay in
// Settings. Reef does not install on Marathon yet, so this stays empty.

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
                objectName: "checkItem"
                text: qsTr("Refresh")
                // Reef ignores a refresh while it is busy; the menu shows the
                // busy state meanwhile.
                onClicked: Reef.refresh()
            }
        }

        header: PageHeader {
            title: qsTr("Installed")
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
                indeterminate: true
                label: Texts.busyText(Reef.busyText)
            }
            // The last failure, and the way out.
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
            hintText: qsTr("Installing apps from Reef is not available on Marathon yet")
        }

        VerticalScrollDecorator {}
    }
}
