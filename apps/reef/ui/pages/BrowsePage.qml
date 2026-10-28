// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Every app of one category, one collection, or the whole store: a list
// built as it scrolls (Reef.browseModel, filled by Reef.browse), so it
// stays quick with thousands of apps.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import "../components"

Page {
    id: page

    // "category", "collection" or "all", and the category or collection.
    property string kind: "all"
    property string browseId
    property string title
    // A collection's line about itself, under the title; else the count.
    property string subtitle

    // browseModel is shared: show this page's list again when coming back
    // to it from another browse page.
    onStatusChanged: if (status === PageStatus.Activating) Reef.browse(kind, browseId)
    Component.onCompleted: Reef.browse(kind, browseId)

    SilicaListView {
        id: list
        objectName: "browseList"
        anchors.fill: parent
        model: Reef.browseModel
        header: PageHeader {
            title: page.title
            description: page.subtitle.length > 0 ? page.subtitle : qsTr("%n app(s)", "", list.count)
        }
        delegate: PackageDelegate {
            onClicked: pageStack.push(Qt.resolvedUrl("PackagePage.qml"), { packageName: name })
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Search")
                onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"))
            }
        }

        ViewPlaceholder {
            enabled: list.count === 0 && !Reef.busy
            text: qsTr("Nothing here yet")
            hintText: qsTr("No apps here are tested on Sailfish OS %1 yet.").arg(Reef.installedRelease)
        }

        VerticalScrollDecorator {}
    }
}
