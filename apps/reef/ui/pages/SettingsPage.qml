// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Settings and diagnostics: where the store is, refreshing, and the
// licence service address.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import "../components/Texts.js" as Texts

Page {
    id: page

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width

            PageHeader { title: qsTr("Settings") }

            SectionHeader { text: qsTr("Store") }
            DetailItem { label: qsTr("Architecture"); value: Reef.arch }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WrapAnywhere
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: Reef.storeUrl
            }
            TextSwitch {
                text: qsTr("Refresh when Reef opens")
                checked: Reef.refreshOnStart
                onCheckedChanged: Reef.refreshOnStart = checked
            }

            SectionHeader { text: qsTr("Licences") }
            // Here, not in the store's pulley, which keeps to four items.
            BackgroundItem {
                objectName: "licencesItem"
                width: parent.width
                onClicked: pageStack.push(Qt.resolvedUrl("LicencesPage.qml"))
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Your licences")
                    color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
            }
            TextField {
                id: serverField
                width: parent.width
                label: qsTr("Licence service")
                placeholderText: qsTr("https://…")
                text: Reef.licenceServer
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                errorHighlight: !Texts.isServiceUrl(text.trim())
                description: errorHighlight ? qsTr("Enter an https:// address") : ""

                function commit() {
                    var url = text.trim()
                    if (Texts.isServiceUrl(url))
                        Reef.licenceServer = url
                }

                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: { commit(); focus = false }
                onActiveFocusChanged: if (!activeFocus) commit()
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: qsTr("Used only to renew subscriptions and check for refunds. One-off licences work offline.")
            }
        }

        VerticalScrollDecorator {}
    }

    // Leaving with Back does not always take the focus first: keep a valid
    // edit then too.
    onStatusChanged: if (status === PageStatus.Deactivating) serverField.commit()
}
