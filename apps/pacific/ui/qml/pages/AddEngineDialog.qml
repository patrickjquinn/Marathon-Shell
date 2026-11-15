// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Add a search engine from its results address, with %s for the words.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Shipwright.Pacific 1.0

Dialog {
    id: dialog

    property string error

    allowedOrientations: Orientation.All
    canAccept: name.text.trim() !== "" && address.text.indexOf("%s") > 0

    onAccepted: Pacific.addEngine(name.text, keyword.text, address.text, suggest.text)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            DialogHeader {
                title: qsTr("Add search engine")
            }
            TextField {
                id: name
                width: parent.width
                label: qsTr("Name")
                placeholderText: qsTr("Name")
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: address.forceActiveFocus()
            }
            TextField {
                id: address
                width: parent.width
                label: qsTr("Results address, %s for the search words")
                placeholderText: "https://example.com/search?q=%s" // i18n: literal
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: keyword.forceActiveFocus()
            }
            TextField {
                id: keyword
                width: parent.width
                label: qsTr("Keyword (optional)")
                placeholderText: qsTr("Keyword (optional)")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: suggest.forceActiveFocus()
            }
            TextField {
                id: suggest
                width: parent.width
                label: qsTr("Suggestions address (optional)")
                placeholderText: qsTr("Suggestions address (optional)")
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }
        VerticalScrollDecorator {}
    }
}
