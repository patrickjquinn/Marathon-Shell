pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../NotesStore.js" as Store

// The latest note, as written: its first line, then as much of the rest as fits.
CoverBackground {
    id: cover

    property var notes: []
    readonly property var latest: notes.length > 0 ? notes[0] : null
    readonly property var lines: {
        if (!latest)
            return [];
        const all = Store.text(latest).split("\n");
        return all.slice(all.findIndex(l => l.trim() !== "") + 1);
    }

    signal newNoteRequested

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: cover.latest === null
        text: qsTr("No notes")
        icon.source: "image://theme/icon-l-note"
    }

    Item {
        id: page

        visible: cover.latest !== null
        clip: true
        anchors {
            fill: parent
            leftMargin: Theme.paddingLarge
            rightMargin: Theme.paddingLarge
            topMargin: Theme.paddingLarge
            bottomMargin: cover.coverActionArea.height
        }

        Column {
            width: parent.width
            spacing: Theme.paddingSmall

            Label {
                objectName: "coverNoteTitle"
                width: parent.width
                text: cover.latest ? Store.titleOf(Store.text(cover.latest)) || qsTr("Untitled") : ""
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeSmall
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.fontSizeExtraSmall
                color: Theme.highlightColor
            }
            Label {
                objectName: "coverNoteBody"
                width: parent.width
                text: cover.lines.join("\n").trim()
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeExtraSmall
                lineHeight: 1.1
            }
        }
    }

    OpacityRampEffect {
        sourceItem: page
        direction: OpacityRamp.TopToBottom
        offset: 0.6
        slope: 2.5
    }

    CoverActionList {
        CoverAction {
            objectName: "newNoteAction"
            iconSource: "image://theme/icon-cover-new"
            onTriggered: cover.newNoteRequested()
        }
    }
}
