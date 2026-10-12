import QtQuick
import Sailfish.Silica 1.0
import "../NotesStore.js" as Store

Page {
    id: page

    property var store
    property int noteId: -1

    readonly property var note: store.notes.find(n => n.id === noteId)

    function commit() {
        autosaveTimer.stop();
        const title = titleField.text.trim();
        const body = bodyArea.text;
        if (noteId < 0) {
            if (title === "" && body.trim() === "")
                return;
            store.save(Store.create(store.notes, title, body, Date.now()));
            noteId = store.notes[0].id;
        } else if (!note || title !== note.title || body !== note.content) {
            store.save(Store.update(store.notes, noteId, title, body, Date.now()));
        }
    }

    onStatusChanged: if (status === PageStatus.Deactivating) commit()

    Timer {
        id: autosaveTimer

        interval: 800
        onTriggered: page.commit()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width

            PageHeader { title: page.noteId < 0 ? qsTr("New note") : qsTr("Edit note") }
            TextField {
                id: titleField

                objectName: "titleField"
                width: parent.width
                label: qsTr("Title")
                placeholderText: qsTr("Title")
                text: page.note ? page.note.title : ""
                onTextChanged: autosaveTimer.restart()
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: bodyArea.focus = true
            }
            TextArea {
                id: bodyArea

                objectName: "bodyField"
                width: parent.width
                placeholderText: qsTr("Note")
                text: page.note ? page.note.content : ""
                onTextChanged: autosaveTimer.restart()
            }
        }

        VerticalScrollDecorator {}
    }
}
