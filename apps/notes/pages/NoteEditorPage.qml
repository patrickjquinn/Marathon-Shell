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
        const title = titleField.text.trim();
        const body = bodyArea.text;
        if (noteId < 0) {
            if (title === "" && body.trim() === "")
                return;
            store.save(Store.create(store.notes, title, body, Date.now()));
            noteId = store.notes[0].id;
        } else if (note && ((title || "Untitled") !== note.title || body !== note.content)) {
            store.save(Store.update(store.notes, noteId, title, body, Date.now()));
        }
    }

    function deleteNote() {
        remorse.execute(qsTr("Deleting"), function () {
            page.discarded = true;
            page.store.save(Store.remove(page.store.notes, page.noteId));
            page.pageContainer.pop();
        });
    }

    onStatusChanged: if (status === PageStatus.Deactivating) commit()
    // Loaded once: rebinding to the saved note would rewrite the text mid-typing.
    Component.onCompleted: {
        if (note) {
            titleField.text = note.title;
            bodyArea.text = note.content;
            autosaveTimer.stop();
        } else {
            titleField.forceActiveFocus();
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

            PageHeader {
                title: page.note ? page.note.title : qsTr("New note")
            }
            TextField {
                id: titleField

                objectName: "titleField"
                width: parent.width
                label: qsTr("Title")
                placeholderText: qsTr("Title")
                font.pixelSize: Theme.fontSizeLarge
                onTextChanged: autosaveTimer.restart()
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: bodyArea.focus = true
            }
            TextArea {
                id: bodyArea

                objectName: "bodyField"
                width: parent.width
                placeholderText: qsTr("Note")
                onTextChanged: autosaveTimer.restart()
            }
        }

        VerticalScrollDecorator {}
    }
}
