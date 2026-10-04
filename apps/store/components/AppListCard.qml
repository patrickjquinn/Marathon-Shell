pragma ComponentBehavior: Bound

import MarathonApp.Store
import MarathonUI.Containers
import MarathonUI.Theme
import QtQuick

// A card of AppRows, edge to edge inside the card's surface.
MCard {
    id: card

    required property var store
    property var model: []

    elevation: 2
    height: rows.height

    // MCard insets its content by MSpacing.md; the rows run edge to edge.
    Column {
        id: rows
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: -MSpacing.md

        Repeater {
            model: card.model
            delegate: AppRow {
                required property var modelData
                required property int index
                width: rows.width
                store: card.store
                app: modelData
                showDivider: index < card.model.length - 1
            }
        }
    }
}
