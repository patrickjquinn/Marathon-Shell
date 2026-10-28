// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// Settings and diagnostics: installed release, repository pinning, update
// checks and the licence service address.

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

            SectionHeader { text: qsTr("This phone") }
            // The installed release, read from /etc/sailfish-release, not the
            // ssu release setting: Reef pins to what is actually running.
            DetailItem { label: qsTr("Sailfish OS"); value: Reef.installedRelease }
            DetailItem { label: qsTr("Architecture"); value: Reef.arch }

            SectionHeader { text: qsTr("Repository") }
            DetailItem { label: qsTr("Alias"); value: Reef.repoAlias }
            DetailItem {
                label: qsTr("State")
                value: Reef.repoState === "pinned" ? qsTr("Pinned to %1").arg(Reef.installedRelease)
                     : Reef.repoState === "drifted" ? qsTr("Set up for another release")
                     : Reef.repoState === "disabled" ? qsTr("Disabled")
                     : qsTr("Not registered")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                wrapMode: Text.WrapAnywhere
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: Reef.registeredRepoUrl
            }
            Column {
                width: parent.width
                visible: Reef.repoState !== "pinned"
                spacing: Theme.paddingSmall

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    text: qsTr("Repair runs:")
                }
                Repeater {
                    model: Reef.repairCommands()
                    Label {
                        required property string modelData
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        wrapMode: Text.WrapAnywhere
                        font.family: "monospace"
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.highlightColor
                        text: modelData
                    }
                }
                Button {
                    objectName: "repairButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    preferredWidth: Theme.buttonWidthMedium
                    text: qsTr("Repair repository")
                    enabled: !Reef.busy
                    onClicked: Reef.repairRepository()
                }
            }

            SectionHeader { text: qsTr("Updates") }
            TextSwitch {
                text: qsTr("Check for updates when Reef opens")
                description: qsTr("Checks Reef's apps only, not system updates")
                checked: Reef.refreshOnStart
                onCheckedChanged: Reef.refreshOnStart = checked
            }
            // Read by `shipwright-reef --check-updates`, which a systemd user
            // timer starts every 4 hours (reef/client/app/packaging/systemd/;
            // backgroundCheckDays 1 is "every few hours", src/check.rs). The
            // setting is written only when the user picks an item, never
            // while the page is created; picking one turns the timer on, or
            // off for Never.
            ComboBox {
                label: qsTr("Check in the background")
                description: qsTr("Notifies you when your apps have updates")
                currentIndex: !Reef.backgroundCheckAsked || Reef.backgroundCheckDays === 0 ? 0
                            : Reef.backgroundCheckDays === 1 ? 1 : 2
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("Never")
                        onClicked: Reef.backgroundCheckDays = 0
                    }
                    MenuItem {
                        text: qsTr("Every few hours")
                        onClicked: Reef.backgroundCheckDays = 1
                    }
                    MenuItem {
                        text: qsTr("Weekly")
                        onClicked: Reef.backgroundCheckDays = 7
                    }
                }
            }
            // ConnMan's connection in use, asked by the check itself.
            TextSwitch {
                objectName: "wifiOnly"
                text: qsTr("Only on Wi-Fi")
                description: qsTr("Background checks never use mobile data")
                visible: Reef.backgroundCheckAsked && Reef.backgroundCheckDays > 0
                checked: Reef.backgroundWifiOnly
                onClicked: Reef.backgroundWifiOnly = checked
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
