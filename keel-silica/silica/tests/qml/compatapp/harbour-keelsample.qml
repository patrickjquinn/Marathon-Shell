// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sample app in the style of Harbour apps (SDK template layout), used by
// tst_compat_app.qml. Written for Keel; no third-party code.
import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"

ApplicationWindow {
    id: app

    property alias notes: notesModel
    property string lastAction

    function addNote(title, priority, pinned) {
        notesModel.append({ "title": title, "priority": priority, "pinned": pinned })
        lastAction = "added " + title
    }

    ListModel {
        id: notesModel
        ListElement { title: "Buy milk"; priority: "low"; pinned: false }
        ListElement { title: "Call Ada"; priority: "high"; pinned: true }
    }

    initialPage: Component { FirstPage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations
    _defaultPageOrientations: Orientation.All
}
