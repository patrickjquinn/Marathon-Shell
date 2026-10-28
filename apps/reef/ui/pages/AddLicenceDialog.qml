// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// Paste a licence token (v1.<payload>.<signature>). The token is verified
// offline as it is typed; Accept is only possible for a token that
// verifies, so nothing invalid is ever stored. If storing it still fails
// (no writable home, an app id that is not a safe file name), Reef sets
// lastError, which the licences page below shows.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0

Dialog {
    id: dialog

    readonly property string token: tokenField.text.trim()
    // "" when valid, otherwise why not (from reef-licence).
    readonly property string problem: token.length === 0 ? "" : Reef.checkLicenceToken(token)

    canAccept: token.length > 0 && problem.length === 0

    onAccepted: Reef.addLicenceToken(token)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width

            DialogHeader {
                dialog: dialog
                acceptText: qsTr("Add")
                title: qsTr("Add licence")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Paste the licence from your purchase email. Reef checks it on this phone and sends nothing.")
            }

            TextField {
                id: tokenField
                width: parent.width
                label: qsTr("Licence")
                placeholderText: qsTr("Paste your licence")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                errorHighlight: dialog.problem.length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.enabled: dialog.canAccept
                EnterKey.onClicked: dialog.accept()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                objectName: "problem"
                visible: dialog.problem.length > 0
                wrapMode: Text.Wrap
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                // The check's own message is for developers.
                text: qsTr("This isn't a Reef licence. Copy it again from your purchase email.")
            }

            Label {
                objectName: "validFor"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: dialog.canAccept
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                text: qsTr("Valid licence for %1").arg(Reef.licenceTokenApp(dialog.token))
            }
        }

        VerticalScrollDecorator {}
    }
}
