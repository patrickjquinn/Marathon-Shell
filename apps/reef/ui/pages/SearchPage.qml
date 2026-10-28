// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// Search: the field, then the matching apps, best first (reef-backend
// ranks them: rows.rs, filter_rows), in a list built as it scrolls.
// Leaving the page clears the search, so the other lists show every app.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import "../components"

Page {
    id: page

    Component.onDestruction: Reef.searchText = ""

    SilicaListView {
        id: list
        objectName: "searchList"
        anchors.fill: parent
        model: Reef.searchText.length > 0 ? Reef.catalogueModel : null
        header: Column {
            width: list.width
            PageHeader {
                title: qsTr("Search")
            }
            SearchField {
                id: field
                objectName: "search"
                width: parent.width
                placeholderText: qsTr("Search apps")
                text: Reef.searchText
                onTextChanged: Reef.searchText = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
                Component.onCompleted: forceActiveFocus()
            }
        }
        delegate: PackageDelegate {
            onClicked: pageStack.push(Qt.resolvedUrl("PackagePage.qml"), { packageName: name })
        }

        ViewPlaceholder {
            enabled: Reef.searchText.length > 0 && list.count === 0 && !Reef.busy
            text: qsTr("No apps match")
            hintText: qsTr("Try another word, or fewer words.")
        }

        VerticalScrollDecorator {}
    }
}
