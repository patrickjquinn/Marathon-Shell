pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../NotesStore.js" as Store

Page {
    id: page

    property var store

    SilicaListView {
        objectName: "foldersView"
        anchors.fill: parent
        header: PageHeader {
            title: qsTr("Folders")
        }
        model: Store.folders(page.store.notes)

        ViewPlaceholder {
            enabled: page.store.notes.length === 0
            text: qsTr("No folders")
            hintText: qsTr("Add a #tag to a note to file it here")
        }

        delegate: ListItem {
            id: item

            required property var modelData

            contentHeight: Theme.itemSizeMedium
            Accessible.name: nameLabel.text + ", " + countLabel.text
            onClicked: pageStack.push(Qt.resolvedUrl("NotesPage.qml"), {
                store: page.store,
                folder: item.modelData.tag
            })

            Icon {
                id: icon

                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                source: item.modelData.tag === "" ? "image://theme/icon-m-note" : "image://theme/icon-m-folder"
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            Label {
                id: nameLabel

                anchors {
                    left: icon.right
                    leftMargin: Theme.paddingLarge
                    right: countLabel.left
                    rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }
                text: item.modelData.tag === "" ? qsTr("Untagged") : "#" + item.modelData.tag
                truncationMode: TruncationMode.Fade
                color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
            Label {
                id: countLabel

                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: item.modelData.count === 1 ? qsTr("1 note") : qsTr("%1 notes").arg(item.modelData.count)
                color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            }
        }

        VerticalScrollDecorator {}
    }
}
