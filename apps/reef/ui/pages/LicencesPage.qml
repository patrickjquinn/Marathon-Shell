// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Licences held on this phone. Each token is verified offline against the
// embedded Reef key; subscriptions refresh from the licence service.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import "../components/Texts.js" as Texts

Page {
    id: page

    function statusText(status, expiresText) {
        switch (status) {
        case "active": return expiresText.length > 0 ? qsTr("Active until %1").arg(expiresText)
                                                     : qsTr("Active")
        case "grace": return qsTr("Expired %1. Renew, or connect to check").arg(expiresText)
        case "expired": return qsTr("Expired %1").arg(expiresText)
        case "revoked": return qsTr("Revoked (refunded)")
        default: return qsTr("Not valid")
        }
    }

    SilicaListView {
        id: list
        anchors.fill: parent
        model: Reef.licenceModel

        PullDownMenu {
            busy: Reef.busy
            MenuItem {
                text: qsTr("Add licence")
                onClicked: pageStack.push(Qt.resolvedUrl("AddLicenceDialog.qml"))
            }
            MenuItem {
                text: qsTr("Refresh licences")
                visible: Reef.licenceModel.count > 0
                enabled: !Reef.busy
                onClicked: Reef.refreshLicences()
            }
        }

        header: Column {
            width: list.width

            PageHeader {
                title: qsTr("Licences")
                description: qsTr("Checked on this phone, no account needed")
            }
            // The last failure: a licence that verified but could not be
            // stored, a refresh, or a removal.
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                objectName: "lastError"
                visible: text.length > 0
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                text: Texts.message(Reef.lastError)
            }
        }

        delegate: ListItem {
            id: row

            required property string appId
            required property string title
            required property string status
            required property string expiresText

            // As tall as its lines need at a large text size.
            contentHeight: Math.max(Theme.itemSizeMedium, rowText.height + 2 * Theme.paddingSmall)
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Forget")
                    onClicked: row.remorseDelete(function() { Reef.removeLicence(row.appId) })
                }
            }

            Column {
                id: rowText
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                Label {
                    width: parent.width
                    text: row.title
                    textFormat: Text.PlainText
                    color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
                    truncationMode: TruncationMode.Fade
                }
                Label {
                    width: parent.width
                    text: page.statusText(row.status, row.expiresText)
                    color: row.status !== "active" || row.highlighted ? Theme.highlightColor : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
            }
        }

        // Below the header and any failure it shows, however tall a large
        // text size makes them (it sits a third of the way down otherwise).
        ViewPlaceholder {
            id: placeholder
            verticalOffset: Math.max(0, (list.headerItem ? list.headerItem.height : 0) + Theme.paddingLarge
                                        - (list.height / 3 - placeholder.height / 2))
            enabled: list.count === 0
            text: qsTr("No licences")
            hintText: qsTr("Apps you buy on reefstore.app come with a licence. Pull down to add one.")
        }

        VerticalScrollDecorator {}
    }
}
