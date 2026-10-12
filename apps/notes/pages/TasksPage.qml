pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../NotesStore.js" as Store

// Tasks are the "- [ ] text" lines of every note.
Page {
    id: page

    property var store

    SilicaListView {
        id: view

        objectName: "tasksView"
        anchors.fill: parent
        header: PageHeader { title: qsTr("Tasks") }
        model: Store.tasks(page.store.notes)

        ViewPlaceholder {
            enabled: view.count === 0
            text: qsTr("No tasks")
            hintText: qsTr("Write a line like \"- [ ] buy milk\" in a note")
        }

        delegate: ListItem {
            id: item

            required property var modelData

            contentHeight: Theme.itemSizeMedium
            Accessible.name: qsTr("Open %1").arg(modelData.noteTitle)
            onClicked: pageStack.push(Qt.resolvedUrl("NoteEditorPage.qml"), { store: page.store, noteId: item.modelData.noteId })

            Switch {
                id: check

                objectName: "taskSwitch"
                anchors.verticalCenter: parent.verticalCenter
                checked: item.modelData.checked
                automaticCheck: false
                Accessible.name: item.modelData.text
                onClicked: page.store.save(Store.toggleTask(page.store.notes, item.modelData.noteId, item.modelData.line, Date.now()))
            }
            Column {
                anchors {
                    left: check.right
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: item.modelData.text
                    font.strikeout: item.modelData.checked
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : item.modelData.checked ? Theme.secondaryColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: item.modelData.noteTitle
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
