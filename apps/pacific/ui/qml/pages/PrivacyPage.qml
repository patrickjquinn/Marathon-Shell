// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Privacy and security: what Pacific has blocked, the protections, the
// filter lists, sites with their own settings, and clearing data.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Shipwright.Pacific 1.0
import "../js/logic.js" as Logic

Page {
    id: page
    objectName: "privacyPage"

    property var browser
    readonly property var s: JSON.parse(Pacific.settings)
    property var totals: ({
            totals: {
                blocked: 0,
                cookie_banners: 0,
                https_upgrades: 0,
                bytes_saved_estimate: 0
            },
            rules: 0
        })

    allowedOrientations: Orientation.All

    function set(key: var, value: var): void {
        var patch = {};
        patch[key] = value;
        Pacific.setSettings(JSON.stringify(patch));
    }

    Component.onCompleted: Pacific.loadTotals()
    Connections {
        target: Pacific
        function onTotalsReady(json) {
            page.totals = JSON.parse(json);
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Clear browsing data")
                onClicked: pageStack.push(Qt.resolvedUrl("ClearDataDialog.qml"))
            }
            MenuItem {
                text: Pacific.listsUpdating ? qsTr("Updating filter lists") : qsTr("Update filter lists")
                enabled: !Pacific.listsUpdating
                onClicked: Pacific.updateLists(true)
            }
        }

        Column {
            id: column
            width: parent.width

            PageHeader {
                title: qsTr("Privacy and security")
                description: qsTr("No telemetry, ever")
            }

            Row {
                objectName: "dashboard"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                Repeater {
                    model: [
                        {
                            n: page.totals.totals.blocked,
                            t: qsTr("ads and trackers blocked")
                        },
                        {
                            n: page.totals.totals.cookie_banners,
                            t: qsTr("cookie banners rejected")
                        },
                        {
                            n: page.totals.totals.https_upgrades,
                            t: qsTr("connections upgraded")
                        }
                    ]
                    Column {
                        id: figure
                        required property var modelData
                        width: parent.width / 3
                        Label {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: figure.modelData.n
                            font.pixelSize: Theme.fontSizeHuge
                            color: Theme.highlightColor
                        }
                        Label {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: figure.modelData.t
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryHighlightColor
                        }
                    }
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                topPadding: Theme.paddingMedium
                visible: page.totals.totals.bytes_saved_estimate > 0
                text: qsTr("About %1 of data not downloaded").arg(Logic.size(page.totals.totals.bytes_saved_estimate))
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
            }

            SectionHeader {
                text: qsTr("Protection")
            }

            TextSwitch {
                objectName: "blockingSwitch"
                text: qsTr("Block ads and trackers")
                description: page.s.blocking && page.browser.protectionIncomplete ? qsTr("Still preparing %n filter list(s)", "", page.browser.missingFilters.length) : (page.totals.rules > 0 ? qsTr("%1 filter rules").arg(page.totals.rules.toLocaleString(Qt.locale(), "f", 0)) : "")
                checked: page.s.blocking
                onClicked: page.set("blocking", checked)
            }
            ValueButton {
                label: qsTr("Filter lists")
                value: Pacific.listsUpdating ? qsTr("Updating") : ""
                onClicked: pageStack.push(Qt.resolvedUrl("FilterListsPage.qml"))
            }
            TextSwitch {
                text: qsTr("Reject cookie banners")
                description: Pacific.autoconsentScript.length > 0 ? qsTr("Answers cookie banners with \"Reject all\" for you") : qsTr("Not available in this build of Pacific")
                enabled: Pacific.autoconsentScript.length > 0
                checked: page.s.cookie_banners
                onClicked: page.set("cookie_banners", checked)
            }
            TextSwitch {
                text: qsTr("HTTPS first")
                description: qsTr("Uses secure connections, and asks before opening a site without one")
                checked: page.s.https_first
                onClicked: page.set("https_first", checked)
            }
            TextSwitch {
                text: qsTr("Tell sites not to sell or share my data")
                description: qsTr("Global Privacy Control")
                checked: page.s.global_privacy_control
                onClicked: page.set("global_privacy_control", checked)
            }

            SectionHeader {
                text: qsTr("Data")
            }

            ComboBox {
                label: qsTr("Keep history")
                currentIndex: [30, 90, 180, 365, 0].indexOf(page.s.history_days)
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("For a month")
                        onClicked: page.set("history_days", 30)
                    }
                    MenuItem {
                        text: qsTr("For three months")
                        onClicked: page.set("history_days", 90)
                    }
                    MenuItem {
                        text: qsTr("For six months")
                        onClicked: page.set("history_days", 180)
                    }
                    MenuItem {
                        text: qsTr("For a year")
                        onClicked: page.set("history_days", 365)
                    }
                    MenuItem {
                        text: qsTr("Always")
                        onClicked: page.set("history_days", 0)
                    }
                }
            }
            TextSwitch {
                text: qsTr("Clear browsing data when Pacific closes")
                checked: page.s.clear_on_exit
                onClicked: page.set("clear_on_exit", checked)
            }
            ValueButton {
                label: qsTr("Site settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SitesPage.qml"))
            }
            ValueButton {
                label: qsTr("Sites allowed over HTTP")
                onClicked: pageStack.push(Qt.resolvedUrl("SitesPage.qml"), {
                    kind: "httpsExceptions"
                })
            }
            Button {
                objectName: "clearDataButton"
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Clear browsing data")
                onClicked: pageStack.push(Qt.resolvedUrl("ClearDataDialog.qml"))
            }
        }
        VerticalScrollDecorator {}
    }
}
