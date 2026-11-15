// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The first start: what Pacific does for you, and the two choices worth
// making now (search engine, cookie banners).

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0

Dialog {
    id: dialog
    objectName: "firstRunPage"

    property var browser
    readonly property var engines: JSON.parse(Pacific.engines)

    allowedOrientations: Orientation.All
    backNavigation: false

    onAccepted: Pacific.setSettings(JSON.stringify({ first_run_done: true, cookie_banners: banners.checked, search_suggestions: suggestions.checked }))

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            DialogHeader {
                title: qsTr("Welcome to Pacific")
                acceptText: qsTr("Start browsing")
                cancelText: ""
            }

            Repeater {
                model: [
                    { icon: "image://theme/icon-m-browser-permissions", text: qsTr("Ads and trackers are blocked on every site, so pages load faster and use less data.") },
                    { icon: "image://theme/icon-m-browser-cookies", text: qsTr("Cookie banners are answered with \"Reject all\" for you.") },
                    { icon: "image://theme/icon-m-incognito", text: qsTr("Private tabs leave no history, cookies or cache behind.") },
                    { icon: "image://theme/icon-m-gesture", text: qsTr("Everything is in reach of your thumb. Swipe the address bar to change tabs.") }
                ]
                Row {
                    id: point
                    required property var modelData
                    x: Theme.horizontalPageMargin
                    width: column.width - 2 * x
                    spacing: Theme.paddingMedium
                    Icon {
                        source: point.modelData.icon
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        width: parent.width - Theme.iconSizeMedium - parent.spacing
                        wrapMode: Text.Wrap
                        text: point.modelData.text
                        color: Theme.highlightColor
                    }
                }
            }

            SectionHeader { text: qsTr("Choices") }

            ComboBox {
                label: qsTr("Search engine")
                currentIndex: {
                    for (var i = 0; i < dialog.engines.length; ++i)
                        if (dialog.engines[i].id === Pacific.defaultEngine)
                            return i
                    return 0
                }
                menu: ContextMenu {
                    Repeater {
                        model: dialog.engines
                        MenuItem {
                            required property var modelData
                            text: modelData.name
                            onClicked: Pacific.setDefaultEngine(modelData.id)
                        }
                    }
                }
            }
            TextSwitch {
                id: suggestions
                text: qsTr("Search suggestions")
                description: qsTr("Sends what you type to the search engine")
                checked: true
            }
            TextSwitch {
                id: banners
                text: qsTr("Reject cookie banners")
                checked: true
            }
        }
        VerticalScrollDecorator {}
    }
}
