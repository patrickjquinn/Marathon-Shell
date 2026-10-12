import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../NotesStore.js" as Store

Page {
    id: page

    property var store

    SilicaListView {
        anchors.fill: parent
        header: PageHeader { title: qsTr("Notes") }
        model: page.store.notes

        PullDownMenu {
            MenuItem {
                text: qsTr("New note")
                onClicked: pageStack.push(Qt.resolvedUrl("NoteEditorPage.qml"), { store: page.store, noteId: -1 })
            }
        }

        ViewPlaceholder {
            enabled: page.store.notes.length === 0
            text: qsTr("No notes")
            hintText: qsTr("Pull down to add one")
        }

        delegate: ListItem {
            id: item

            required property var modelData

            contentHeight: Theme.itemSizeMedium
            Accessible.name: item.modelData.title
            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: item.remorseDelete(function () {
                        page.store.save(Store.remove(page.store.notes, item.modelData.id));
                    })
                }
            }
            onClicked: pageStack.push(Qt.resolvedUrl("NoteEditorPage.qml"), { store: page.store, noteId: item.modelData.id })

            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter

                Label {
                    width: parent.width
                    text: item.modelData.title
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: item.modelData.content
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
