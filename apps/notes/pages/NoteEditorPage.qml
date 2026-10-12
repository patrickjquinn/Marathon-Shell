pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../NotesStore.js" as Store

Page {
    id: page

    property var store
    property int noteId: -1
    property bool discarded: false

    readonly property var note: store.notes.find(n => n.id === noteId)

    function commit() {
        autosaveTimer.stop();
        if (discarded)
            return;
        const body = bodyArea.text;
        if (noteId < 0) {
            if (body.trim() === "")
                return;
            store.save(Store.create(store.notes, body, Date.now()));
            noteId = store.notes[0].id;
        } else if (note && body !== Store.text(note)) {
            store.save(Store.update(store.notes, noteId, body, Date.now()));
        }
    }

    function deleteNote() {
        remorse.execute(qsTr("Deleted"), function () {
            page.discarded = true;
            page.store.save(Store.remove(page.store.notes, page.noteId));
            page.pageContainer.pop();
        });
    }

    onStatusChanged: if (status === PageStatus.Deactivating) commit()
    // Loaded once: rebinding to the saved note would rewrite the text mid-typing.
    Component.onCompleted: {
        if (note) {
            bodyArea.text = Store.text(note);
            autosaveTimer.stop();
        } else {
            bodyArea.forceActiveFocus();
        }
    }

    Timer {
        id: autosaveTimer

        interval: 800
        onTriggered: page.commit()
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            visible: page.note !== undefined
            MenuItem {
                objectName: "deleteNoteItem"
                text: qsTr("Delete")
                onClicked: page.deleteNote()
            }
            MenuItem {
                objectName: "pinNoteItem"
                text: page.note && page.note.pinned ? qsTr("Unpin") : qsTr("Pin to top")
                onClicked: {
                    page.commit();
                    page.store.save(Store.setPinned(page.store.notes, page.noteId, !page.note.pinned));
                }
            }
        }

        Column {
            id: column

            width: parent.width

            // The first line is the title, so the header carries the date instead.
            PageHeader {
                objectName: "header"
                title: page.note ? Store.when(page.note.timestamp, new Date()) : qsTr("New note")
            }
            TextArea {
                id: bodyArea

                objectName: "bodyField"
                width: parent.width
                backgroundStyle: TextEditor.NoBackground
                placeholderText: qsTr("Write a note")
                onTextChanged: autosaveTimer.restart()
            }
        }

        VerticalScrollDecorator {}
    }
}
