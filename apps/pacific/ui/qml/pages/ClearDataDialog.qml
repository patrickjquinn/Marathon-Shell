// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Clear browsing data from a time range.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0

Dialog {
    id: dialog
    objectName: "clearDataDialog"

    property bool historyOnly: false
    readonly property var ranges: ["last_hour", "today", "last_week", "last_four_weeks", "all"]

    allowedOrientations: Orientation.All
    canAccept: history.checked || cookies.checked || cache.checked || downloads.checked || sites.checked

    onAccepted: Pacific.clearData(ranges[range.currentIndex], JSON.stringify({
        history: history.checked, cookies: cookies.checked, cache: cache.checked,
        downloads: downloads.checked, site_settings: sites.checked, session: history.checked && range.currentIndex === 4
    }))

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            DialogHeader {
                title: qsTr("Clear browsing data")
                acceptText: qsTr("Clear")
            }
            ComboBox {
                id: range
                label: qsTr("From")
                currentIndex: 0
                menu: ContextMenu {
                    MenuItem { text: qsTr("The last hour") }
                    MenuItem { text: qsTr("Today") }
                    MenuItem { text: qsTr("The last seven days") }
                    MenuItem { text: qsTr("The last four weeks") }
                    MenuItem { text: qsTr("All time") }
                }
            }
            TextSwitch {
                id: history
                text: qsTr("History")
                description: qsTr("Pages you visited and what you typed in the address bar. Bookmarks stay.")
                checked: true
            }
            TextSwitch {
                id: cookies
                text: qsTr("Cookies and site data")
                description: qsTr("Signs you out of most sites")
                checked: !dialog.historyOnly
            }
            TextSwitch {
                id: cache
                text: qsTr("Cached pages and images")
                checked: !dialog.historyOnly
            }
            TextSwitch {
                id: downloads
                text: qsTr("Download list")
                description: qsTr("The files stay in Downloads")
                checked: false
            }
            TextSwitch {
                id: sites
                text: qsTr("Site settings")
                description: qsTr("Zoom, permissions and other choices made for sites")
                checked: false
            }
        }
        VerticalScrollDecorator {}
    }
}
