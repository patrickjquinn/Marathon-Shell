import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

CoverBackground {
    id: cover

    property var notes: []

    signal newNoteRequested

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        enabled: cover.notes.length === 0
        text: qsTr("No notes")
    }

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingMedium
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingSmall

        Repeater {
            objectName: "coverNotes"
            model: cover.notes.slice(0, 3)

            Label {
                required property var modelData

                width: parent.width
                text: modelData.title
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeMedium
            }
        }
    }

    CoverActionList {
        CoverAction {
            objectName: "newNoteAction"
            iconSource: "image://theme/icon-cover-new"
            onTriggered: cover.newNoteRequested()
        }
    }
}
