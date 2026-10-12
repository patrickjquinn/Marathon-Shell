pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../NotesStore.js" as Store

Page {
    id: page

    property var store
    // Set to show one folder; "" is the untagged notes.
    property var folder: undefined
    property string searchText: ""

    readonly property bool inFolder: folder !== undefined
    readonly property var scope: inFolder ? Store.inFolder(store.notes, folder) : store.notes
    readonly property var shown: Store.sorted(Store.search(scope, searchText))

    SilicaListView {
        id: view

        objectName: "notesView"
        anchors.fill: parent
        model: page.shown

        header: Column {
            width: view.width

            PageHeader {
                title: !page.inFolder ? qsTr("Notes") : page.folder === "" ? qsTr("Untagged") : "#" + page.folder
            }
            SearchField {
                objectName: "searchField"
                width: parent.width
                placeholderText: qsTr("Search notes")
                visible: page.scope.length > 0
                onTextChanged: page.searchText = text
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Folders")
                visible: !page.inFolder
                onClicked: pageStack.push(Qt.resolvedUrl("FoldersPage.qml"), { store: page.store })
            }
            MenuItem {
                text: qsTr("Tasks")
                visible: !page.inFolder
                onClicked: pageStack.push(Qt.resolvedUrl("TasksPage.qml"), { store: page.store })
            }
            MenuItem {
                objectName: "newNoteItem"
                text: qsTr("New note")
                onClicked: pageStack.push(Qt.resolvedUrl("NoteEditorPage.qml"), { store: page.store, noteId: -1 })
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: page.shown.length === 0
            text: page.scope.length === 0 ? qsTr("No notes") : qsTr("No matching notes")
            hintText: page.scope.length === 0 ? qsTr("Pull down to add one") : qsTr("Try a different word")
        }

        delegate: ListItem {
            id: item

            required property var modelData

            contentHeight: Theme.itemSizeLarge
            Accessible.name: (modelData.pinned ? qsTr("Pinned") + ", " : "") + titleLabel.text
            menu: ContextMenu {
                MenuItem {
                    objectName: "pinItem"
                    text: item.modelData.pinned ? qsTr("Unpin") : qsTr("Pin to top")
                    onClicked: page.store.save(Store.setPinned(page.store.notes, item.modelData.id, !item.modelData.pinned))
                }
                MenuItem {
                    objectName: "deleteItem"
                    text: qsTr("Delete")
                    onClicked: item.remorseDelete(function () {
                        page.store.save(Store.remove(page.store.notes, item.modelData.id));
                    })
                }
            }
            onClicked: pageStack.push(Qt.resolvedUrl("NoteEditorPage.qml"), { store: page.store, noteId: item.modelData.id })

            Icon {
                id: pin

                x: Theme.horizontalPageMargin
                anchors.verticalCenter: titleLabel.verticalCenter
                visible: item.modelData.pinned === true
                source: "image://theme/icon-s-favorite"
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            Label {
                id: titleLabel

                anchors {
                    left: pin.visible ? pin.right : parent.left
                    leftMargin: pin.visible ? Theme.paddingSmall : Theme.horizontalPageMargin
                    right: dateLabel.left
                    rightMargin: Theme.paddingMedium
                    bottom: parent.verticalCenter
                }
                text: item.modelData.title || qsTr("Untitled")
                truncationMode: TruncationMode.Fade
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            Label {
                id: dateLabel

                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    baseline: titleLabel.baseline
                }
                text: Store.when(item.modelData.timestamp, new Date())
                font.pixelSize: Theme.fontSizeExtraSmall
                color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            }
            Label {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    top: parent.verticalCenter
                }
                text: Store.preview(item.modelData)
                font.pixelSize: Theme.fontSizeSmall
                truncationMode: TruncationMode.Fade
                color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            }
        }

        VerticalScrollDecorator {}
    }
}
